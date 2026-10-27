# Vending machine

A console vending machine written in Erlang, with stock and coins stored in Mnesia.
Customers pick an item, insert coins and get change; an admin console manages items, prices and coins.

## History

The original version was written in 2023 as a short Erlang exercise.

In 2026 I revisited it with the help of Claude and restructured it into a proper OTP application:

- all business logic moved into a proper `gen_server`; the consoles only read input and print
- every sale is one Mnesia transaction, based on fresh data
- several customers can shop at the same time, each in their own supervised session
- packaged as an OTP application with a supervisor, started with one call

## Architecture (gen_server version)

```
vending_machine (application, depends on mnesia)
└── vending_machine_sup                 one_for_one
    ├── vending_machine_server          stock, coins, sales (permanent)
    ├── vending_machine_session         customer 1 (temporary)
    ├── vending_machine_session         customer 2 (temporary)
    └── ...
```

| File | Role |
|---|---|
| `vending_machine.app` | Application description: dependencies (`mnesia`) and start module |
| `vending_machine_app.erl` | Application callback, starts the supervisor |
| `vending_machine_sup.erl` | Supervisor for the server and all sessions; `start_session/0` adds a session |
| `vending_machine_server.erl` | `gen_server` owning the shared stock and coins; sells items in one transaction |
| `vending_machine_session.erl` | `gen_server` per customer: selected item and inserted coins |
| `vending_machine_user.erl` | Customer console |
| `vending_machine_admin.erl` | Admin console |
| `vending_machine_utils.erl` | Menu input validation |
| `vending_machine_common.hrl` | Shared `item` and `money` records |

Design decisions:

- **The server holds no customer state.** If it crashes, the supervisor restarts it and customers keep their inserted coins, because those live in their sessions.
- **Sessions are temporary.** A crashed session is not restarted, since a fresh one would not know what the customer had inserted. A session ends when its console exits or dies.
- **No reservations.** Two customers can select the last item; whoever pays first gets it, the other gets their money back.
- **One supervisor.** Sessions are added to the same `one_for_one` supervisor as the server, instead of a separate `simple_one_for_one` supervisor, which keeps the tree small. On shutdown, sessions are stopped before the server.

## Running

Requires Erlang/OTP (tested with OTP 25).

```
erlc *.erl
erl
```

Start `erl` from inside the folder, so that the `.app` file and the `Mnesia.nonode@nohost` database are found.
On the first run, create the database first (see [Database](#database) below).

In the Erlang shell:

```erlang
vending_machine_admin:start().   %% admin console
vending_machine_user:start().    %% customer console
```

Whichever console is started first starts the application. Menu choices are Erlang terms, so end each input with a dot, e.g. `1.`

To stop everything:

```erlang
application:stop(vending_machine),
application:stop(mnesia).
```

### Database

The database is not part of the repository. Before the first start, create it once from a fresh Erlang shell in this folder:

```erlang
vending_machine_server:init_db().
```

This creates the `Mnesia.nonode@nohost/` folder with both tables and sample items and coins (edit `sample_items/0` and `sample_coins/0` to change them).
It returns `{error, ...}` instead of overwriting anything if the database already exists; to start over, delete the folder and run it again.

The folder name comes from the Erlang node name, so start `erl` the same way (e.g. without `-sname`) when creating the database and when running the application.

## Testing

EUnit tests cover the server (admin operations, purchases, change calculation, `init_db/0`) and the customer sessions (purchase flow, several customers at once, crash recovery).
Each test runs against its own temporary database, so your `Mnesia.nonode@nohost` is never touched. Running the tests stops the application if it is running.

```
erlc *.erl
erl -noshell -eval "eunit:test([vending_machine_server_tests, vending_machine_session_tests], [verbose]), halt()."
```

| File | Tests |
|---|---|
| `vending_machine_server_tests.erl` | Admin API, item and coin lists, purchases and change, `init_db/0` |
| `vending_machine_session_tests.erl` | Purchase flow, cancelling, two customers and the race for the last item, server/console/session crashes |
| `vending_machine_test_setup.erl` | Shared setup: temporary database, test data, helpers |

## Known limitations

- Money is stored as floats and rounded to two decimals at each step.
- The admin console does not validate prices and amounts.
- If the server crashes in the middle of a purchase call, that customer's session crashes too and their inserted coins are lost.
- Everything runs on one Erlang node.
