-module(vending_machine_session).
-behaviour(gen_server).
-include("vending_machine_common.hrl").

%%Customer API
-export([start_link/1, select_item/2, insert_coin/2, cancel/1, stop/1]).
%%gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

%%One session per customer console, started by vending_machine_sup:start_session/0.
%%It keeps that customer's purchase; the stock and coins are in vending_machine_server.
-record(state, {owner,              %%the customer's console process
                item = none,        %%name of the selected item, or none
                inserted = []}).    %%values of the coins inserted so far

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%CUSTOMER API

start_link(Owner) -> gen_server:start_link(?MODULE, Owner, []).

%%ok | {error, not_available} | {error, already_selected}
select_item(Session, Name) -> gen_server:call(Session, {select_item, Name}).

%%{inserted, TotalSoFar} | {bought, Change} | {no_change, InsertedCoins}
%%| {error, not_available} | {error, unknown_coin} | {error, no_item_selected}
%%(see vending_machine_server:purchase/2)
insert_coin(Session, Value) -> gen_server:call(Session, {insert_coin, Value}).

%%{refund, InsertedCoins}
cancel(Session) -> gen_server:call(Session, cancel).

stop(Session) -> gen_server:stop(Session).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%GEN_SERVER CALLBACKS

init(Owner) ->
	erlang:monitor(process, Owner), %%if the console goes away, the session ends
	{ok, #state{owner = Owner}}.

handle_call({select_item, Name}, _From, State = #state{item = none}) ->
	case vending_machine_server:item_available(Name) of
		true -> {reply, ok, State#state{item = Name}};
		false -> {reply, {error, not_available}, State}
	end;
handle_call({select_item, _Name}, _From, State) ->
	{reply, {error, already_selected}, State};

handle_call({insert_coin, Value}, _From, State = #state{item = Name, inserted = Inserted})
  when Name =/= none ->
	NewInserted = Inserted ++ [Value],
	case vending_machine_server:purchase(Name, NewInserted) of
		{inserted, Total} ->
			{reply, {inserted, Total}, State#state{inserted = NewInserted}};
		{error, unknown_coin} ->
			{reply, {error, unknown_coin}, State};
		Finished -> %%bought, no_change or not_available: the purchase is over
			{reply, Finished, reset(State)}
	end;
handle_call({insert_coin, _Value}, _From, State) ->
	{reply, {error, no_item_selected}, State};

handle_call(cancel, _From, State = #state{inserted = Inserted}) ->
	{reply, {refund, Inserted}, reset(State)};

handle_call(_Request, _From, State) ->
	{reply, {error, unknown_request}, State}.

handle_cast(_Msg, State) ->
	{noreply, State}.

handle_info({'DOWN', _Ref, process, Owner, _Reason}, State = #state{owner = Owner}) ->
	{stop, normal, State};
handle_info(_Info, State) ->
	{noreply, State}.

terminate(_Reason, _State) ->
	ok.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%UTILS

reset(State) ->
	State#state{item = none, inserted = []}.
