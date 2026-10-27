-module(vending_machine_sup).
-behaviour(supervisor).

-export([start_link/0, start_session/0]).
-export([init/1]).

start_link() -> supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%%Starts a session for the calling process (the customer's console).
%%Sessions are temporary: a crashed session is not restarted, because a fresh
%%one would not know which item was selected or which coins were inserted.
%%A temporary child is removed from the supervisor as soon as it ends.
%%{ok, Session}
start_session() ->
	Session = #{id => {vending_machine_session, make_ref()}, %%unique id per session
	            start => {vending_machine_session, start_link, [self()]},
	            restart => temporary,
	            type => worker},
	supervisor:start_child(?MODULE, Session).

%%one_for_one: every child is restarted on its own.
%%The server holds no customer state, so if it restarts the sessions keep their coins.
%%The server starts first and sessions are added later, so on shutdown
%%(reverse start order) all sessions are stopped before the server.
init([]) ->
	SupFlags = #{strategy => one_for_one, intensity => 5, period => 10},
	Server = #{id => vending_machine_server,
	           start => {vending_machine_server, start_link, []},
	           restart => permanent,
	           type => worker},
	{ok, {SupFlags, [Server]}}.
