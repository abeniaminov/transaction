%%%-------------------------------------------------------------------
%%% @author udeis
%%% @copyright (C) 2016, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 10. Янв. 2016 21:52
%%%-------------------------------------------------------------------
-module(trpc).
-author("udeis").

%% API
-export([apply/4, apply_server/0]).

apply_server() ->
    receive
        {{CallerPid, Ref}, {Module, Func, Args}} ->
            Result = apply(Module, Func, Args),
            CallerPid ! {Ref, Result}
    end.

apply(Node, Module, Fun, Args) when Node =/= node() ->
    monitor_node(Node, true),
    RemotePid = spawn(Node, ?MODULE, apply_server, []),
    Ref = make_ref(),
    RemotePid ! {{self(), Ref}, {Module, Fun, Args}},
    receive
        {Ref, Result} ->
            monitor_node(Node, false),
            Result;
        {nodedown, Node} ->
            {error, nodedown}
    end;
apply(Node, Module, Fun, Args) when Node =:= node() ->
    erlang:apply(Module, Fun, Args).
