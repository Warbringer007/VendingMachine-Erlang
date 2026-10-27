-module(vending_machine_admin).
-include("vending_machine_common.hrl").
-export([start/0]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%UI
start() ->
	{ok, _} = application:ensure_all_started(vending_machine),
	main_menu().

main_menu() ->
	io:fwrite("Vending Machine ADMIN~nPlease select option:~n1. Add new item~n2. Change item price~n3. Change item amount~n4. Delete item~n5. Add new coin~n6. Change coin amount~n7. Delete coin~n8. List all items~n9. List all coins~n10. Exit~n"),
	case vending_machine_utils:read_choice("", 10) of
		{ok, 10} ->
			io:fwrite("Exiting...~n");
		{ok, Option} ->
			run_option(Option),
			main_menu();
		_ ->
			io:fwrite("Input not recognised! Choose one of the available actions!~n~n"),
			timer:sleep(500),
			main_menu()
	end.

run_option(1) -> admin_add_item();
run_option(2) -> admin_change_item_price();
run_option(3) -> admin_change_item_amount();
run_option(4) -> admin_delete_item();
run_option(5) -> admin_add_coin();
run_option(6) -> admin_change_coin_amount();
run_option(7) -> admin_delete_coin();
run_option(8) ->
	io:fwrite("List of all items:~n"),
	get_all_item_details();
run_option(9) ->
	io:fwrite("List of all coins:~n"),
	get_all_coins().

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%ITEM MANAGEMENT

admin_add_item() ->
	{ok, Name} = io:read("Name of the new item: "),
	{ok, Price} = io:read("Price of the new item: "),
	{ok, Amount} = io:read("Amount available of the new item: "),
	case vending_machine_server:add_item(Name, Price, Amount) of
		ok -> io:fwrite("Item with name ~p successfully added!~n", [Name]);
		{error, already_exists} -> io:fwrite("Item with name ~p already exists!~n", [Name])
	end,
	timer:sleep(500).

admin_delete_item() ->
	io:fwrite("List of all items:~n"),
	AllKeys = get_all_item_details(),
	case vending_machine_utils:read_choice("Please select which item to delete: ", length(AllKeys)) of
		{ok, Input} ->
			ItemToDelete = lists:nth(Input, AllKeys),
			ok = vending_machine_server:delete_item(ItemToDelete),
			io:fwrite("Item ~p deleted!~n~n", [ItemToDelete]);
		Error ->
			bad_selection(Error)
	end,
	timer:sleep(500).

admin_change_item_price() ->
	io:fwrite("List of all item:~n"),
	AllKeys = get_all_item_details(),
	case vending_machine_utils:read_choice("Please select for which item to change its price: ", length(AllKeys)) of
		{ok, Input} ->
			ItemToChange = lists:nth(Input, AllKeys),
			{ok, NewPrice} = io:read("New price for the item: "),
			case vending_machine_server:change_item_price(ItemToChange, NewPrice) of
				ok -> io:fwrite("Item ~p price changed!~n~n", [ItemToChange]);
				{error, not_found} -> io:fwrite("Item with name ~p doesn't exist!~n", [ItemToChange])
			end;
		Error ->
			bad_selection(Error)
	end,
	timer:sleep(500).

admin_change_item_amount() ->
	io:fwrite("List of all items:~n"),
	AllKeys = get_all_item_details(),
	case vending_machine_utils:read_choice("Please select for which item to change its amount: ", length(AllKeys)) of
		{ok, Input} ->
			ItemToChange = lists:nth(Input, AllKeys),
			{ok, NewAmount} = io:read("New amount available for the item: "),
			case vending_machine_server:change_item_amount(ItemToChange, NewAmount) of
				ok -> io:fwrite("Item ~p amount changed!~n~n", [ItemToChange]);
				{error, not_found} -> io:fwrite("Item with name ~p doesn't exist!~n", [ItemToChange])
			end;
		Error ->
			bad_selection(Error)
	end,
	timer:sleep(500).

%%Prints all items and returns their names, in the same order as printed.
get_all_item_details() ->
	AllItems = vending_machine_server:list_items(),
	print_items(AllItems, 1),
	[Name || #item{name = Name} <- AllItems].

print_items([], _) -> ok;
print_items([#item{name = Name, price = Price, amount = Amount} | T], N) ->
	io:fwrite("~p. Item ~p~n   Price ~p€~n   Amount ~p~n~n", [N, Name, Price, Amount]),
	print_items(T, N+1).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%MONEY MANAGEMENT

admin_add_coin() ->
	{ok, Value} = io:read("Value of the new coin: "),
	{ok, Amount} = io:read("Amount available of the new coin: "),
	case vending_machine_server:add_coin(Value, Amount) of
		ok -> io:fwrite("Coin with value ~p€ successfully added!~n", [Value]);
		{error, already_exists} -> io:fwrite("Coin with value ~p€ already exists!~n", [Value])
	end,
	timer:sleep(500).

admin_delete_coin() ->
	io:fwrite("List of all coins:~n"),
	AllKeys = get_all_coins(),
	case vending_machine_utils:read_choice("Please select which coin to delete: ", length(AllKeys)) of
		{ok, Input} ->
			CoinToDelete = lists:nth(Input, AllKeys),
			ok = vending_machine_server:delete_coin(CoinToDelete),
			io:fwrite("Coin ~p€ deleted!~n~n", [CoinToDelete]);
		Error ->
			bad_selection(Error)
	end,
	timer:sleep(500).

admin_change_coin_amount() ->
	io:fwrite("List of all coins:~n"),
	AllKeys = get_all_coins(),
	case vending_machine_utils:read_choice("Please select for which coin to change its amount: ", length(AllKeys)) of
		{ok, Input} ->
			CoinToChange = lists:nth(Input, AllKeys),
			{ok, NewAmount} = io:read("New amount available for the coin: "),
			case vending_machine_server:change_coin_amount(CoinToChange, NewAmount) of
				ok -> io:fwrite("Coin ~p€ amount changed!~n~n", [CoinToChange]);
				{error, not_found} -> io:fwrite("Coin with name ~p doesn't exist!~n", [CoinToChange])
			end;
		Error ->
			bad_selection(Error)
	end,
	timer:sleep(500).

%%Prints all coins (largest first) and returns their values, in the same order as printed.
get_all_coins() ->
	AllCoins = vending_machine_server:list_coins(),
	print_coins(AllCoins, 1),
	[Value || #money{value = Value} <- AllCoins].

print_coins([], _) -> ok;
print_coins([#money{value = Value, amount = Amount} | T], N) ->
	io:fwrite("~p. Value ~p€~n   Amount ~p~n~n", [N, Value, Amount]),
	print_coins(T, N+1).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%UTILS

bad_selection(too_large) ->
	io:fwrite("Input too large!~n~n");
bad_selection(invalid) ->
	io:fwrite("Input not recognised! Choose one of the available actions!~n~n").
