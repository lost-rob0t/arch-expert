% Interactive prompting helpers.  All throw prompt_eof on closed input so
% non-interactive callers fail loudly instead of spinning.

:- module(prompt, [ask/2, ask_default/3, confirm/1, choose/4]).
:- set_prolog_flag(double_quotes, string).

ask(Msg, A) :-
    format("~s: ", [Msg]),
    flush_output(user_output),
    read_line_to_string(current_input, S),
    (   S == end_of_file
    ->  throw(prompt_eof)
    ;   S = A
    ).

ask_default(Msg, Def, A) :-
    format("~s [~w]: ", [Msg, Def]),
    flush_output(user_output),
    read_line_to_string(current_input, S),
    (   S == end_of_file
    ->  throw(prompt_eof)
    ;   S == ""
    ->  A = Def
    ;   S = A
    ).

confirm(Msg) :-
    ask_default(Msg, "n", S),
    member(S, ["y", "Y", "yes"]).

choose(Msg, Options, Def, Sel) :-
    length(Options, L),
    choose_(Msg, Options, Def, L, 0, Sel).

choose_(Msg, Options, Def, L, Try, Sel) :-
    Try < 5,
    !,
    forall(nth1(I, Options, O), format("  ~d) ~s~n", [I, O])),
    ask_default(Msg, Def, S),
    (   number_string(N, S), between(1, L, N)
    ->  nth1(N, Options, Sel)
    ;   member(S, Options)
    ->  Sel = S
    ;   T2 is Try + 1,
        choose_(Msg, Options, Def, L, T2, Sel)
    ).
choose_(_, _, _, _, _, _) :-
    format("too many invalid choices~n"),
    fail.
