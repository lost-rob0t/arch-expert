% Shell execution helpers: captured probes and interactive runs.

:- module(cmdrun, [run_capture/3, run_interactive/2, probe_lines/2]).
:- set_prolog_flag(double_quotes, string).

run_capture(Cmd, Exit, Out) :-
    process_create("/bin/sh", ["-c", Cmd],
                   [stdout(pipe(O)), stderr(pipe(E)), process(P)]),
    read_string(O, _, SO),
    read_string(E, _, SE),
    wait(P, Status),
    exit_code(Status, Exit),
    (   SE == ""
    ->  Out = SO
    ;   string_concat(SO, "\n[stderr]\n", T),
        string_concat(T, SE, Out)
    ).

exit_code(exited(N), N) :- !.
exit_code(_, 1).

run_interactive(Cmd, Exit) :-
    shell(Cmd, Exit).

% Lines of a probe command; empty list on any failure.
probe_lines(Cmd, Lines) :-
    catch(run_capture(Cmd, _, Out), _, Out = ""),
    (   var(Out)
    ->  Lines = []
    ;   split_string(Out, "\n", " \r", L0),
        exclude(==(""), L0, Lines)
    ).
