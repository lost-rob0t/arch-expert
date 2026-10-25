:- set_prolog_flag(double_quotes, string).
:- use_module(library(plunit)).
:- ['../prolog/load.pl'].
:- use_module(types).
:- use_module(template).
:- use_module(kb).
:- use_module(cmdrun).

% ------------------------------------------------------- type inference

:- begin_tests(inference).

test(journalctl_unit_slot) :-
    infer_template("journalctl -u sshd.service -b", t("journalctl", P)),
    memberchk(slot(service, "sshd.service"), P),
    memberchk(literal("-u"), P),
    memberchk(literal("-b"), P).

test(systemctl_status_unit) :-
    infer_template("systemctl status nginx", t("systemctl", P)),
    memberchk(slot(service, "nginx"), P).

test(pacman_package_operand) :-
    infer_template("pacman -Qkk glibc", t("pacman", P)),
    memberchk(slot(package, "glibc"), P).

test(mount_paths) :-
    infer_template("mount /dev/sda2 /mnt", t("mount", P)),
    memberchk(slot(device, "/dev/sda2"), P),
    memberchk(slot(mountpoint, "/mnt"), P).

test(mkinitcpio_kernel) :-
    infer_template("mkinitcpio -p linux", t("mkinitcpio", P)),
    memberchk(slot(kernel_version, "linux"), P).

test(device_shape) :-
    infer_template("blkid /dev/sda1", t("blkid", P)),
    memberchk(slot(device, "/dev/sda1"), P).

test(flags_stay_literal) :-
    infer_template("df -h /boot", t("df", P)),
    memberchk(literal("-h"), P),
    memberchk(slot(mountpoint, "/boot"), P).

test(plain_words_stay_literal) :-
    infer_template("ip link", t("ip", P)),
    P = [literal("link")].

test(uuid_shape) :-
    infer_template("mount UUID=123e4567-e89b-12d3-a456-426614174000 /mnt", t("mount", P)),
    memberchk(slot(uuid, "UUID=123e4567-e89b-12d3-a456-426614174000"), P).

test(apt_package_operand) :-
    infer_template("apt install nginx", t("apt", P)),
    memberchk(slot(package, "nginx"), P).

test(dnf_package_operand) :-
    infer_template("dnf reinstall kernel-core", t("dnf", P)),
    memberchk(slot(package, "kernel-core"), P).

test(plan_dict_for_embedding) :-
    arch_expert:plan(failed_service, Steps),
    member(D, Steps),
    get_dict(command, D, C),
    sub_string(C, _, _, _, "journalctl -u {{service}}"),
    get_dict(slots, D, [service]).

:- end_tests(inference).

% ------------------------------------------------------- render and fill

:- begin_tests(templates).

test(render_generic) :-
    infer_template("journalctl -u sshd.service -b", T),
    render_generic(T, S),
    S == "journalctl -u {{service}} -b".

test(render_example) :-
    infer_template("journalctl -u sshd.service -b", T),
    render_example(T, S),
    S == "journalctl -u {{service:sshd.service}} -b".

test(fill_replaces_slots) :-
    T = t("journalctl", [literal("-u"), slot(service, "ssh.service"), literal("-b")]),
    fill(T, ["nginx.service"], Argv),
    join_words(Argv, S),
    S == "journalctl -u nginx.service -b".

test(fill_no_slots) :-
    T = t("lsblk", [literal("-f")]),
    fill(T, [], Argv),
    join_words(Argv, S),
    S == "lsblk -f".

:- end_tests(templates).

% ------------------------------------------------------- validation

:- begin_tests(validation).

test(device_ok)      :- validate(device, "/dev/sda1").
test(device_bad)     :- \+ validate(device, "sda1").
test(service_ok)     :- validate(service, "sshd.service").
test(service_bad)    :- \+ validate(service, "-x").
test(user_ok)        :- validate(user, "root").
test(user_bad)       :- \+ validate(user, "Bad User!").
test(mount_ok)       :- validate(mountpoint, "/mnt").
test(package_ok)     :- validate(package, "archlinux-keyring").
test(kernel_ok)      :- validate(kernel_version, "linux-lts").
test(number_ok)      :- validate(number, "15").
test(number_bad)     :- \+ validate(number, "15x").

:- end_tests(validation).

% ------------------------------------------------------- name + kb

:- begin_tests(kb).

test(normalize_kebab, [true(Name == broken_pacman_db)]) :-
    normalize_name("Broken Pacman-DB", Name).

test(normalize_drops_junk, [true(Name == clean_name_2)]) :-
    normalize_name("CLEAN? NAME!! 2", Name).

test(add_and_read_back) :-
    run_capture("mktemp -d", 0, T),
    split_string(T, "\n", " ", [Tmp|_]),
    setup_call_cleanup(
        setenv("ARCH_EXPERT_KB", Tmp),
        (   add_problem(test_kb_x, "test desc", ["t"], ["s"],
                        [cmd(t("ls", [literal("-l")]), "list files")],
                        [prose("redo it")]),
            user_kb_dir(Tmp),
            format(string(P), "~s/problems.pl", [Tmp]),
            exists_file(P),
            read_file_to_string(P, Content, []),
            sub_string(Content, _, _, _, "problem(test_kb_x, \"test desc\""),
            problem_info(test_kb_x, D, _),
            D == "test desc",
            problem_diags(test_kb_x, [_-_])
        ),
        (   unsetenv("ARCH_EXPERT_KB"),
            format(string(RM), "rm -rf ~s", [Tmp]),
            run_capture(RM, _, _)
        )).

:- end_tests(kb).
