-module(vending_machine_user).
-include("vending_machine_common.hrl").
-export([start/0]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%UI
start() ->
	{ok, _} = application:ensure_all_started(vending_machine),
	{ok, Session} = vending_machine_sup:start_session(),
	item_choosing(Session),
	vending_machine_session:stop(Session).

%%After a purchase or a cancel the item list is shown again, until the customer picks Exit.
item_choosing(Session) ->
	AllItems = [Item || Item = #item{amount = Amount} <- vending_machine_server:list_items(), Amount > 0],
	io:fwrite("Choose an item:~n"),
	list_all_items(AllItems, 1),
	ExitOption = length(AllItems) + 1,
	io:fwrite("~p. Exit~n", [ExitOption]),
	case vending_machine_utils:read_choice("", ExitOption) of
		{ok, ExitOption} ->
			io:fwrite("Exiting...~n");
		{ok, Input} ->
			#item{name = Name} = lists:nth(Input, AllItems),
			case vending_machine_session:select_item(Session, Name) of
				ok ->
					payment(Session, vending_machine_server:list_coins(), 0.0);
				{error, not_available} ->
					io:fwrite("Item ~p is not available!~n~n", [Name]),
					timer:sleep(500)
			end,
			item_choosing(Session);
		_ ->
			io:fwrite("Input not recognised! Choose one of the available actions!~n~n"),
			timer:sleep(500),
			item_choosing(Session)
	end.

payment(Session, AllCoins, InsertedMoney) ->
	io:fwrite("Total money inserted ~.2f€~n", [InsertedMoney]),
	coin_menu(AllCoins),
	CancelOption = length(AllCoins) + 1,
	case vending_machine_utils:read_choice("", CancelOption) of
		{ok, CancelOption} ->
			{refund, _Coins} = vending_machine_session:cancel(Session),
			io:fwrite("Exiting...~n");
		{ok, Input} ->
			#money{value = Value} = lists:nth(Input, AllCoins),
			case vending_machine_session:insert_coin(Session, Value) of
				{inserted, Total} ->
					payment(Session, AllCoins, Total);
				{bought, Change} ->
					io:format("Item successfully bought! Returning change ~p€ ...~n", [Change]);
				{no_change, _Coins} ->
					io:format("Can't return change, returning inserted money...~n");
				{error, not_available} ->
					io:format("Item is no longer available, returning inserted money...~n")
			end;
		_ ->
			io:fwrite("Input not recognised! Choose one of the available coins!~n~n"),
			timer:sleep(500),
			payment(Session, AllCoins, InsertedMoney)
	end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%UTILS

list_all_items([], _) -> ok;
list_all_items([#item{name = Name, price = Price} | T], N) ->
	io:fwrite("~p. ~p -> ~p€~n", [N, Name, Price]),
	list_all_items(T, N+1).

coin_menu(AllCoins) ->
	io:fwrite("Please insert money or coins:~n"),
	list_all_coins(AllCoins, 1),
	io:fwrite("~p. Cancel~n", [length(AllCoins) + 1]).

list_all_coins([], _) -> ok;
list_all_coins([#money{value = Value} | T], N) when is_integer(Value) ->
	io:fwrite("~p. ~p€~n", [N, Value]),     %%whole euros, e.g. "5€"
	list_all_coins(T, N+1);
list_all_coins([#money{value = Value} | T], N) ->
	io:fwrite("~p. ~.2f€~n", [N, Value]),   %%cents, e.g. "0.50€"
	list_all_coins(T, N+1).
