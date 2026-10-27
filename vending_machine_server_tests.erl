-module(vending_machine_server_tests).
-include_lib("eunit/include/eunit.hrl").
-include("vending_machine_common.hrl").

-define(S, vending_machine_server).
-import(vending_machine_test_setup, [stock/1, coins/1]).

%%Test data (see vending_machine_test_setup:start/0):
%%  Cola 1.50 x3, Chips 1.20 x1, Gum 0.50 x0
%%  coins 5 x0, 2 x5, 1 x5, 0.50 x5, 0.20 x5, 0.10 x0

server_test_() ->
	{foreach,
	 fun vending_machine_test_setup:start/0,
	 fun vending_machine_test_setup:stop/1,
	 [%%admin
	  {"add item, duplicate rejected", fun add_item/0},
	  {"change item price", fun change_item_price/0},
	  {"change item amount", fun change_item_amount/0},
	  {"change missing item", fun change_missing_item/0},
	  {"delete item", fun delete_item/0},
	  {"add coin, duplicate rejected", fun add_coin/0},
	  {"change coin amount", fun change_coin_amount/0},
	  {"delete coin", fun delete_coin/0},
	  %%lists
	  {"items include sold out ones", fun list_items/0},
	  {"coins largest first", fun list_coins/0},
	  {"item availability", fun item_available/0},
	  %%purchase
	  {"not enough money saves nothing", fun not_enough_money/0},
	  {"exact payment", fun exact_payment/0},
	  {"overpayment returns change", fun overpayment/0},
	  {"change uses largest coins first", fun largest_coins_first/0},
	  {"change falls back to smaller coins", fun change_fallback/0},
	  {"no change possible saves nothing", fun no_change/0},
	  {"unknown coin rejected", fun unknown_coin/0},
	  {"sold out or unknown item", fun not_available/0},
	  {"last item can be sold only once", fun last_item/0}]}.

init_db_test_() ->
	{setup,
	 fun vending_machine_test_setup:start_with_sample_data/0,
	 fun vending_machine_test_setup:stop/1,
	 [{"creates sample items and coins", fun init_db_sample_data/0},
	  {"refuses to overwrite an existing database", fun init_db_twice/0}]}.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%ADMIN

add_item() ->
	?assertEqual(ok, ?S:add_item("Water", 1, 10)),
	?assertEqual(10, stock("Water")),
	?assertEqual({error, already_exists}, ?S:add_item("Cola", 9, 9)),
	?assertEqual(3, stock("Cola")).

change_item_price() ->
	?assertEqual(ok, ?S:change_item_price("Cola", 1.8)),
	?assertMatch([#item{price = 1.8}], [I || I = #item{name = "Cola"} <- ?S:list_items()]).

change_item_amount() ->
	?assertEqual(ok, ?S:change_item_amount("Gum", 7)),
	?assertEqual(7, stock("Gum")).

change_missing_item() ->
	?assertEqual({error, not_found}, ?S:change_item_price("Nope", 1)),
	?assertEqual({error, not_found}, ?S:change_item_amount("Nope", 1)).

delete_item() ->
	?assertEqual(ok, ?S:delete_item("Chips")),
	?assertEqual(["Cola", "Gum"], lists:sort([N || #item{name = N} <- ?S:list_items()])).

add_coin() ->
	?assertEqual(ok, ?S:add_coin(0.05, 3)),
	?assertEqual(3, coins(0.05)),
	?assertEqual({error, already_exists}, ?S:add_coin(2, 99)),
	?assertEqual(5, coins(2)).

change_coin_amount() ->
	?assertEqual(ok, ?S:change_coin_amount(0.1, 4)),
	?assertEqual(4, coins(0.1)),
	?assertEqual({error, not_found}, ?S:change_coin_amount(0.03, 1)).

delete_coin() ->
	?assertEqual(ok, ?S:delete_coin(5)),
	?assertEqual([2, 1, 0.5, 0.2, 0.1], [V || #money{value = V} <- ?S:list_coins()]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%LISTS

list_items() ->
	?assertEqual(["Chips", "Cola", "Gum"], lists:sort([N || #item{name = N} <- ?S:list_items()])).

list_coins() ->
	?assertEqual([5, 2, 1, 0.5, 0.2, 0.1], [V || #money{value = V} <- ?S:list_coins()]).

item_available() ->
	?assert(?S:item_available("Cola")),
	?assertNot(?S:item_available("Gum")),
	?assertNot(?S:item_available("Nope")).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%PURCHASE

not_enough_money() ->
	?assertEqual({inserted, 1.0}, ?S:purchase("Cola", [1])),
	?assertEqual(3, stock("Cola")),
	?assertEqual(5, coins(1)).

exact_payment() ->
	?assertEqual({bought, 0.0}, ?S:purchase("Cola", [1, 0.5])),
	?assertEqual(2, stock("Cola")),
	?assertEqual(6, coins(1)),
	?assertEqual(6, coins(0.5)).

overpayment() ->
	?assertEqual({bought, 0.5}, ?S:purchase("Cola", [2])),
	?assertEqual(2, stock("Cola")),
	?assertEqual(6, coins(2)),    %%inserted coin kept
	?assertEqual(4, coins(0.5)).  %%change given

largest_coins_first() ->
	ok = ?S:change_coin_amount(5, 1),
	?assertEqual({bought, 3.5}, ?S:purchase("Cola", [5])),   %%3.50 = 2 + 1 + 0.50
	?assertEqual([2, 4, 4, 4, 5], [coins(V) || V <- [5, 2, 1, 0.5, 0.2]]).

change_fallback() ->
	%%0.80 change: 0.50 + 0.20 would need a 0.10 coin (none), so 4 x 0.20 is used
	?assertEqual({bought, 0.8}, ?S:purchase("Chips", [2])),
	?assertEqual(5, coins(0.5)),
	?assertEqual(1, coins(0.2)),
	?assertEqual(0, stock("Chips")).

no_change() ->
	ok = ?S:change_coin_amount(0.5, 0),
	ok = ?S:change_coin_amount(0.2, 0),
	Before = {?S:list_items(), ?S:list_coins()},
	?assertEqual({no_change, [2]}, ?S:purchase("Cola", [2])),
	?assertEqual(Before, {?S:list_items(), ?S:list_coins()}).

unknown_coin() ->
	?assertEqual({error, unknown_coin}, ?S:purchase("Cola", [3])),
	?assertEqual({error, unknown_coin}, ?S:purchase("Cola", [2, 3])),
	?assertEqual(3, stock("Cola")).

not_available() ->
	?assertEqual({error, not_available}, ?S:purchase("Gum", [1])),
	?assertEqual({error, not_available}, ?S:purchase("Nope", [1])),
	?assertEqual(5, coins(1)).

last_item() ->
	?assertEqual({bought, 0.8}, ?S:purchase("Chips", [2])),
	?assertEqual({error, not_available}, ?S:purchase("Chips", [2])),
	?assertEqual(0, stock("Chips")).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%INIT_DB

init_db_sample_data() ->
	?assertEqual(6, length(?S:list_items())),
	?assertEqual(9, length(?S:list_coins())),
	?assert(?S:item_available("Sprite")).

init_db_twice() ->
	?assertMatch({error, _}, ?S:init_db()),
	?assertEqual(6, length(?S:list_items())).
