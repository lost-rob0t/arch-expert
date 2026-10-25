% arch-expert: CLI entrypoint, interactive troubleshooter, add wizard, shell,
% and a machine-facing plan API (plan/2, plan_fixes/2, `arch-expert json`).

:- module(arch_expert, [cli_main/0, plan/2, plan_fixes/2]).
:- set_prolog_flag(double_quotes, string).

:- use_module(types).
:- use_module(template).
:- use_module(kb).
:- use_module(prompt).
:- use_module(cmdrun).
:- use_module(library(ansi_term)).
:- use_module(library(json)).

cli_main :-
    current_prolog_flag(argv, Argv0),
    maplist(to_string, Argv0, Argv),
    (   catch(dispatch(Argv), prompt_eof, (format("input closed~n"), fail))
    ->  halt(0)
    ;   halt(1)
    ).

to_string(X, S) :-
    (   string(X) -> S = X
    ;   atom(X)   -> atom_string(X, S)
    ;   term_to_atom(X, S)
    ).

% ---------------------------------------------------------------- dispatch

dispatch([])                  :- usage.
dispatch(["help"])            :- usage.
dispatch(["-h"])              :- usage.
dispatch(["--help"])          :- usage.
dispatch(["list"])            :- cmd_list.
dispatch(["find", Q])         :- cmd_find(Q).
dispatch(["kb"])              :- cmd_kb.
dispatch(["json"])            :- cmd_json.
dispatch(["json", N])         :- cmd_json(N).
dispatch(["shell"])           :- cmd_shell.
dispatch(["add", N])          :- cmd_add(N).
dispatch(["troubleshoot", N]) :- cmd_troubleshoot(N).
dispatch(["debug", N])        :- cmd_troubleshoot(N).
dispatch([N]) :-
    load_kbs,
    resolve_problem(N, _),
    cmd_show(N).

usage :-
    format("arch-expert - typed command playbooks for system troubleshooting~n~n", []),
    format("  arch-expert list                    list known problems~n", []),
    format("  arch-expert <problem>               show a problem's playbook~n", []),
    format("  arch-expert troubleshoot <problem>  walk diagnostics + fixes step by step~n", []),
    format("  arch-expert add <problem-name>      record a new problem (interactive)~n", []),
    format("  arch-expert find <text>             search names, descriptions, symptoms~n", []),
    format("  arch-expert shell                   interactive expert shell~n", []),
    format("  arch-expert kb                      show knowledge base locations~n", []),
    format("  arch-expert json [problem]          machine-readable playbook (JSON)~n", []),
    format("~nslot types: ", []),
    forall(known_type(T), format("~w ", [T])),
    format("~n", []).

% ---------------------------------------------------------------- commands

cmd_list :-
    load_kbs,
    known_problems(Ns),
    (   Ns == []
    ->  format("knowledge base is empty; seed it with `arch-expert add <name>`~n", [])
    ;   forall(member(N, Ns),
               (   problem_info(N, D, _),
                   format("  ~w~n      ~s~n", [N, D])
               ))
    ).

cmd_find(Q) :-
    load_kbs,
    find_problems(Q, Ms),
    (   Ms == []
    ->  format("no matches for '~s'~n", [Q])
    ;   forall(member(N, Ms),
               (   problem_info(N, D, _),
                   format("  ~w~n      ~s~n", [N, D])
               ))
    ).

cmd_kb :-
    load_kbs,
    bundled_kb_dir(B), user_kb_dir(U), state_dir(S),
    problem_count(N),
    format("bundled kb: ~s~nuser kb:   ~s~nstate dir:  ~s~nproblems:   ~d~n", [B, U, S, N]).

% ------------------------------------------------------------ machine API

% plan(+Problem, -Steps): rendered diagnostics as dicts, for embedding hosts
% (Zara sidecar, opencode agents) that query Prolog directly.
plan(Problem, Steps) :-
    load_kbs,
    problem_diags(Problem, Ds),
    maplist(step_dict(diag), Ds, Steps).

plan_fixes(Problem, Steps) :-
    load_kbs,
    problem_fixes(Problem, Fs),
    maplist(fix_dict, Fs, Steps).

