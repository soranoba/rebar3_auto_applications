rebar3_auto_applications
======
Provider for automatically solving dependent.

It is a plugin of [rebar3](https://github.com/erlang/rebar3).

## Overview
Automatically add the applications elements of the `.app`.

- It doesn't look for system libraries. So, you must write it.
- It can remove the circular reference.

## Usage

```erlang
{plugins, [rebar3_auto_applications]}.
{provider_hooks, [{post, [{compile, auto_app}]}]}.

{project_app_dirs, ["apps/a, apps/b, apps/c"]}.
%%
%% You must write applications in the order in which you want to start,
%% if you use the remove_circulation option.
%%
%% If you include the current directory (".") in project_app_dirs, hook will not work correctly.
%%

{auto_app, [
            {root_app, atom()},
            {remove_circulation, boolean()}
           ]}.
%% options
%%
%% - root_app
%%     When you start the root_app, all of the other project_apps will launch.
%% - remove_circulation
%%     Remove the circular reference between the project_apps.
%%
```

## License
[MIT License](LICENSE)
