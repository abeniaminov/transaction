% -*- coding: utf8 -*-
%%---- BEGIN COPYRIGHT -------------------------------------------------------
%% This Source Code Form is subject to the terms of the Mozilla Public
%% License, v. 2.0. If a copy of the MPL was not distributed with this
%% file, You can obtain one at http://mozilla.org/MPL/2.0/.
%%
%%---- END COPYRIGHT ---------------------------------------------------------

%%%-------------------------------------------------------------------
%%% @author Alexander Beniaminov
%%% @copyright (C) 2015,
%%% @doc
%%%
%%% @end
%%% Created : 16. Окт. 2015 12:33
%%%-------------------------------------------------------------------
%%=============================================================================
%% @doc Transaction gen_server behaviour
%%
%% This behaviour was inspired by MVCC ( MultiVersion Concurrency Control).
-module(tgen_server).
-author("Alexander Beniaminov").
-behaviour(gen_server).

-define(DEADLOCK_TIMEOUT, 500).

%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------

-export([start/4, start/5, start_link/4, start_link/5, stop/2]).

-export([lock/2, lock/3]).

-export([init/1]).

%% ------------------------------------------------------------------
%% gen_server Function Exports
%% ------------------------------------------------------------------

-export([call/3, call/4]).

-export([handle_call/3, handle_cast/2, handle_info/2,
  terminate/2, code_change/3]).
-export([gambler_bm/0, gambler_fm/1]).


-type version_level() :: record_version |no_record_version.
-type wait() :: wait | no_wait.
-type overwrite() :: boolean().
-type lock_result() :: 'deadlock' | 'busy' | 'lost'|  'ok'.
-type transaction() :: #{tr_id => reference(), tr_bet => integer(), i_level => version_level(), wait => wait(), overwrite => overwrite()}.
-type tr_options() :: #{i_level => version_level(), wait => wait(), overwrite => overwrite()}.
-export_type([version_level/0, wait/0, overwrite/0, transaction/0, lock_result/0, tr_options/0]).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

-callback init(Tr :: transaction(), Args :: term()) ->
  {ok, State :: term()} | {ok, State :: term(), timeout() | hibernate} |
  {stop, Reason :: term()} | ignore.

-callback handle_call(Tr :: transaction(), Request :: term(), From :: {pid(), Tag :: term()},
  State :: term()) ->
  {reply, Reply :: term(), NewState :: term()} |
  {reply, Reply :: term(), NewState :: term(), timeout() | hibernate} |
  {noreply, NewState :: term()} |
  {noreply, NewState :: term(), timeout() | hibernate} |
  {stop, Reason :: term(), Reply :: term(), NewState :: term()} |
  {stop, Reason :: term(), NewState :: term()}.

-callback handle_info(Tr :: transaction(), Info :: timeout | term(), State :: term()) ->
  {noreply, NewState :: term()} |
  {noreply, NewState :: term(), timeout() | hibernate} |
  {stop, Reason :: term(), NewState :: term()}.

-callback terminate(Tr :: transaction(), Reason :: (normal | shutdown | {shutdown, term()} |
term()),
  State :: term()) ->
  term().

-callback code_change(OldVsn :: (term() | {down, term()}), State :: term(),
  Extra :: term()) ->
  {ok, NewState :: term()} | {error, Reason :: term()}.

-callback format_status(Opt, StatusData) -> Status when
  Opt :: 'normal' | 'terminate',
  StatusData :: [PDict | State],
  PDict :: [{Key :: term(), Value :: term()}],
  State :: term(),
  Status :: term().

-optional_callbacks([format_status/2]).


%% @doc Start tgen_server process.
%%
%% There are start and start_link functions similar to the gen_server but
%% with additional parameter Tr - transaction::transaction()
%%
%% @end

start(Mod, Args, Tr, Options) ->
  gen_server:start(?MODULE, [Mod, Args, self(), Tr], Options).

start(Name, Mod, Args, Tr, Options) ->
  gen_server:start(Name, ?MODULE, [Mod, Args, self(), Tr], Options).

start_link(Mod, Args, Tr, Options) ->
  gen_server:start_link(?MODULE, [Mod, Args, self(), Tr], Options).

