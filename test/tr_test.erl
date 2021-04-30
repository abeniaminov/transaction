% -*- coding: utf8 -*-
%%%-------------------------------------------------------------------
%%% @author Alexander
%%% @copyright (C) 2015, <COMPANY>
%%% @doc
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(tr_test).
-author("Alexander").

-include_lib("eunit/include/eunit.hrl").

-compile(export_all).
-define(NOTEST, true).

run_test_() ->
  {setup,
    fun() ->
      ok = application:start(transaction)
    end,
    fun(_) ->
      ok = application:stop(transaction)
    end,
    {inorder,
      [?_test(start_stop()),
        ?_test(simple_get_record_version()),
        ?_test(simple_get_no_record_version_wait()),
        ?_test(simple_lock())
      ]}
  }.

start_stop() ->
  %% create tgen_server behavoiur process and commit
  Tr1 = transaction:start(),
  {ok, Pid} = tgen_sampl:start_link(Tr1, 0),
  transaction:commit(Tr1),
  ?assert(is_process_alive(Pid)),

  %% Stop previously committed tgen_server process then roll back it.
  %% After roll back the process is still alive
  Tr1_1 = transaction:start(),
  tgen_sampl:set_value(Pid, Tr1_1, 12),
  tgen_server:stop(Pid, Tr1_1),
  transaction:rollback(Tr1_1),
  ?assert(is_process_alive(Pid)),

  %% Rolled back process has state of last committed transaction
  %% Stop, but only after commit the process really stop
  Tr2 = transaction:start(),
  V2 = tgen_sampl:get_value(Pid, Tr2),
  ?debugVal(V2),
  ?assertEqual(V2, 0),
  tgen_server:stop(Pid, Tr2),
  transaction:commit(Tr2),
  ?assertNot(is_process_alive(Pid)),

  %% Roll back process creation.
  Tr3 = transaction:start(),
  {ok, Pid2} = tgen_sampl:start_link(Tr3, 0),
  transaction:rollback(Tr3),
  ?assertNot(is_process_alive(Pid2)),


  %% Roll back process creation despite the interim state change
  Tr4 = transaction:start(),
  {ok, Pid4} = tgen_sampl:start_link(Tr4, 8),
  tgen_sampl:set_value(Pid4, Tr4, 12),
  transaction:rollback(Tr4),
  ?assertNot(is_process_alive(Pid4)),

  %% Roll back process creation despite the interim state change and stop
  Tr5 = transaction:start(),
  {ok, Pid5} = tgen_sampl:start_link(Tr5, 8),
  tgen_sampl:set_value(Pid5, Tr5, 12),
  tgen_server:stop(Pid5, Tr5),
  transaction:rollback(Tr5),
  ?assertNot(is_process_alive(Pid5)),

  %% But
  Tr6 = transaction:start(),
  {ok, Pid6} = tgen_sampl:start_link(Tr6, 9),
  tgen_sampl:set_value(Pid6, Tr6, 12),
  {ok, Pid6_1} = tgen_sampl:start_from(Pid6, Tr6, 12),
  tgen_server:stop(Pid6, Tr6),
  transaction:commit(Tr6),
  ?assertNot(is_process_alive(Pid6)),
  ?assert(is_process_alive(Pid6_1)).



simple_get_record_version() ->
  Tr1 = transaction:start(),
  tgen_sampl:start_link(o1, Tr1, 0),
  transaction:commit(Tr1),
  Tr2 = transaction:start(),
  Tr3 = transaction:start(),
  V0 = tgen_sampl:get_value(o1, Tr3),
  SetV = 1,
  tgen_sampl:set_value(o1, Tr2, SetV),
  V1 = tgen_sampl:get_value(o1, Tr3),
  ?assert(V0 =:= V1),
  transaction:commit(Tr2),
  V2 = tgen_sampl:get_value(o1, Tr3),
  ?assert(SetV =:= V2),
  tgen_sampl:stop(o1, Tr3),
  transaction:commit(Tr3).



simple_get_no_record_version_wait() ->
  Tr1 = transaction:start(),
  {ok, Pid} = tgen_sampl:start_link(Tr1, 0),
  transaction:commit(Tr1),

  spawn(?MODULE, clientS, [start_wo, 1, 60, Pid]),
  timer:sleep(10),
  V = apply(?MODULE, clientR, [start_wo, 1, Pid]),

  ?assertEqual(1, V),


  spawn(?MODULE, clientS, [start_wo, 2, 10, Pid]),
  timer:sleep(400),
  V2 = apply(?MODULE, clientR, [start_wo, 2, Pid]),
  ?assertEqual(2, V2),

  spawn(?MODULE, clientS, [start_w, 3, 10, Pid]),
  timer:sleep(10),
  spawn(?MODULE, clientS, [start_wo, 4, 300, Pid]),
  timer:sleep(0),
  V3 = apply(?MODULE, clientR, [start_nw, 4, Pid]),
  ?assertEqual(busy, V3),
  timer:sleep(500),


  Tr2 = transaction:start(),
  tgen_sampl:stop(Pid, Tr2),
  transaction:commit(Tr2).


clientS(Type, Val, Sleep, Obj) ->
  Tr = transaction:Type(),
  tgen_sampl:set_value(Obj, Tr, Val),
  G = tgen_sampl:get_value(Obj, Tr),
  ?debugVal(G),
  timer:sleep(Sleep),
  transaction:commit(Tr).

clientR(Type, _R, Obj) ->
  Tr = transaction:Type(),
  V = tgen_sampl:get_value(Obj, Tr),
  ?debugVal(V),
  transaction:commit(Tr),
  V.



simple_lock() -> ok.