step_dict(Kind, T-E, #{kind: Kind, command: C, slots: SlotTs, explanation: E}) :-
    render_generic(T, C),
    T = t(_, Parts),
    findall(S, member(slot(S, _), Parts), SlotTs).

fix_dict(prose(Text), #{kind: note, text: Text}) :-
    !.
fix_dict(cmd(T, E), Dict) :-
    step_dict(fix, T-E, Dict).

cmd_json :-
    load_kbs,
    known_problems(Ns),
    maplist(name_dict, Ns, Ds),
    json_write_dict(current_output, Ds),
    nl.

name_dict(N, #{name: Name, description: D}) :-
    atom_string(N, Name),
    problem_info(N, D, _).

cmd_json(UserN) :-
    load_kbs,
    resolve_problem(UserN, Name),
    problem_info(Name, D, _),
    problem_symptoms(Name, Ss),
    plan(Name, Diags),
    plan_fixes(Name, Fixes),
    atom_string(Name, NameS),
    json_write_dict(current_output,
                    #{name: NameS,
                      description: D,
                      symptoms: Ss,
                      diagnostics: Diags,
                      fixes: Fixes}),
    nl.

cmd_show(UserN) :-
    load_kbs,
    resolve_problem(UserN, Name),
    show_problem(Name).

show_problem(Name) :-
    problem_info(Name, D, Ts),
    ansi_format([bold], "~w~n", [Name]),
    format("  ~s~n", [D]),
    (   Ts == [] -> true
    ;   format("  tags: ", []),
        forall(member(T, Ts), format("~s ", [T])),
        format("~n", [])
    ),
    problem_symptoms(Name, Ss),
    (   Ss == [] -> true
    ;   ansi_format([fg(cyan)], "symptoms:~n", []),
        forall(member(S, Ss), format("  - ~s~n", [S]))
    ),
    problem_diags(Name, Ds),
    (   Ds == [] -> true
    ;   ansi_format([fg(cyan)], "diagnostics:~n", []),
        forall(nth1(I, Ds, T-E),
               (   render_example(T, S),
                   format("  ~d. ~s~n      ~s~n", [I, S, E])
               ))
    ),
    problem_fixes(Name, Fs),
    (   Fs == [] -> true
    ;   ansi_format([fg(cyan)], "fixes:~n", []),
        forall(nth1(J, Fs, Step), show_fix_step(J, Step))
    ).

show_fix_step(J, prose(Text)) :-
    !,
    format("  ~d. (prose) ~s~n", [J, Text]).
show_fix_step(J, cmd(T, E)) :-
    render_example(T, S),
    format("  ~d. ~s~n      ~s~n", [J, S, E]).

resolve_problem(User, Name) :-
    atom_string(NAtom, User),
    (   problem_info(NAtom, _, _)
    ->  Name = NAtom
    ;   find_problems(User, [Single])
    ->  Name = Single
    ;   find_problems(User, Many), Many \= []
    ->  choose("which problem?", Many, _, Sel),
        atom_string(Name, Sel)
    ;   format("no problem matching '~s'; `arch-expert list` to browse~n", [User]),
        fail
    ).

% ---------------------------------------------------------------- troubleshoot

cmd_troubleshoot(UserN) :-
    load_kbs,
    resolve_problem(UserN, Name),
    catch(troubleshoot(Name), abort_troubleshoot, true).

troubleshoot(Name) :-
    problem_info(Name, D, _),
    ansi_format([bold], "=== troubleshoot: ~w ===~n", [Name]),
    format("~s~n~n", [D]),
    problem_symptoms(Name, Ss),
    forall(member(S, Ss), format("symptom: ~s~n", [S])),
    problem_diags(Name, Ds),
    run_steps("DIAG", Ds, Ran1),
    problem_fixes(Name, Fs),
    run_steps("FIX", Fs, Ran2),
    append(Ran1, Ran2, Ran),
    catch(append_session(Name, Ran), _, true),
    format("~nlearned something new? `arch-expert add <name>` records it for next time.~n", []).

run_steps(_, [], []).
run_steps(Kind, [Step|Rest], Ran) :-
    (   run_step(Kind, Step, Cmd)
    ->  Ran = [Cmd|Ran0]
    ;   Ran = Ran0
    ),
    !,
    run_steps(Kind, Rest, Ran0).

% diag entries arrive as Template-Expl pairs; fix entries as cmd/2 or prose/1.
run_step(Kind, T-E, Cmd) :-
    T = t(_, _),
    !,
    ansi_format([bold, fg(cyan)], "~s: ~s~n", [Kind, E]),
    render_generic(T, Gen),
    format("  plan: ~s~n", [Gen]),
    fill_interactive(T, Cmd),
    maybe_run(Cmd).
run_step(Kind, cmd(T, E), Cmd) :-
    !,
    run_step(Kind, T-E, Cmd).
run_step(_, prose(Text), _) :-
    !,
    ansi_format([bold, fg(yellow)], "NOTE: ~s~n", [Text]),
    fail.

fill_interactive(t(Cmd, Parts), CmdS) :-
    slots(Parts, Ss),
    fill_slots(Ss, Vals),
    fill(t(Cmd, Parts), Vals, Argv),
    join_words(Argv, CmdS).

fill_slots([], []).
fill_slots([slot(T, Ex)|Ss], [V|Vs]) :-
    !,
    fill_slot(T, Ex, V),
    fill_slots(Ss, Vs).

fill_slot(T, Ex, V) :-
    type_prompt(T, P),
    (   catch(suggest_values(T, Opts), _, Opts = []),
        Opts \= []
    ->  choose(P, Opts, Ex, V0)
    ;   ask_default(P, Ex, V0)
    ),
    (   validate(T, V0)
    ->  V = V0
    ;   ansi_format([fg(red)], "  '~s' is not a valid ~w~n", [V0, T]),
        fill_slot(T, Ex, V)
    ).

suggest_values(device, Opts) :-
    !, probe_lines("lsblk -dn -o PATH", Opts).
suggest_values(mountpoint, Opts) :-
    !, probe_lines("findmnt -rn -o TARGET", O0), sort(O0, Opts).
suggest_values(service, Opts) :-
    !,
    probe_lines("systemctl list-units --state=failed --no-legend --plain", L),
    maplist(first_word, L, O0),
    sort(O0, Opts).
suggest_values(kernel_version, Opts) :-
    !,
    probe_lines("ls /boot", L0),
    include(vmlinuz, L0, L),
    maplist(strip_vmlinuz, L, Opts).
suggest_values(_, []).

first_word(Line, W) :-
    split_string(Line, " ", " ", [W|_]).
vmlinuz(S) :- sub_string(S, 0, 8, _, "vmlinuz-").
strip_vmlinuz(S, W) :- sub_string(S, 8, _, 0, W).

maybe_run(Cmd) :-
    dangerous(Cmd),
    !,
    ansi_format([fg(red)], "  ~s~n", [Cmd]),
    (   confirm("  DESTRUCTIVE - really run? [y/N]")
    ->  execute(Cmd)
    ;   format("  skipped~n", [])
    ).
maybe_run(Cmd) :-
    (   confirm("  run? [y/N]")
    ->  execute(Cmd)
    ;   format("  skipped~n", [])
    ).

execute(Cmd) :-
    format("  $ ~s~n", [Cmd]),
    run_interactive(Cmd, Exit),
    (   Exit == 0
    ->  format("  [exit 0]~n", [])
    ;   format("  [exit ~d]~n", [Exit])
    ).

dangerous(Cmd) :-
    member(D, ["mkfs", "wipefs", "shred", "blkdiscard", "rm -rf", "dd ",
               "sgdisk --zap", "parted ", "zpool destroy"]),
    sub_string(Cmd, _, _, _, D).

% ---------------------------------------------------------------- add wizard

cmd_add(RawName) :-
    load_kbs,
    normalize_name(RawName, Name),
    (   problem_info(Name, _, _)
    ->  format("note: '~w' already known; new facts will override it~n", [Name])
    ;   true
    ),
    ansi_format([bold], "=== add problem: ~w ===~n", [Name]),
    ask("one-line description", Desc),
    ask("tags, comma separated", TagsRaw),
    split_string(TagsRaw, ",", " \t", Tags0),
    exclude(==(""), Tags0, Tags),
    format("symptoms, one per line, empty line to finish:~n", []),
    read_lines("symptom", Symptoms),
    format("diagnostic commands; type each as you would run it, empty line to finish:~n", []),
    read_command_steps("diag command", Diags),
    format("fixes: a shell command (typed like above), or 'prose: <free text>', empty line to finish:~n", []),
    read_command_steps("fix", Fixes),
    summary(Name, Desc, Symptoms, Diags, Fixes),
    (   confirm("save to user kb? [y/N]")
    ->  add_problem(Name, Desc, Tags, Symptoms, Diags, Fixes),
        user_kb_dir(U),
        ansi_format([fg(green)], "saved to ~s/problems.pl~n", [U]),
        format("try it: arch-expert troubleshoot ~w~n", [Name])
    ;   format("discarded~n", [])
    ).

read_lines(Prompt, Ls) :- read_lines_(Prompt, [], Ls).
read_lines_(Prompt, Acc, Ls) :-
    ask(Prompt, S),
    (   S == ""
    ->  reverse(Acc, Ls)
    ;   read_lines_(Prompt, [S|Acc], Ls)
    ).

read_command_steps(Prompt, Steps) :- read_steps_(Prompt, [], Steps).
read_steps_(Prompt, Acc, Steps) :-
    ask(Prompt, S),
    (   S == ""
    ->  reverse(Acc, Steps)
    ;   parse_step(S, Step)
    ->  read_steps_(Prompt, [Step|Acc], Steps)
    ;   read_steps_(Prompt, Acc, Steps)
    ).

parse_step(S, prose(Text)) :-
    string_concat("prose:", Rest, S),
    !,
    split_string(Rest, " ", " ", Words),
    atomic_list_concat(Words, ' ', A),
    atom_string(A, Text).
parse_step(S, Step) :-
    catch(record_command(S, Step), E, print_message(error, E)).

record_command(Line, cmd(t(C, P), E)) :-
    infer_template(Line, t(C, P0)),
    confirm_slots(P0, P),
    render_example(t(C, P), Ex),
    format("  stored as: ~s~n", [Ex]),
    ask("  what does it check/do", E).

confirm_slots([], []).
confirm_slots([slot(T, Ex)|Ps], [P|Qs]) :-
    !,
    findall(K, known_type(K), Ks),
    format("  slot '~s' inferred as ~w~n", [Ex, T]),
    ask_default("  keep type (enter) or override", T, A0),
    (   A0 == "literal"
    ->  P = literal(Ex)
    ;   atom_string(K, A0),
        memberchk(K, Ks)
    ->  P = slot(K, Ex)
    ;   P = slot(T, Ex)
    ),
    confirm_slots(Ps, Qs).
confirm_slots([literal(S)|Ps], [literal(S)|Qs]) :-
    confirm_slots(Ps, Qs).

summary(Name, Desc, Symptoms, Diags, Fixes) :-
    ansi_format([bold], "~n~w: ~s~n", [Name, Desc]),
    forall(member(S, Symptoms), format("  symptom: ~s~n", [S])),
    forall(nth1(I, Diags, cmd(T, E)),
           (   render_example(T, S),
               format("  diag ~d: ~s  (~s)~n", [I, S, E]) )),
    forall(nth1(J, Fixes, F), show_fix_step(J, F)).

% ---------------------------------------------------------------- shell

cmd_shell :-
    load_kbs,
    banner,
    catch(shell_iterations, stop_shell, true).

banner :-
    ansi_format([bold], "arch-expert shell~n", []),
    format("commands: list | show <p> | troubleshoot <p> | add <p> | find <t> | kb | help~n", []),
    format("          !<shell cmd>  runs a shell command~n", []),
    format("          ?- <goal>.    evaluates Prolog in the expert's context~n", []),
    format("          quit~n~n", []).

shell_iterations :-
    format("arch-expert> "),
    flush_output(user_output),
    read_line_to_string(current_input, S),
    (   S == end_of_file
    ->  format("~nbye~n", [])
    ;   catch(shell_dispatch(S), E,
              (   E = prompt_eof
              ->  throw(stop_shell)
              ;   print_message(error, E)
              )) -> true
    ;   true
    ),
    S \== end_of_file,
    shell_iterations.

shell_dispatch("quit") :- !, throw(prompt_eof).
shell_dispatch("exit") :- !, throw(prompt_eof).
shell_dispatch("!") :- !, true.
shell_dispatch(S) :-
    string_concat("!", Cmd, S),
    Cmd \= "",
    !,
    run_interactive(Cmd, _).
shell_dispatch(S) :-
    string_concat("?-", GoalS, S),
    !,
    prolog_goal(GoalS).
shell_dispatch(S) :-
    split_string(S, " ", " ", [Word|Args]),
    !,
    shell_cmd(Word, Args).
shell_dispatch(_).

shell_cmd("help", _)           :- !, banner.
shell_cmd("list", _)           :- !, cmd_list.
shell_cmd("kb", _)             :- !, cmd_kb.
shell_cmd("show", [N])         :- !, cmd_show(N).
shell_cmd("find", [Q])         :- !, cmd_find(Q).
shell_cmd("troubleshoot", [N]) :- !, cmd_troubleshoot(N).
shell_cmd("add", [N])          :- !, cmd_add(N).
shell_cmd("add", [])           :- !, ask("problem name", N), cmd_add(N).
shell_cmd(_, _)                :- format("unknown command; 'help' for usage~n", []).

prolog_goal(GoalS) :-
    ensure_period(GoalS, G0),
    atom_string(A, G0),
    catch(read_term_from_atom(A, Goal, [variable_names(VN)]),
          E, (print_message(error, E), fail)),
    (   catch(call(Goal), E, (print_message(error, E), fail))
    ->  print_bindings(VN)
    ;   format("false.~n", [])
    ).

ensure_period(S, S) :- sub_string(S, _, 1, _, "."), !.
ensure_period(S, SP) :- string_concat(S, ".", SP).

print_bindings([]) :-
    !, format("true.~n", []).
print_bindings(VN) :-
    forall(member(Name=Value, VN),
           format("  ~w = ~q~n", [Name, Value])).
