-module(vending_machine_server).
-behaviour(gen_server).
-include("vending_machine_common.hrl").

%%Starting
-export([start_link/0]).
%%Creating the database (run once, before the first start)
-export([init_db/0]).
%%Customer API (used by vending_machine_session)
-export([list_items/0, list_coins/0, item_available/1, purchase/2]).
%%Admin API
-export([add_item/3, change_item_price/2, change_item_amount/2, delete_item/1,
         add_coin/2, change_coin_amount/2, delete_coin/1]).
%%gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

%%The server owns the shared stock and coins. It holds no customer state:
%%each customer's selected item and inserted coins live in their own vending_machine_session.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%STARTING (by vending_machine_sup)

start_link() -> gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%CUSTOMER API

%%All items (also those with amount 0), in table order.
list_items() -> gen_server:call(?MODULE, list_items).

%%All coins, from the largest to the smallest value.
list_coins() -> gen_server:call(?MODULE, list_coins).

%%true | false
item_available(Name) -> gen_server:call(?MODULE, {item_available, Name}).

%%Tries to sell item Name for the coins inserted so far, in one transaction.
%%{inserted, TotalSoFar}      - not enough money yet, nothing is saved
%%{bought, Change}            - item sold, Change is the amount returned
%%{no_change, InsertedCoins}  - change can't be given, inserted coins are returned
%%{error, not_available}      - item ran out meanwhile, inserted coins are returned
%%{error, unknown_coin}       - one of the coins is not accepted by the machine
purchase(Name, InsertedCoins) -> gen_server:call(?MODULE, {purchase, Name, InsertedCoins}).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%ADMIN API
%%All return ok, {error, already_exists} (add) or {error, not_found} (change).

add_item(Name, Price, Amount)       -> gen_server:call(?MODULE, {add_item, Name, Price, Amount}).
change_item_price(Name, NewPrice)   -> gen_server:call(?MODULE, {change_item_price, Name, NewPrice}).
change_item_amount(Name, NewAmount) -> gen_server:call(?MODULE, {change_item_amount, Name, NewAmount}).
delete_item(Name)                   -> gen_server:call(?MODULE, {delete_item, Name}).
add_coin(Value, Amount)             -> gen_server:call(?MODULE, {add_coin, Value, Amount}).
change_coin_amount(Value, NewAmount) -> gen_server:call(?MODULE, {change_coin_amount, Value, NewAmount}).
delete_coin(Value)                  -> gen_server:call(?MODULE, {delete_coin, Value}).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%GEN_SERVER CALLBACKS

%%Mnesia is started by the application controller (it is listed in vending_machine.app).
init([]) ->
	ok = mnesia:wait_for_tables([item, money], 5000),
	{ok, no_state}.

handle_call(list_items, _From, State) ->
	{reply, transaction(fun read_all_items/0), State};

handle_call(list_coins, _From, State) ->
	{reply, transaction(fun read_all_coins/0), State};

handle_call({item_available, Name}, _From, State) ->
	{reply, transaction(fun() -> item_available_in_db(Name) end), State};

handle_call({purchase, Name, InsertedCoins}, _From, State) ->
	F = fun() ->
		case lists:all(fun(Value) -> mnesia:read({money, Value}) =/= [] end, InsertedCoins) of
			false -> {error, unknown_coin};
			true -> try_purchase(Name, InsertedCoins)
		end
	end,
	{reply, transaction(F), State};