start_link(Name, Mod, Args, Tr, Options) ->
  gen_server:start_link(Name, ?MODULE, [Mod, Args, self(), Tr], Options).



-spec lock(term(), pid(), transaction()) -> lock_result().
%% @doc Try to lock process for read and update.
%%
%%  First parameter is the result of the previous operation
%%  This function can be used for a simple workflow without many nested conditional expressions
%%
%%
%% @end
lock(Res, Pid, Tr) ->
  case Res of
    deadlock -> deadlock;
    busy -> busy;
    lost -> lost;
    _ -> lock(Pid, Tr)
  end.


-spec lock(pid(), transaction()) -> lock_result().
%% @doc Try to lock process for update.
%%
%%
%%
%%
%%
%% @end
lock(Pid, Tr) ->
  call(Pid, Tr, lock).



stop(Pid, Tr) ->
  call(Pid, Tr, stop).

-spec call(term(), pid(), transaction(), term()) -> term().
%% @doc Transaction analog of gen_server call function
%%
%% First parameter is the result of the previous operation
%% This function can be used for a simple workflow without many nested conditional expressions
%%
%%
%% @end
call(Res, Pid, Tr, Request) ->
  case Res of
    deadlock -> deadlock;
    busy -> busy;
    lost -> lost;
    _ -> call(Pid, Tr, Request)
  end.


