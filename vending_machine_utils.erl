-module(vending_machine_utils).
-export([read_choice/2]).

%%Reads a menu choice and checks that it is an integer between 1 and Max.
%%Returns {ok, N}, too_large (integer above Max) or invalid (anything else).
read_choice(Prompt, Max) ->
	case io:read(Prompt) of
		{ok, N} when is_integer(N), N >= 1, N =< Max -> {ok, N};
		{ok, N} when is_integer(N), N > Max -> too_large;
		{ok, _} -> invalid;
		{error, _} -> invalid
	end.
