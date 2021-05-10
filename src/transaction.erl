% -*- coding: utf8 -*-
%%%-------------------------------------------------------------------
%%% @author Alexander
%%% @copyright (C) 2015, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 29. Сент. 2015 15:57
%%%-------------------------------------------------------------------
-module(transaction).
-author("Alexander").

-behaviour(gen_server).

%% API
-export([start_link/0]).

%% gen_server callbacks
-export([
  init/1,
  handle_call/3,
  handle_cast/2,
  handle_info/2,
  terminate/2,
  code_change/3
]).

-export([
  start/0,
  start/1,
  start_w/0,
  start_nw/0,
  start_o/0,
  start_wo/0,
  start_nwo/0,
  commit/1,
  set_locks/2,
  rollback/1,
  write_transaction_log/2,
  write_reading_log/3,
  read_reading_log/2,
  wait_subscribe/4,
  wait_unsubscribe/4
]).

-export([all_p/2, pforeach/2]).

-define(SERVER, ?MODULE).

%%%===================================================================
%%% API
%%%===================================================================

start_link() ->
  gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

-spec start() -> tgen_server:transaction().
%%
start() ->
  TrID = get_next_id(),
  #{tr_id => TrID, tr_bet => get_bet(), i_level => record_version, wait => no_wait, overwrite => false}.

-spec start_w() -> tgen_server:transaction().
%%
start_w() ->
  TrID = get_next_id(),
  #{tr_id => TrID, tr_bet => get_bet(), i_level => no_record_version, wait => wait, overwrite => false}.

-spec start_nw() -> tgen_server:transaction().
%%
start_nw() ->
  TrID = get_next_id(),
  #{tr_id => TrID, tr_bet => get_bet(), i_level => no_record_version, wait => no_wait, overwrite => false}.

-spec start_o() -> tgen_server:transaction().
%%
start_o() ->
  TrID = get_next_id(),
  #{tr_id => TrID, tr_bet => get_bet(), i_level => record_version, wait => no_wait, overwrite => true}.

-spec start_wo() -> tgen_server:transaction().
%%
start_wo() ->
  TrID = get_next_id(),
  #{tr_id => TrID, tr_bet => get_bet(), i_level => no_record_version, wait => wait, overwrite => true}.

-spec start_nwo() -> tgen_server:transaction().
%%
start_nwo() ->
  TrID = get_next_id(),
  #{tr_id => TrID, tr_bet => get_bet(), i_level => no_record_version, wait => no_wait, overwrite => true}.

-spec start(Options :: tgen_server:tr_options()) -> tgen_server:transaction().
%%
start(Options) ->
  TrID = get_next_id(),
  maps:merge(
    #{tr_id => TrID, tr_bet => get_bet(), i_level => record_version, wait => no_wait, overwrite => false},
    Options
  ).