handle_call({add_item, Name, Price, Amount}, _From, State) ->
	F = fun() ->
		case mnesia:read({item, Name}) of
			[] -> mnesia:write(#item{name = Name, price = Price, amount = Amount});
			_ -> {error, already_exists}
		end
	end,
	{reply, transaction(F), State};

handle_call({change_item_price, Name, NewPrice}, _From, State) ->
	F = fun() ->
		case mnesia:wread({item, Name}) of
			[] -> {error, not_found};
			[Item] -> mnesia:write(Item#item{price = NewPrice})
		end
	end,
	{reply, transaction(F), State};

handle_call({change_item_amount, Name, NewAmount}, _From, State) ->
	F = fun() ->
		case mnesia:wread({item, Name}) of
			[] -> {error, not_found};
			[Item] -> mnesia:write(Item#item{amount = NewAmount})
		end
	end,
	{reply, transaction(F), State};

handle_call({delete_item, Name}, _From, State) ->
	{reply, transaction(fun() -> mnesia:delete({item, Name}) end), State};

handle_call({add_coin, Value, Amount}, _From, State) ->
	F = fun() ->
		case mnesia:read({money, Value}) of
			[] -> mnesia:write(#money{value = Value, amount = Amount});
			_ -> {error, already_exists}
		end
	end,
	{reply, transaction(F), State};

handle_call({change_coin_amount, Value, NewAmount}, _From, State) ->
	F = fun() ->
		case mnesia:wread({money, Value}) of
			[] -> {error, not_found};
			[Coin] -> mnesia:write(Coin#money{amount = NewAmount})
		end
	end,
	{reply, transaction(F), State};

handle_call({delete_coin, Value}, _From, State) ->
	{reply, transaction(fun() -> mnesia:delete({money, Value}) end), State};

handle_call(_Request, _From, State) ->
	{reply, {error, unknown_request}, State}.

handle_cast(_Msg, State) ->
	{noreply, State}.

handle_info(_Info, State) ->
	{noreply, State}.

terminate(_Reason, _State) ->
	ok.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%PURCHASE (runs inside one transaction: everything is read fresh and saved together)

try_purchase(Name, Inserted) ->
	InsertedMoney = float(lists:sum(Inserted)),
	case mnesia:wread({item, Name}) of
		[Item = #item{price = Price, amount = Amount}] when Amount > 0 ->
			case InsertedMoney >= Price of
				false ->
					{inserted, InsertedMoney};
				true ->
					RoundedInsertedMoney = round_float(InsertedMoney), %%rounding to 2 decimals
					case calculate_returns(RoundedInsertedMoney - Price, read_all_coins(), []) of
						wrong ->
							{no_change, Inserted};
						ChangeCoins ->
							mnesia:write(Item#item{amount = Amount - 1}),
							update_coin_amount(Inserted, ChangeCoins),
							{bought, round_float(lists:sum(ChangeCoins))} %%rounding to 2 decimals
					end
			end;
		_ ->
			{error, not_available}
	end.

calculate_returns(0.00, _, UsedCoins) -> UsedCoins; %%has to match with float
calculate_returns(_, [], _) -> wrong;
calculate_returns(Diff, [H | T], UsedCoins) ->
	CurrentCoin = H#money.value,
	case H#money.amount > 0 andalso Diff >= CurrentCoin of
		true ->
			RoundedDiff = round_float(Diff - CurrentCoin), %%rounding to 2 decimals
			NewCurrentCoin = H#money{amount = H#money.amount - 1},
			case calculate_returns(RoundedDiff, [NewCurrentCoin | T], UsedCoins ++ [CurrentCoin]) of
				wrong ->
					calculate_returns(Diff, T, UsedCoins);
				Result -> Result
			end;
		false ->
			calculate_returns(Diff, T, UsedCoins)
	end.

update_coin_amount(InsertedCoins, ChangeCoins) ->
	lists:foreach(
		fun(Value) ->
			Total = length([X || X <- InsertedCoins, X =:= Value])
			      - length([X || X <- ChangeCoins, X =:= Value]),
			[Coin] = mnesia:wread({money, Value}),
			mnesia:write(Coin#money{amount = Coin#money.amount + Total})
		end,
		lists:usort(InsertedCoins ++ ChangeCoins)).

round_float(Number) ->
	{RoundedNumber, []} = string:to_float(io_lib:format("~.2f", [Number * 1.0])),
	RoundedNumber.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%HELPERS

transaction(F) ->
	mnesia:activity(transaction, F).

read_all_items() ->
	[Item || Name <- mnesia:all_keys(item), Item <- mnesia:read({item, Name})].

read_all_coins() ->
	[Coin || Value <- lists:reverse(lists:sort(mnesia:all_keys(money))),
	         Coin <- mnesia:read({money, Value})].

item_available_in_db(Name) ->
	case mnesia:read({item, Name}) of
		[#item{amount = Amount}] -> Amount > 0;
		[] -> false
	end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%INITIALISE NEW MNESIA DB
%%Run once from a fresh shell in this folder, before the application is started:
%%    vending_machine_server:init_db().
%%Creates the Mnesia.<node> folder with both tables and the sample items and coins below.
%%Returns ok, or {error, Reason} (e.g. if the database already exists or Mnesia is running).
init_db() ->
	Node = [node()],
	case mnesia:create_schema(Node) of
		ok ->
			ok = mnesia:start(),
			{atomic, ok} = mnesia:create_table(money,
			                 [{attributes, record_info(fields, money)},
			                  {disc_copies, Node}]),
			{atomic, ok} = mnesia:create_table(item,
			                 [{attributes, record_info(fields, item)},
			                  {disc_copies, Node}]),
			F = fun() -> lists:foreach(fun mnesia:write/1, sample_coins() ++ sample_items()) end,
			ok = mnesia:activity(transaction, F),
			stopped = mnesia:stop(),
			ok;
		{error, Reason} ->
			{error, Reason}
	end.

sample_coins() ->
	[#money{value = 5,    amount = 30},
	 #money{value = 2,    amount = 8},
	 #money{value = 1,    amount = 13},
	 #money{value = 0.5,  amount = 12},
	 #money{value = 0.2,  amount = 13},
	 #money{value = 0.1,  amount = 0},
	 #money{value = 0.05, amount = 0},
	 #money{value = 0.02, amount = 0},
	 #money{value = 0.01, amount = 0}].

sample_items() ->
	[#item{name = "Sprite",   price = 2.2, amount = 92},
	 #item{name = "Dorina",   price = 3,   amount = 12},
	 #item{name = "KitKat",   price = 2,   amount = 0},
	 #item{name = "Snickers", price = 1.5, amount = 999},
	 #item{name = "Twix",     price = 1.5, amount = 45},
	 #item{name = "Lays",     price = 1.4, amount = 25}].
