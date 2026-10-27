-module(vending_machine_test_setup).
-include("vending_machine_common.hrl").

%%Shared setup for the EUnit tests. Every test gets its own fresh database in a
%%temporary folder (test_db_<number>), so the real Mnesia.nonode@nohost is never touched.
-export([start/0, start_with_sample_data/0, stop/1]).
-export([stock/1, coins/1, sessions/0, wait_for_new_server/1, wait_for_exit/1]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%SETUP AND CLEANUP

%%Fresh database with the small, fixed test data below, application running.
start() ->
	State = start_with_sample_data(),
	{atomic, ok} = mnesia:clear_table(item),
	{atomic, ok} = mnesia:clear_table(money),
	add_test_data(),
	State.

%%Fresh database created by vending_machine_server:init_db(), application running.
start_with_sample_data() ->
	#{level := LogLevel} = logger:get_primary_config(),
	logger:set_primary_config(level, none), %%hide the crash reports the fault tests cause on purpose
	_ = application:stop(vending_machine),
	_ = application:stop(mnesia),
	case application:load(mnesia) of
		ok -> ok;
		{error, {already_loaded, mnesia}} -> ok
	end,
	Dir = "test_db_" ++ integer_to_list(erlang:unique_integer([positive])),
	ok = application:set_env(mnesia, dir, Dir),
	ok = vending_machine_server:init_db(),
	{ok, _} = application:ensure_all_started(vending_machine),
	{Dir, LogLevel}.

stop({Dir, LogLevel}) ->
	_ = application:stop(vending_machine),
	_ = application:stop(mnesia),
	ok = file:del_dir_r(Dir),
	logger:set_primary_config(level, LogLevel).

%%Items: Cola 1.50 (3 left), Chips 1.20 (1 left), Gum 0.50 (sold out).
%%Coins: 5 (none), 2, 1, 0.50, 0.20 (5 of each), 0.10 (none).
add_test_data() ->
	ok = vending_machine_server:add_item("Cola", 1.5, 3),
	ok = vending_machine_server:add_item("Chips", 1.2, 1),
	ok = vending_machine_server:add_item("Gum", 0.5, 0),
	ok = vending_machine_server:add_coin(5, 0),
	ok = vending_machine_server:add_coin(2, 5),
	ok = vending_machine_server:add_coin(1, 5),
	ok = vending_machine_server:add_coin(0.5, 5),
	ok = vending_machine_server:add_coin(0.2, 5),
	ok = vending_machine_server:add_coin(0.1, 0).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%HELPERS

%%How many of item Name are in stock.
stock(Name) ->
	[Amount] = [A || #item{name = N, amount = A} <- vending_machine_server:list_items(), N =:= Name],
	Amount.

%%How many coins of Value the machine holds.
coins(Value) ->
	[Amount] = [A || #money{value = V, amount = A} <- vending_machine_server:list_coins(), V =:= Value],
	Amount.

%%Pids of all running sessions.
sessions() ->
	[Pid || {{vending_machine_session, _}, Pid, worker, _} <- supervisor:which_children(vending_machine_sup)].

%%Waits until the supervisor has replaced the server process OldPid.
wait_for_new_server(OldPid) ->
	wait_for_new_server(OldPid, 50).

wait_for_new_server(_OldPid, 0) ->
	error(server_not_restarted);
wait_for_new_server(OldPid, Tries) ->
	case whereis(vending_machine_server) of
		Pid when is_pid(Pid), Pid =/= OldPid -> Pid;
		_ -> timer:sleep(20), wait_for_new_server(OldPid, Tries - 1)
	end.

%%Waits until process Pid has ended.
wait_for_exit(Pid) ->
	Ref = erlang:monitor(process, Pid),
	receive
		{'DOWN', Ref, process, Pid, _Reason} -> ok
	after 1000 ->
		error({still_alive, Pid})
	end.