-spec call(pid(), transaction(), term()) -> term().
%% @doc Transaction gen_server call function
%%
%%
%%
%%
%% @end
call(Pid, #{tr_id := TrID, tr_bet := Bet} = Tr, Request) ->
  flush_unlock(),
  R = gen_server:call(Pid, {Tr, Request}),
  case R of
    locked ->
      receive
        {unlocked, TrID} ->
          call(Pid, Tr, Request)
      after ?DEADLOCK_TIMEOUT ->
        {atid, ATID, ActiveClPid, ActiveBet} = gen_server:call(Pid, get_atid),
        GamblerPid = case ActiveBet < Bet of
                       true ->
                         GPid = spawn(?MODULE, gambler_bm, []),
                         ActiveClPid ! {fm, TrID, Bet, self()},
                         GPid;
                       false ->
                         spawn(?MODULE, gambler_fm, [{bm, ATID, ActiveBet, ActiveClPid}])
                     end,

        fun F() ->
          receive
            {BFM, BmTrID, BmBet, BmClient} ->
              GamblerPid ! {BFM, BmTrID, BmBet, BmClient},
              F();
            {unlocked, TrID} ->
              gambler_stop(GamblerPid),
              flush_gambler(),
              call(Pid, Tr, Request);
            you_lost ->
              gambler_stop(GamblerPid),
              transaction:rollback(Tr),

              timer:sleep(?DEADLOCK_TIMEOUT),
              flush_gambler(),
              deadlock
          end
        end()

      end;
    _ -> R
  end.

gambler_stop(GamblerPid) ->
  case is_process_alive(GamblerPid) of
    true -> GamblerPid ! stop;
    false -> stopped
  end.



gambler_bm() ->
  receive
    {bm, BmTrID, BmBet, BmClient} ->
      gambler_fm({bm, BmTrID, BmBet, BmClient});
    stop ->
      %flush_gambler(),
      stopped

  end.


gambler_fm({bm, BmTrID, BmBet, BmClient}) ->

  receive
    {fm, FmTrID, FmBet, FmClient} ->
      if
        FmBet > BmBet ->
          BmClient ! {fm, FmTrID, FmBet, FmClient};
        FmBet < BmBet ->
          FmClient ! {bm, BmTrID, BmBet, BmClient};
        FmBet == BmBet ->
          BmClient ! you_lost

      end,
      gambler_fm({bm, BmTrID, BmBet, BmClient});
    stop ->
      %flush_gambler(),
      stopped
  end.


flush_gambler() ->
  receive
    {fm, _TrID, _Bet, _C} ->
      flush_gambler();
    {bm, _TrID, _Bet, _C} ->
      flush_gambler()
  after 0 -> ok
  end.

%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------

init([Mod, Args, ClPid, #{tr_id := TrID, tr_bet := Bet} = Tr]) ->
  VarState = #{
    tr_state => starting,
    active_tid => TrID,
    active_bet => Bet,
    client_pid => ClPid,
    committed_tid => TrID,
    module => Mod},
  case Mod:init(Tr, Args) of
    {ok, State} ->
      transaction:write_transaction_log(Tr, self()),
      {ok, VarState#{TrID => State}};
    ignore ->
      ignore;
    {ok, State, Timeout} ->
      transaction:write_transaction_log(Tr, self()),
      {ok, VarState#{TrID => State}, Timeout};
    {stop, Reason} ->
      {stop, Reason};
    Error ->
      {stop, {bad_return, {Mod, init, Error}}}
  end.


handle_call(get_atid, _From, #{active_tid := ATID, active_bet := Bet, client_pid := ClPid} = State) ->
  {reply, {atid, ATID, ClPid, Bet}, State};

handle_call({Tr, commit}, _From, State) ->
  CommittedState = commit_by_context(Tr, State),
  case maps:get(tr_state, CommittedState) of
    stopping ->
      {stop, normal, ok, CommittedState};
    _ ->
      {reply, ok, CommittedState}
  end;


handle_call({Tr, rollback}, _From, State) ->
  RolledBackState = rollback_by_context(Tr, State),
  case maps:get(tr_state, RolledBackState) of
    stopping ->
      {stop, normal, ok, RolledBackState};
    _ ->
      {reply, ok, RolledBackState}
  end;



handle_call({#{tr_id := TrID, tr_bet := Bet} = Tr, lock},
  {From, _Ref}, #{tr_state := committed, module := _Mod, committed_tid := CTID} = State) ->
  CommittedVState = maps:get(CTID, State),
  NewState = State#{tr_state => active, active_bet => Bet, client_pid => From, active_tid => TrID, TrID => CommittedVState},
  transaction:write_transaction_log(Tr, self()),
  {reply, ok, NewState};

handle_call({#{tr_id := TrID} = _Tr, lock},
  _From, #{tr_state := TrSt, active_tid := ATID} = State)
  when
  TrID =:= ATID, TrSt =:= active;
  TrID =:= ATID, TrSt =:= starting;
  TrID =:= ATID, TrSt =:= stopping ->
  {reply, ok, State};


handle_call({#{tr_id := TrID, i_level := no_record_version, wait := wait} = _Tr, lock},
  {From, _Tag}, #{tr_state := active, active_tid := ATID} = State)
  when TrID =/= ATID ->
  transaction:wait_subscribe(TrID, ATID, self(), From),
  {reply, locked, State};


handle_call({#{tr_id := TrID, i_level := IL, wait := W} = _Tr, lock},
  _From, #{tr_state := active, active_tid := ATID} = State)
  when
  TrID =/= ATID, IL =:= record_version, W =:= no_wait;
  TrID =/= ATID, IL =:= no_record_version, W =:= no_wait;
  TrID =/= ATID, IL =:= record_version, W =:= wait ->
  {reply, busy, State};




handle_call({#{tr_id := TrID} = Tr, stop},
  _From, #{tr_state := committed} = State) ->
  NewState = State#{tr_state => stopping, active_tid => TrID},
  transaction:write_transaction_log(Tr, self()),
  {reply, ok, NewState};

handle_call({#{tr_id := TrID} = _Tr, stop},
  _From, #{tr_state := stopping, active_tid := ATID} = State)
  when TrID =:= ATID ->
  {reply, ok, State};

handle_call({#{tr_id := TrID} = _Tr, stop},
  _From, #{tr_state := active, active_tid := ATID} = State)
  when TrID =:= ATID ->
  NewState = State#{tr_state => stopping},
  {reply, ok, NewState};

handle_call({#{tr_id := TrID} = _Tr, stop},
  _From, #{tr_state := starting, active_tid := ATID} = State)
  when TrID =:= ATID ->
  NewState = State#{tr_state => stopping},
  {reply, ok, NewState};


handle_call({#{tr_id := TrID, i_level := record_version, wait := _W} = _Tr, stop},
  _From, #{tr_state := active, active_tid := ATID} = State)
  when TrID =/= ATID ->
  {reply, busy, State};

handle_call({#{tr_id := TrID, i_level := no_record_version, wait := no_wait} = _Tr, stop},
  _From, #{tr_state := active, active_tid := ATID} = State)
  when TrID =/= ATID ->
  {reply, busy, State};

handle_call({#{tr_id := TrID, i_level := no_record_version, wait := wait} = _Tr, stop},
  {From, _Tag}, #{tr_state := active, active_tid := ATID} = State)
  when TrID =/= ATID ->
  transaction:wait_subscribe(TrID, ATID, self(), From),
  {reply, locked, State};


handle_call({#{tr_id := TrID} = _Tr, _Request},
  _From, #{tr_state := starting, active_tid := ATID} = State)
  when TrID =/= ATID ->
  {reply, busy, State};



handle_call({#{tr_id := TrID, tr_bet := Bet, overwrite := OWrite} = Tr, Request},
  {From, Ref}, #{tr_state := committed, module := Mod, committed_tid := CTID} = State) ->
  CommittedVState = maps:get(CTID, State),
  Res1 = Mod:handle_call(Tr, Request, {From, Ref}, CommittedVState),
  {Reply, NewVState} = get_result_state(Res1),
  NewState = case NewVState =/= CommittedVState of
               true ->
                 Latest_CTID = case OWrite of
                                 true -> CTID;
                                 false -> get_latest_CTID(TrID, CTID)
                               end,
                 case CTID =/= Latest_CTID of
                   true ->
                     set_result(Res1, lost, State);
                   false ->
                     transaction:write_transaction_log(Tr, self()),
                     set_result(Res1, Reply,
                       State#{
                         tr_state => active,
                         active_bet => Bet,
                         client_pid => From,
                         active_tid => TrID,
                         TrID => NewVState}
                     )
                 end;
               false ->
                 case OWrite of
                   true -> continue;
                   false -> transaction:write_reading_log(TrID, self(), CTID)
                 end,
                 set_result(Res1, Reply, State)
             end,
  NewState;

handle_call({#{tr_id := TrID} = Tr, Request},
  From, #{tr_state := TrSt, active_tid := ATID, module := Mod} = State)
  when
  TrID =:= ATID, TrSt =:= active;
  TrID =:= ATID, TrSt =:= starting ->
  ActiveVState = maps:get(ATID, State),
  Res1 = Mod:handle_call(Tr, Request, From, ActiveVState),
  {Reply, NewVersion} = get_result_state(Res1),
  NewState = State#{ATID => NewVersion},
  set_result(Res1, Reply, NewState);

handle_call({#{tr_id := TrID, i_level := record_version, wait := _W, overwrite := OWrite} = Tr, Request},
  From, #{tr_state := TrSt, committed_tid := CTID, active_tid := ATID, module := Mod} = State)
  when
  TrID =/= ATID, TrSt =:= active;
  TrID =/= ATID, TrSt =:= stopping ->
  CommittedVState = maps:get(CTID, State),
  Res1 = Mod:handle_call(Tr, Request, From, CommittedVState),
  {Reply, NewVState} = get_result_state(Res1),
  case NewVState =/= CommittedVState of
    true ->
      set_result(Res1, busy, State);
    false ->
      case OWrite of
        true -> continue;
        false -> transaction:write_reading_log(TrID, self(), CTID)
      end,
      set_result(Res1, Reply, State)
  end;

handle_call({#{tr_id := TrID, i_level := no_record_version, wait := no_wait} = _Tr, _Request},
  _From, #{tr_state := active, active_tid := ATID} = State)
  when TrID =/= ATID ->
  {reply, busy, State};


handle_call({#{tr_id := TrID, i_level := no_record_version, wait := wait} = _Tr, _Request},
  {From, _Tag}, #{tr_state := active, active_tid := ATID} = State)
  when TrID =/= ATID ->
  transaction:wait_subscribe(TrID, ATID, self(), From),
  {reply, locked, State}.


handle_cast(_R, State) ->
  {noreply, State}.


handle_info({Tr, Info}, #{module := Mod} = State) ->
  Mod:handle_info(Tr, Info, State),
  {noreply, State}.


terminate(_Reason, #{module := Mod, committed_tid := CTID, active_tid := ATID} = State) ->
  CommittedVState = maps:get(CTID, State),
  Mod:terminate(ATID, normal, CommittedVState),
  ok.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------

commit_by_context(#{tr_id := TrID} = _Tr,
  #{tr_state := stopping, active_tid := ATID} = State)
  when TrID =:= ATID ->
  State;

commit_by_context(#{tr_id := TrID} = _Tr,
  #{tr_state := TrSt, active_tid := ATID, module := Mod} = State)
  when TrID =:= ATID, TrSt =:= active;
  TrID =:= ATID, TrSt =:= starting ->
  ActiveVState = maps:get(ATID, State),
  #{
    tr_state => committed,
    active_bet => none,
    client_pid => none,
    active_tid => 0,
    committed_tid => TrID,
    module => Mod,
    TrID => ActiveVState};

commit_by_context(#{tr_id := TrID} = _Tr, #{tr_state := active, active_tid := ATID} = State)
  when TrID =/= ATID ->
  State;

commit_by_context(#{tr_id := _TrID} = _Tr, #{tr_state := committed} = State) ->
  State.


rollback_by_context(#{tr_id := TrID} = _Tr, #{tr_state := TRState, active_tid := ATID, committed_tid := CTID, module := Mod} = State)
  when TRState =:= stopping, TrID =:= ATID, CTID =/= ATID ->
  CommittedVState = maps:get(CTID, State),
  #{tr_state => committed, active_bet => none, client_pid => none, active_tid => 0, committed_tid => CTID, module => Mod, CTID => CommittedVState};


rollback_by_context(#{tr_id := TrID} = _Tr, #{tr_state := TRState, active_tid := ATID, committed_tid := CTID} = State)
  when TRState =:= stopping, TrID =:= ATID, CTID =:= ATID ->
  State;



rollback_by_context(#{tr_id := TrID} = _Tr,
  #{tr_state := starting, active_tid := ATID} = State)
  when TrID =:= ATID ->
  State#{tr_state => stopping};


rollback_by_context(#{tr_id := TrID} = _Tr,
  #{tr_state := active, active_tid := ATID, committed_tid := CTID, module := Mod} = State)
  when TrID =:= ATID ->
  CommittedVState = maps:get(CTID, State),
  #{
    tr_state => committed,
    active_bet => none,
    client_pid => none,
    active_tid => 0,
    committed_tid => CTID,
    module => Mod,
    CTID => CommittedVState};




rollback_by_context(#{tr_id := TrID} = _Tr, #{tr_state := active, active_tid := ActiveTr} = State)
  when TrID =/= ActiveTr ->
  State;

rollback_by_context(#{tr_id := _TrID} = _Tr, #{tr_state := committed} = State) ->
  State.



get_result_state({reply, Reply, NewState}) -> {Reply, NewState};
get_result_state({reply, Reply, NewState, hibernate}) -> {Reply, NewState};
get_result_state({reply, Reply, NewState, _Timeout}) -> {Reply, NewState};
get_result_state({noreply, NewState}) -> {noreply, NewState};
get_result_state({noreply, NewState, hibernate}) -> {noreply, NewState};
get_result_state({noreply, NewState, _Timeout}) -> {noreply, NewState};
get_result_state({stop, _Reason, Reply, NewState}) -> {Reply, NewState};
get_result_state({stop, _Reason, NewState}) -> {noreply, NewState}.


set_result({reply, _Reply, _State}, NewReply, NewState) -> {reply, NewReply, NewState};
set_result({reply, _Reply, _State, hibernate}, NewReply, NewState) -> {reply, NewReply, NewState, hibernate};
set_result({reply, _Reply, _State, Timeout}, NewReply, NewState) -> {reply, NewReply, NewState, Timeout};
set_result({noreply, _State}, _NewReply, NewState) -> {noreply, NewState};
set_result({noreply, _State, hibernate}, _newReply, NewState) -> {noreply, NewState, hibernate};
set_result({noreply, _State, Timeout}, _NewReply, NewState) -> {noreply, NewState, Timeout};
set_result({stop, Reason, _Reply, _State}, NewReply, NewState) -> {stop, Reason, NewReply, NewState};
set_result({stop, Reason, _State}, _NewReply, NewState) -> {stop, Reason, NewState}.

get_latest_CTID(TrID, CTID) ->
  L_CTID = transaction:read_reading_log(TrID, self()),
  case L_CTID of
    none -> CTID;
    L_CTID -> L_CTID
  end.

flush_unlock() ->
  receive
    {unlocked, _TrID} ->
      flush_unlock()
  after 0 -> ok
  end.