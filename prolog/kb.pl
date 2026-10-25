% Durable knowledge base: bundled defaults plus a user overlay that wins.

:- module(kb, [
    load_kbs/0, load_kbs/1,
    bundled_kb_dir/1, user_kb_dir/1,
    known_problems/1, known_problem/1, problem_count/1,
    problem_info/3, problem_symptoms/2,
    problem_diags/2, problem_fixes/2,
    find_problems/2,
    normalize_name/2,
    add_problem/6,
    state_dir/1, append_session/2
]).
:- set_prolog_flag(double_quotes, string).

:- dynamic problem/3.   % problem(Name, Desc, Tags)
:- dynamic symptom/2.   % symptom(Name, Text)
:- dynamic diag/4.      % diag(Name, Order, Template, Expl)
:- dynamic fix/3.       % fix(Name, Order, Step)  Step = cmd(Template, Expl) | prose(Text)
:- discontiguous problem/3, symptom/2, diag/4, fix/3.
:- dynamic loaded/1.
:- dynamic source_dir/1.

:- (   prolog_load_context(directory, Dir)
   ->  atom_string(Dir, D0),
       format(string(D), "~s/..", [D0]),
       assertz(source_dir(D))
   ).

env_string(Name, S) :- getenv(Name, A), to_str(A, S).
to_str(A, S) :- atom(A), !, atom_string(A, S).
to_str(S, S).

home_dir(H) :- env_string("HOME", H), !.
home_dir("/root").

user_kb_dir(D) :-
    (   env_string("ARCH_EXPERT_KB", U)
    ->  D = U
    ;   home_dir(H),
        format(string(D), "~s/.local/share/arch-expert/kb", [H])
    ).

bundled_kb_dir(D) :-
    (   env_string("ARCH_EXPERT_HOME", B)
    ->  format(string(D), "~s/kb", [B])
    ;   source_dir(S),
        format(string(D), "~s/kb", [S])
    ).

% ---------------------------------------------------------------- loading

load_kbs :- load_kbs(force).

load_kbs(_) :- loaded(all), !.
load_kbs(_) :-
    load_kb_dir(bundled_kb_dir),
    load_kb_dir(user_kb_dir),
    assertz(loaded(all)).

load_kb_dir(DSpec) :-
    call(DSpec, D),
    (   exists_directory(D)
    ->  load_kb_files(D)
    ;   true
    ).

load_kb_files(D) :-
    atom_string(DA, D),
    directory_files(DA, Fs0),
    include(pl_file, Fs0, Fs),
    sort(Fs, FsS),
    forall(member(F, FsS), safe_load(D, F)).

pl_file(F) :- sub_atom(F, _, 3, _, ".pl"), F \= ".", F \= "..".

% Load KB clauses by asserting them: unlike consult/1 this merges facts from
% the bundled KB and the user overlay instead of redefining the predicates.
safe_load(D, F) :-
    format(string(P), "~s/~s", [D, F]),
    catch(setup_call_cleanup(open(P, read, S),
                             load_stream(S),
                             close(S)),
          E,
          format(user_error, "kb: failed to load ~s: ~w~n", [P, E])).

load_stream(S) :-
    repeat,
    read_term(S, T, []),
    (   T == end_of_file
    ->  !
    ;   load_term(T),
        fail
    ).

load_term((:- G)) :-
    !,
    catch(ignore(G), _, true).
load_term(T) :-
    catch(assertz(T), _, true).

% ---------------------------------------------------------------- queries

known_problems(Ns) :-
    findall(N, problem(N, _, _), Ns0),
    sort(Ns0, Ns).

known_problem(N) :- known_problems(Ns), member(N, Ns).

problem_count(N) :- known_problems(Ns), length(Ns, N).

problem_info(N, D, Ts) :- last_of(problem(N, D, Ts)).

problem_symptoms(N, Ss) :-
    findall(S, symptom(N, S), Ss0),
    sort(Ss0, Ss).

problem_diags(N, Diags) :-
    findall(O-(T-E), diag(N, O, T, E), L0),
    keysort(L0, L1),
    collapse_last(L1, L2),
    maplist(pair_value, L2, Diags).