-spec commit(Tr :: gen_server:transaction()) -> committed | rolled_back.
%%
commit(#{tr_id := TrID} = Tr) when node(TrID) =/= node() ->
  trpc:apply(node(TrID), transaction, commit, [Tr]);
commit(#{tr_id := TrID} = Tr) ->
  ChangedObjects = ets:lookup(write_log, TrID),

  R =
    case all_p(fun(Object) -> commit_object1(Object) end, ChangedObjects) of
      true ->
        lists:foreach(fun(Object) -> commit_object2(Object) end, ChangedObjects),
        committed;
      false ->
        lists:foreach(fun(Object) -> rollback_object(Object) end, ChangedObjects),
        rolled_back
    end,
  %remove_dups(
  WaitingEndTransaction =
    %),
  [{ClientPid, ConcurTr} || {_TrID, _ObjID, ClientPid, ConcurTr} <- ets:lookup(wait_log, TrID)],
  ok = broadcast_unlock(WaitingEndTransaction),
  flush_tr_log(Tr),
  R.

-spec rollback(Tr :: gen_server:transaction()) -> rolled_back.
%%
rollback(#{tr_id := TrID} = Tr) when node(TrID) =/= node() ->
  trpc:apply(node(TrID), transaction, rollback, [Tr]);
rollback(#{tr_id := TrID} = Tr) ->
  ChangedObjects = ets:lookup(write_log, TrID),
  lists:foreach(fun(Object) -> rollback_object(Object) end, ChangedObjects),
  %remove_dups(
  WaitingEndTransaction =
    %),
  [{ClientPid, ConcurTr} || {_TrID, _ObjID, ClientPid, ConcurTr} <- ets:lookup(wait_log, TrID)],
  ok = broadcast_unlock(WaitingEndTransaction),
  flush_tr_log(Tr),
  rolled_back.

-spec set_locks(Tr :: gen_server:transaction(), [pid()]) -> ok | busy | deadlock.
set_locks(_Tr, []) ->
  ok;
set_locks(Tr, [Pid | RestObjects]) ->
  case tgen_server:lock(Pid, Tr) of
    ok -> set_locks(Tr, RestObjects);
    busy -> busy;
    deadlock -> deadlock
  end.

write_transaction_log(#{tr_id := TrID} = _Tr, ObjPid) when is_reference(TrID), node() =:= node(TrID) ->
  ets:insert(write_log, {TrID, ObjPid});
write_transaction_log(#{tr_id := TrID} = Tr, ObjPid) when is_reference(TrID), node() =/= node(TrID) ->
  trpc:apply(node(TrID), transaction, write_transaction_log, [Tr, ObjPid]).

write_reading_log(TrID, ObjPid, CTID) when is_reference(TrID), node() =:= node(TrID) ->
  ets:insert(read_log, {{TrID, ObjPid}, CTID});
write_reading_log(TrID, ObjPid, CTID) when is_reference(TrID), node() =/= node(TrID) ->
  trpc:apply(node(TrID), transaction, write_reading_log, [TrID, ObjPid, CTID]).

wait_subscribe(TrID, ATID, ObjPid, WaitClientPid) when
  is_reference(TrID), is_reference(ATID), node() =:= node(ATID) ->
  ets:insert(wait_log, {ATID, ObjPid, WaitClientPid, TrID});
wait_subscribe(TrID, ATID, ObjPid, WaitClientPid) when
  is_reference(TrID), is_reference(ATID), node() =/= node(ATID) ->
  trpc:apply(node(ATID), transaction, wait_subscribe, [TrID, ATID, ObjPid, WaitClientPid]).

wait_unsubscribe(TrID, ATID, ObjPid, WaitClientPid) when
  is_reference(TrID), is_reference(ATID), node() =:= node(ATID) ->
  ets:delete_object(wait_log, {ATID, ObjPid, WaitClientPid, TrID});
wait_unsubscribe(TrID, ATID, ObjPid, WaitClientPid) when
  is_reference(TrID), is_reference(ATID), node() =/= node(ATID) ->
  trpc:apply(node(ATID), transaction, wait_unsubscribe, [TrID, ATID, ObjPid, WaitClientPid]).

read_reading_log(TrID, ObjPid) when is_reference(TrID), is_pid(ObjPid), node(TrID) =:= node() ->
  Res = ets:lookup(read_log, {TrID, ObjPid}),
  case Res of
    [] -> none;
    [{{TrID, ObjPid}, CTID}] -> CTID
  end;
read_reading_log(TrID, ObjPid) when is_reference(TrID), is_pid(ObjPid), node(TrID) =/= node() ->
  trpc:apply(node(TrID), transaction, read_reading_log, [TrID, ObjPid]).

%%%===================================================================
%%% Internal functions
%%%===================================================================
get_next_id() ->
  make_ref().

get_bet() ->
  %    erlang:monotonic_time(nano_seconds).
  %    crypto:rand_uniform(0, 1000000).
  erlang:unique_integer([positive, monotonic]).

all(_F, []) ->
  true;
all(F, [H | T]) ->
  case F(H) of
    true -> all(F, T);
    false -> false
  end.

all_p(F, T) ->
  all_l(pmap(F, T)).

all_l([]) ->
  true;
all_l([H | T]) when H ->
  all_l(T);
all_l(_T) ->
  false.

%%====================================================================
commit_object1({Tr, Pid}) ->
  gen_server:call(Pid, {Tr, commit_1}).

commit_object2({Tr, Pid}) ->
  gen_server:call(Pid, {Tr, commit_2}).

rollback_object({Tr, Pid}) ->
  gen_server:call(Pid, {Tr, rollback}).

flush_tr_log(#{tr_id := TrID} = Tr) when node(TrID) =/= node() ->
  trpc:apply(node(TrID), transaction, flush_tr_log, [Tr]);
flush_tr_log(#{tr_id := TrID} = Tr) ->
  ets:delete(write_log, TrID),
  ets:match_delete(read_log, {{TrID, '$1'}, '_'}),
  ets:delete(wait_log, TrID).

broadcast_unlock([]) ->
  ok;
broadcast_unlock([{WaitClientPid, TrID} | T]) ->
  WaitClientPid ! {unlocked, TrID},
  broadcast_unlock(T).

remove_dups([]) -> [];
remove_dups([H | T]) -> [H | [X || X <- remove_dups(T), X /= H]].

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init(_Arg) ->
  io:format("!!!!!!!!!!!!!!~nStart transaction~n!!!!!!!!!!!!!!!!!~n", []),
  ets:new(write_log, [bag, public, named_table, {read_concurrency, true}]),
  ets:new(read_log, [ordered_set, public, named_table, {read_concurrency, true}]),
  ets:new(wait_log, [bag, public, named_table, {read_concurrency, true}]),
  {ok, _Arg}.

handle_call(_Request, _From, State) ->
  {reply, ok, State}.

handle_cast(_Request, State) ->
  {noreply, State}.

handle_info(_Info, State) ->
  {noreply, State}.

terminate(_Reason, _State) ->
  ok.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

pmap(Function, List) ->
  S = self(),
  Pids = lists:map(
    fun(El) ->
      spawn(fun() -> execute(S, Function, El) end)
    end,
    List
  ),
  gather(Pids).

execute(Recv, Function, Element) ->
  Recv ! {self(), Function(Element)}.

gather(Pids) ->
  gather(Pids, []).

gather([], Acc) ->
  Acc;
gather([H | T], Acc) ->
  receive
    {H, Ret} ->
      gather(T, [Ret |Acc])
  after 500 ->
    gather(T, [false |Acc])
  end.

pforeach(F, L) ->
  lists:foreach(
    fun(X) -> spawn(fun() -> F(X) end) end,
    L
  ).
