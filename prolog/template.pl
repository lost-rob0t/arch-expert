% Command templates: raw command line <-> typed template <-> filled argv.

:- module(template, [
    infer_template/2,   % +RawLine, -t(Cmd, Parts)
    render_generic/2,   % +Template, -String with {{type}} slots
    render_example/2,   % +Template, -String with {{type:example}} slots
    fill/3,             % +Template, +SlotValues, -Argv
    slots/2,            % +Parts, -Slots
    join_words/2
]).
:- set_prolog_flag(double_quotes, string).
:- use_module(types).

infer_template(Line, t(Cmd, Parts)) :-
    split_string(Line, " ", "\t ", Toks),
    Toks = [Cmd|Rest],
    Cmd \= "",
    parts_from_tokens(Cmd, Rest, "", Parts).

parts_from_tokens(_, [], _, []).
parts_from_tokens(Cmd, [T|Ts], Prev, [P|Ps]) :-
    infer_part(Cmd, Prev, T, P),
    parts_from_tokens(Cmd, Ts, T, Ps).

% ---------------------------------------------------------------- rendering

render_generic(t(Cmd, Parts), Str) :-
    render_parts(Parts, generic, Ws),
    join_words([Cmd|Ws], Str).

render_example(t(Cmd, Parts), Str) :-
    render_parts(Parts, example, Ws),
    join_words([Cmd|Ws], Str).

render_parts([], _, []).
render_parts([literal(S)|Ps], M, [S|Ws]) :- !,
    render_parts(Ps, M, Ws).
render_parts([slot(T, Ex)|Ps], M, [W|Ws]) :- !,
    slot_word(T, Ex, M, W),
    render_parts(Ps, M, Ws).

slot_word(T, _, generic, W) :-
    !, format(string(W), "{{~w}}", [T]).
slot_word(T, Ex, example, W) :-
    ( Ex == ""
    -> format(string(W), "{{~w}}", [T])
    ;  format(string(W), "{{~w:~w}}", [T, Ex]) ).

slots(Parts, Slots) :-
    findall(S, (member(S, Parts), S = slot(_, _)), Slots).

% ---------------------------------------------------------------- filling

fill(t(Cmd, Parts), Vals, Argv) :-
    fill_parts(Parts, Vals, Ws),
    Argv = [Cmd|Ws].

fill_parts([], [], []).
fill_parts([literal(S)|Ps], Vs, [S|Ws]) :- !,
    fill_parts(Ps, Vs, Ws).
fill_parts([slot(_, _)|_], [], _) :-
    !, throw(missing_slot_values).
fill_parts([slot(_, _)|Ps], [V|Vs], [V|Ws]) :- !,
    fill_parts(Ps, Vs, Ws).

join_words([], "").
join_words([W|Ws], Str) :-
    foldl(cat_sep, Ws, W, Str).

cat_sep(Word, Acc0, Acc) :-
    string_concat(Acc0, " ", T),
    string_concat(T, Word, Acc).
