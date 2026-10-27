{application, vending_machine,
 [{description, "Vending machine"},
  {vsn, "1.0.0"},
  {modules, [vending_machine_app, vending_machine_sup, vending_machine_server,
             vending_machine_session,
             vending_machine_user, vending_machine_admin, vending_machine_utils]},
  {registered, [vending_machine_sup, vending_machine_server]},
  {applications, [kernel, stdlib, mnesia]},
  {mod, {vending_machine_app, []}}]}.
