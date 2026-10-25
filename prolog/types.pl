% Slot types for arch-expert command templates.
%
% A typed slot carries both a semantic type (used for validation, prompting
% and system probing) and the example value the author typed when the
% command was recorded.  Tokens that do not match a strong shape stay
% literal, so replaying a stored command never invents structure.

:- module(types, [
    known_type/1,
    infer_part/4,     % +Cmd, +PrevTok, +Tok, -Part
    validate/2,       % +Type, +Value  (semidet)
    type_prompt/2
]).
:- set_prolog_flag(double_quotes, string).

known_type(T) :-
    member(T, [device, mountpoint, path, service, package,
               kernel_version, uuid, user, number, owner]).

% ---------------------------------------------------------------- inference

infer_part(Cmd, Prev, Tok, slot(Type, Tok)) :-
    context_type(Cmd, Prev, Tok, Type), !.
infer_part(_, _, Tok, slot(Type, Tok)) :-
    shape_type(Tok, Type), !.
infer_part(_, _, Tok, literal(Tok)).

flag(T) :-
    sub_string(T, 0, 1, _, "-"),
    string_length(T, L),
    L > 1.

unit_flag("-u").
unit_flag("--unit").
unit_flag(F) :- sub_string(F, 0, _, _, "--unit=").

pacman_op(O) :-
    member(O, ["-S", "-Sy", "-Q", "-R", "-Rs", "-Rns", "-Rsn", "-Qs", "-Qi",
               "-Ql", "-Qo", "-Qkk", "-Qk", "-Si", "-Ss", "-Sw", "-U", "-D"]).

% Cross-distro package managers: subcommand decides the operand type.
pkg_manager_op("apt", S) :- member(S, ["install", "remove", "purge", "reinstall", "show", "policy"]).
pkg_manager_op("apt-get", S) :- member(S, ["install", "remove", "purge", "reinstall"]).
pkg_manager_op("dnf", S) :- member(S, ["install", "remove", "reinstall", "info", "downgrade"]).
pkg_manager_op("zypper", S) :- member(S, ["install", "remove", "info"]).
pkg_manager_op("apk", S) :- member(S, ["add", "del", "fix", "info"]).
pkg_manager_op("nix-env", "-iA").

serviceish(T) :- re_match("^[A-Za-z0-9_@:.\\-]+$", T), \+ flag(T).
packagish(T) :- re_match("^[A-Za-z0-9@._+-]+$", T), \+ flag(T).

% Context rules: the previous token (subcommand or flag) decides.
context_type("journalctl", Prev, Tok, service) :-
    unit_flag(Prev), serviceish(Tok), !.
context_type("systemctl", Prev, Tok, service) :-
    unit_flag(Prev), serviceish(Tok), !.
context_type("systemctl", Sub, Tok, service) :-
    member(Sub, ["status", "restart", "start", "stop", "enable", "disable",
                 "mask", "unmask", "cat", "edit"]),
    serviceish(Tok), !.
context_type("pacman", Prev, Tok, package) :-
    pacman_op(Prev), packagish(Tok), !.
context_type(Cmd, Sub, Tok, package) :-
    pkg_manager_op(Cmd, Sub),
    packagish(Tok), !.
context_type("rc-service", Sub, Tok, service) :-
    member(Sub, ["start", "stop", "restart", "status", "add", "del"]),
    serviceish(Tok), !.
context_type("mkinitcpio", "-p", Tok, kernel_version) :-
    packagish(Tok), !.
context_type("chown", _, Tok, owner) :-
    \+ flag(Tok),
    sub_string(Tok, B, _, A, ":"),
    B > 0, A > 0.
context_type("su", _, Tok, user) :-
    \+ flag(Tok).

% Shape rules: what the token itself looks like.
shape_type(T, device) :- sub_string(T, 0, _, _, "/dev/"), !.
shape_type(T, uuid) :- sub_string(T, 0, _, _, "UUID="), !.
shape_type(T, uuid) :-
    re_match("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", T), !.
shape_type(T, mountpoint) :- mount_root(T), !.
shape_type(T, kernel_version) :- re_match("^linux[a-z0-9.-]*$", T), !.
shape_type(T, kernel_version) :-
    re_match("^[0-9]+\\.[0-9]+(\\.[0-9]+)?", T), !.
shape_type(T, number) :- re_match("^[0-9]+$", T), !.
shape_type(T, path) :- sub_string(T, 0, 1, _, "/"), !.

mount_root("/").
mount_root(T) :-
    member(P, ["/mnt", "/boot", "/media", "/run/mount", "/srv", "/data", "/efi"]),
    sub_string(T, 0, _, _, P).

% ---------------------------------------------------------------- validation

validate(device, V) :- !, sub_string(V, 0, _, _, "/dev/").
validate(uuid, V) :- !,
    ( sub_string(V, 0, _, _, "UUID=")
    ; re_match("^[0-9a-fA-F-]{36}$", V) ).
validate(mountpoint, V) :- !, sub_string(V, 0, 1, _, "/").
validate(path, V) :- !, sub_string(V, 0, 1, _, "/").
validate(service, V) :- !, serviceish(V).
validate(package, V) :- !, packagish(V).
validate(kernel_version, V) :- !,
    ( re_match("^linux[a-z0-9.-]*$", V)
    ; re_match("^[0-9][0-9.]*", V) ).
validate(user, V) :- !, re_match("^[a-z_][a-z0-9_-]*$", V).
validate(owner, V) :- !,
    sub_string(V, B, _, A, ":"), B > 0, A > 0.
validate(number, V) :- !, re_match("^[0-9]+$", V).

% ---------------------------------------------------------------- prompting

type_prompt(device, "device path (see: lsblk)").
type_prompt(mountpoint, "mountpoint (e.g. /mnt)").
type_prompt(path, "absolute file path").
type_prompt(service, "systemd unit (e.g. sshd.service)").
type_prompt(package, "package name (e.g. glibc)").
type_prompt(kernel_version, "kernel package (e.g. linux, linux-lts)").
type_prompt(uuid, "filesystem UUID").
type_prompt(user, "user name").
type_prompt(owner, "owner as user:group").
type_prompt(number, "number").
