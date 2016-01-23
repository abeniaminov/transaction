% -*- coding: utf8 -*-
%%%-------------------------------------------------------------------
%%% @author Alexander
%%% @copyright (C) 2015, <COMPANY>
%%% @doc
%%%
%%% @end

%%%-------------------------------------------------------------------
-module(tgen_sampl).
-author("Alexander").

-behaviour(tgen_server).

%% API
-export([start_link/3, start_link/2]).
-export([set_value/3, get_value/2, stop/2, start_from/3]).


%% gen_server callbacks
-export([init/2,
    handle_call/4,
    handle_cast/3,
    handle_info/3,
    terminate/3,
    code_change/3]).

-define(SERVER, ?MODULE).


%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @end
%%--------------------------------------------------------------------
-spec(start_link(atom(), tgen_sever:transaction(), term()) ->
    {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link(Name, Tr, InitVal) ->
    tgen_server:start_link({local, Name}, ?MODULE, InitVal, Tr, []).

start_link(Tr, InitVal) ->
    tgen_server:start_link(?MODULE, InitVal, Tr, []).


set_value(Pid, Tr, Value) ->
    tgen_server:call(Pid, Tr, {set_value, Value}).

get_value(Pid, Tr) ->
    tgen_server:call(Pid, Tr, get_value).

start_from(Pid, Tr, Value) ->
    tgen_server:call(Pid, Tr, {start_from, Value}).

stop(Pid, Tr) ->
    tgen_server:stop(Pid, Tr).


%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%%--------------------------------------------------------------------


init(_Tr, InitVal) ->
    {ok, InitVal}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @end
%%--------------------------------------------------------------------

handle_call(_Tr, {set_value, Value}, _From, _State) ->
    {reply, ok, Value};

handle_call(Tr, {start_from, Value}, _From, _State) ->
    NewPid = start_link(Tr, Value),
    {reply, NewPid, Value};


handle_call(_Tr, get_value, _From, State) ->
    {reply, State, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @end
%%--------------------------------------------------------------------
handle_cast(_Tr,_Request, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% @end
%%--------------------------------------------------------------------
handle_info(_Tr,_Info, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% @end
%%--------------------------------------------------------------------

terminate(_Tr, _Reason, _State) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