problem_fixes(N, Fixes) :-
    findall(O-S, fix(N, O, S), L0),
    keysort(L0, L1),
    collapse_last(L1, L2),
    maplist(pair_value, L2, Fixes).

pair_value(_-V, V).

% For duplicate orders keep the most recently asserted fact (user overlay).
collapse_last([], []).
collapse_last([O-V|Rest], [O-V|Out]) :-
    !, \+ memberchk(O-_, Rest),
    collapse_last(Rest, Out).
collapse_last([_|Rest], Out) :-
    collapse_last(Rest, Out).

last_of(T) :-
    findall(T, T, L),
    L \= [],
    last(L, T).

find_problems(Q, Matches) :-
    string_lower(Q, QL),
    findall(N, (problem(N, _, _), problem_matches(N, QL)), Ms),
    sort(Ms, Matches).

problem_matches(N, QL) :-
    (   atom_string(N, NS), string_lower(NS, NSL), sub_string(NSL, _, _, _, QL)
    ;   problem(N, D, _), string_lower(D, DL), sub_string(DL, _, _, _, QL)
    ;   symptom(N, S), string_lower(S, SL), sub_string(SL, _, _, _, QL)
    ;   problem(N, _, Ts), member(T, Ts), string_lower(T, TL), sub_string(TL, _, _, _, QL)
    ).

% ---------------------------------------------------------------- writing

normalize_name(Raw, Name) :-
    string_lower(Raw, L),
    string_codes(L, Cs),
    maplist(sep_to_us, Cs, Cs2),
    include(valid_code, Cs2, Cs3),
    Cs3 \= [],
    string_codes(S, Cs3),
    atom_string(Name, S).

sep_to_us(C, 0'_) :- member(C, [0' , 0'-, 0'.]), !.
sep_to_us(C, C).

valid_code(C) :- between(0'a, 0'z, C), !.
valid_code(C) :- between(0'0, 0'9, C), !.
valid_code(0'_).

add_problem(Name, Desc, Tags, Symptoms, Diags, Fixes) :-
    user_kb_dir(D),
    make_directory_path(D),
    format(string(P), "~s/problems.pl", [D]),
    (   exists_file(P)
    ->  true
    ;   setup_user_kb(P)
    ),
    open(P, append, F, [encoding(utf8)]),
    format(F, "~n% added ~w~n", [Name]),
    format(F, "problem(~q, ~q, ~q).~n", [Name, Desc, Tags]),
    forall(member(S, Symptoms),
           format(F, "symptom(~q, ~q).~n", [Name, S])),
    forall(nth1(I, Diags, cmd(T, E)),
           format(F, "diag(~q, ~d, ~q, ~q).~n", [Name, I, T, E])),
    forall(nth1(J, Fixes, Step),
           format(F, "fix(~q, ~d, ~q).~n", [Name, J, Step])),
    close(F),
    assertz(problem(Name, Desc, Tags)),
    forall(member(S, Symptoms), assertz(symptom(Name, S))),
    forall(nth1(I, Diags, cmd(T, E)), assertz(diag(Name, I, T, E))),
    forall(nth1(J, Fixes, Step), assertz(fix(Name, J, Step))).

setup_user_kb(P) :-
    open(P, write, F, [encoding(utf8)]),
    format(F, "% arch-expert user knowledge base (managed by `arch-expert add`)~n", []),
    format(F, ":- set_prolog_flag(double_quotes, string).~n", []),
    close(F).

% ---------------------------------------------------------------- sessions

state_dir(S) :-
    (   env_string("ARCH_EXPERT_STATE", U)
    ->  S = U
    ;   home_dir(H),
        format(string(S), "~s/.local/state/arch-expert", [H])
    ).

append_session(Problem, Cmds) :-
    state_dir(S),
    make_directory_path(S),
    format(string(P), "~s/sessions.pl", [S]),
    get_time(T),
    format_time(string(Stamp), "%Y-%m-%dT%H:%M:%S%z", T),
    open(P, append, F, [encoding(utf8)]),
    format(F, "session(~q, ~q, ~q).~n", [Stamp, Problem, Cmds]),
    close(F).
