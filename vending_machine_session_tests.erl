-module(vending_machine_session_tests).
-include_lib("eunit/include/eunit.hrl").

-define(SS, vending_machine_session).
-import(vending_machine_test_setup, [stock/1, sessions/0, wait_for_new_server/1, wait_for_exit/1]).

%%Test data (see vending_machine_test_setup:start/0):
%%  Cola 1.50 x3, Chips 1.20 x1, Gum 0.50 x0
%%  coins 5 x0, 2 x5, 1 x5, 0.50 x5, 0.20 x5, 0.10 x0

session_test_() ->
	{foreach,
	 fun vending_machine_test_setup:start/0,
	 fun vending_machine_test_setup:stop/1,
	 [%%one customer
	  {"select, pay, buy, then buy again", fun buy_flow/0},
	  {"cancel refunds inserted coins", fun cancel/0},
	  {"selecting twice", fun select_twice/0},
	  {"inserting before selecting", fun insert_without_item/0},
	  {"selecting a sold out item", fun select_sold_out/0},
	  {"unknown coin keeps the purchase going", fun unknown_coin/0},
	  {"failed change ends the purchase", fun no_change/0},
	  %%several customers
	  {"two customers shop at the same time", fun two_customers/0},
	  {"race for the last item", fun last_item_race/0},
	  %%crashes
	  {"server crash keeps inserted coins", fun server_crash/0},
	  {"console exit ends its session", fun console_exit/0},
	  {"session crash affects no one else", fun session_crash/0},
	  {"ended sessions are removed", fun ended_sessions_removed/0}]}.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%ONE CUSTOMER

buy_flow() ->
	{ok, S} = vending_machine_sup:start_session(),
	?assertEqual(ok, ?SS:select_item(S, "Cola")),
	?assertEqual({inserted, 1.0}, ?SS:insert_coin(S, 1)),
	?assertEqual({bought, 0.0}, ?SS:insert_coin(S, 0.5)),
	?assertEqual(2, stock("Cola")),
	?assertEqual(ok, ?SS:select_item(S, "Cola")), %%session is ready for the next purchase
	?assertEqual({bought, 0.5}, ?SS:insert_coin(S, 2)),
	?assertEqual(1, stock("Cola")).

cancel() ->
	{ok, S} = vending_machine_sup:start_session(),
	ok = ?SS:select_item(S, "Cola"),
	{inserted, 1.0} = ?SS:insert_coin(S, 1),
	?assertEqual({refund, [1]}, ?SS:cancel(S)),
	?assertEqual({error, no_item_selected}, ?SS:insert_coin(S, 1)),
	?assertEqual(3, stock("Cola")).

select_twice() ->
	{ok, S} = vending_machine_sup:start_session(),
	ok = ?SS:select_item(S, "Cola"),
	?assertEqual({error, already_selected}, ?SS:select_item(S, "Chips")).

insert_without_item() ->
	{ok, S} = vending_machine_sup:start_session(),
	?assertEqual({error, no_item_selected}, ?SS:insert_coin(S, 1)).

select_sold_out() ->
	{ok, S} = vending_machine_sup:start_session(),
	?assertEqual({error, not_available}, ?SS:select_item(S, "Gum")),
	?assertEqual(ok, ?SS:select_item(S, "Cola")). %%nothing was selected, so this works

unknown_coin() ->
	{ok, S} = vending_machine_sup:start_session(),
	ok = ?SS:select_item(S, "Cola"),
	{inserted, 1.0} = ?SS:insert_coin(S, 1),
	?assertEqual({error, unknown_coin}, ?SS:insert_coin(S, 3)),
	?assertEqual({bought, 0.0}, ?SS:insert_coin(S, 0.5)).

no_change() ->
	ok = vending_machine_server:change_coin_amount(0.5, 0),
	ok = vending_machine_server:change_coin_amount(0.2, 0),
	{ok, S} = vending_machine_sup:start_session(),
	ok = ?SS:select_item(S, "Cola"),
	?assertEqual({no_change, [2]}, ?SS:insert_coin(S, 2)),
	?assertEqual(ok, ?SS:select_item(S, "Chips")). %%purchase ended, new one can start

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%SEVERAL CUSTOMERS

two_customers() ->
	{ok, A} = vending_machine_sup:start_session(),
	{ok, B} = vending_machine_sup:start_session(),
	?assertEqual(ok, ?SS:select_item(A, "Cola")),
	?assertEqual(ok, ?SS:select_item(B, "Cola")),
	?assertEqual({inserted, 1.0}, ?SS:insert_coin(A, 1)),
	?assertEqual({inserted, 1.0}, ?SS:insert_coin(B, 1)),
	?assertEqual({bought, 0.0}, ?SS:insert_coin(B, 0.5)),
	?assertEqual({bought, 0.0}, ?SS:insert_coin(A, 0.5)),
	?assertEqual(1, stock("Cola")).

last_item_race() ->
	{ok, A} = vending_machine_sup:start_session(),
	{ok, B} = vending_machine_sup:start_session(),
	?assertEqual(ok, ?SS:select_item(A, "Chips")),
	?assertEqual(ok, ?SS:select_item(B, "Chips")),         %%no reservation
	?assertEqual({inserted, 1.0}, ?SS:insert_coin(A, 1)),
	?assertEqual({bought, 0.8}, ?SS:insert_coin(B, 2)),     %%B pays first
	?assertEqual({error, not_available}, ?SS:insert_coin(A, 1)),
	?assertEqual(0, stock("Chips")).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%CRASHES

server_crash() ->
	{ok, S} = vending_machine_sup:start_session(),
	ok = ?SS:select_item(S, "Cola"),
	{inserted, 1.0} = ?SS:insert_coin(S, 1),
	OldServer = whereis(vending_machine_server),
	exit(OldServer, kill),
	wait_for_new_server(OldServer),
	?assertEqual({bought, 0.0}, ?SS:insert_coin(S, 0.5)),  %%the 1 inserted before the crash still counts
	?assertEqual([S], sessions()).

console_exit() ->
	Self = self(),
	Console = spawn(fun() ->
		{ok, S} = vending_machine_sup:start_session(),
		Self ! {session, S},
		receive stop -> ok end
	end),
	S = receive {session, Pid} -> Pid end,
	exit(Console, kill),
	wait_for_exit(S),
	?assertEqual([], sessions()).

session_crash() ->
	{ok, A} = vending_machine_sup:start_session(),
	{ok, B} = vending_machine_sup:start_session(),
	exit(A, kill),
	wait_for_exit(A),
	?assertEqual([B], sessions()),                          %%A is not restarted
	?assertEqual(ok, ?SS:select_item(B, "Cola")),
	?assertEqual({bought, 0.5}, ?SS:insert_coin(B, 2)).

ended_sessions_removed() ->
	Sessions = [begin {ok, S} = vending_machine_sup:start_session(), S end || _ <- lists:seq(1, 20)],
	?assertEqual(20, length(sessions())),
	[ok = ?SS:stop(S) || S <- Sessions],
	?assertEqual([], sessions()).
