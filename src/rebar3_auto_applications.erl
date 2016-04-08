%% @copyright 2016 Hinagiku Soranoba All Rights Reserved.
%%
%% @doc Provider for automatically solving dependent.
-module(rebar3_auto_applications).
-behaviour(provider).

%%----------------------------------------------------------------------------------------------------------------------
%% 'provider' Callback APIs
%%----------------------------------------------------------------------------------------------------------------------
-export([init/1, do/1, format_error/1]).

%%----------------------------------------------------------------------------------------------------------------------
%% Macros
%%----------------------------------------------------------------------------------------------------------------------
-define(DEBUG(Format, Args), rebar_log:log(debug, "[~s:~p] "++Format++"~n", [?MODULE, ?LINE | Args])).

-define(GET_OPT(Key, State, Default),
        proplists:get_value(Key, rebar_state:get(State, auto_app, []), Default)).
-define(NAME(X), binary_to_atom(rebar_app_info:name(X), utf8)).
-define(DO(X),
        (fun() ->
                 case X of
                     {error, __R} -> throw({?MODULE, __R});
                     __Other      -> __Other
                 end
         end)()).

%%----------------------------------------------------------------------------------------------------------------------
%% 'provider' Callback Functions
%%----------------------------------------------------------------------------------------------------------------------

%% @private
init(State) ->
    Profiles = rebar_state:current_profiles(State),
    ?DEBUG("profiles = ~p", [Profiles]),
    Provider = providers:create([{name, auto_app},
                                 {module, ?MODULE},
                                 {bare, true},
                                 {deps, [install_deps]},
                                 {short_desc, "Automatically solve dependent and rewrite .app"}
                                ]),
    {ok, rebar_state:add_provider(State, Provider)}.

%% @private
do(State) ->
    try
        _ = ?DO(xref:start(?MODULE, [{xref_mode, modules}])),

        ProjectApps = rebar_state:project_apps(State),
        ?DEBUG("project_apps = ~s", [ binary_join([rebar_app_info:name(App) || App <- ProjectApps], <<",">>) ]),

        ok = register_depending_applications(State),

        lists:foreach(fun(App) ->
                              Applications0 = analyze_direct_depending_applications(App),
                              Applications1 = case is_root_app(App, State) of
                                                  true ->
                                                      Applications0 ++ [?NAME(X) || X <- ProjectApps, X =/= App];
                                                  false ->
                                                      remove_circular_reference_if_neseccary(App, Applications0, State)
                                              end,
                              rewrite_applications(App, Applications1)
                      end, ProjectApps),
        _ = xref:stop(?MODULE),
        {ok, State}
    catch
        throw:{?MODULE, Reason_} -> {error, {?MODULE, Reason_}}
    end.

%% @private
format_error(Reason) ->
    io_lib:format("~p", [Reason]).

%%----------------------------------------------------------------------------------------------------------------------
%% Internal Functions
%%----------------------------------------------------------------------------------------------------------------------

%% @doc Register depending applications to xref server.
-spec register_depending_applications(rebar_state:t()) -> ok.
register_depending_applications(State) ->
    AllApps = rebar_state:all_deps(State) ++ rebar_state:project_apps(State),
    lists:foreach(fun(App) ->
                          AppName = ?NAME(App),
                          Dir = filename:dirname(rebar_app_info:ebin_dir(App)),
                          ?DEBUG("add : ~p (~s)", [AppName, Dir]),
                          ?DO(xref:add_application(?MODULE, Dir, [{name, AppName}]))
                  end, AllApps).

%% @doc Return the project apps in the order specified.
-spec ordering_project_apps(rebar_state:t()) -> [rebar_app_info:t()].
ordering_project_apps(State) ->
    ProjectApps    = rebar_state:project_apps(State),
    ProjectAppDirs = lists:flatmap(fun filelib:wildcard/1, rebar_state:get(State, project_app_dirs)),
    DirAppLists    = [{rebar_app_info:dir(App), App} || App <- ProjectApps],
    Rev = lists:foldl(fun(Dir, Acc) ->
                              ProjectDir = filename:dirname(filename:absname(filename:join(Dir, "dummy"))),
                              case proplists:lookup(ProjectDir, DirAppLists) of
                                  none   -> Acc;
                                  {_, V} -> case lists:member(V, Acc) of
                                                true  -> Acc;
                                                false -> [V | Acc]
                                            end
                              end
                      end, [], ProjectAppDirs),
    lists:reverse(Rev).

%% @doc Remove circular references in the project apps if necessary.
-spec remove_circular_reference_if_neseccary(ProjectApp, DependingApps, rebar_state:t()) -> [atom()] when
      ProjectApp    :: rebar_app_info:t(),
      DependingApps :: [atom()].
remove_circular_reference_if_neseccary(ProjectApp, DependingApps, State) ->
    case ?GET_OPT(remove_circulation, State, false) of
        true ->
            OrderingProjectApps = ordering_project_apps(State),
            ?DEBUG("project_app_dirs = ~s",
                   [string:join([rebar_app_info:dir(App) || App <- OrderingProjectApps], ",")]),
            {_, RemoveApps} = lists:splitwith(fun(X) -> X =/= ProjectApp end, OrderingProjectApps),
            (DependingApps -- lists:map(fun(App) -> ?NAME(App) end, RemoveApps)) -- [?GET_OPT(root_app, State, [])];
        false ->
            DependingApps
    end.

%% @doc Return application names that has been referred to in the application
-spec analyze_direct_depending_applications(rebar_app_info:t()) -> [atom()].
analyze_direct_depending_applications(App) ->
    AppName = ?NAME(App),
    {ok, Calls} = ?DO(xref:analyze(?MODULE, {application_call, AppName})),
    Calls -- [AppName].

%% @doc Return true, if the application is a specifed root application, otherwise false.
-spec is_root_app(rebar_app_info:t(), rebar_state:t()) -> boolean().
is_root_app(App, State) ->
    ?GET_OPT(root_app, State, []) =:= ?NAME(App).

%% @doc Rewrite applications field of .app
-spec rewrite_applications(rebar_app_info:t(), [atom()]) -> ok.
rewrite_applications(App, Applications0) ->
    AppFile = rebar_app_info:app_file(App),
    {ok, [{application, AppName, AppKeys0}]} = file:consult(AppFile),
    Applications = lists:usort(Applications0 ++ proplists:get_value(applications, AppKeys0, [])),
    AppKeys1 = lists:keystore(applications, 1, AppKeys0, {applications, Applications}),
    ?DEBUG("rewrite : ~s (~s)", [ string:join([atom_to_list(X) || X <- Applications], ","), AppFile]),
    rebar_file_utils:write_file_if_contents_differ(AppFile, io_lib:format("~p.\n", [{application, AppName, AppKeys1}])).

%% @doc Returns a binary with the elements of BinList separated by the binary in Separator.
-spec binary_join([binary()], binary()) -> binary().
binary_join([], _)  -> <<>>;
binary_join([H], _) -> H;
binary_join([H1, H2 | Rest], Separator) ->
    binary_join([<<H1/binary, Separator/binary, H2/binary>> | Rest], Separator).
