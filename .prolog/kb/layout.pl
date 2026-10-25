% Repository layout and module responsibilities.
:- set_prolog_flag(double_quotes, string).

module_role("bin/arch-expert", "portable sh launcher; resolves ARCH_EXPERT_HOME for repo/nix/FHS layouts").
module_role("prolog/load.pl", "single loader consulted by launcher and tests").
module_role("prolog/types.pl", "slot type taxonomy: context+shape inference, validation, prompts").
module_role("prolog/template.pl", "raw command line <-> t(Cmd,Parts) <-> filled argv").
module_role("prolog/kb.pl", "bundled+user KB merge, add_problem persistence, sessions").
module_role("prolog/prompt.pl", "interactive prompting; throws prompt_eof on closed stdin").
module_role("prolog/cmdrun.pl", "shell capture (run_capture) and interactive runs; normalizes wait/2 exit").
module_role("prolog/arch_expert.pl", "CLI dispatch, troubleshoot, add wizard, shell, plan/2+json API").
module_role("kb/00_core.pl", "distro-neutral seed playbooks").
module_role("kb/10_arch.pl", "Arch-specific playbooks (pacman, mkinitcpio, grub).").
module_role("kb/20_nixos.pl", "NixOS-specific playbooks (generations, bootloader, store).").
module_role("tests/test_arch_expert.pl", "PlUnit suite; make test").

part("command inference", [context_rules, shape_rules]).
part("context_rules", "previous token (flag/subcommand) decides: journalctl -u, pacman -S, apt install, ...").
part("shape_rules", "token text decides: /dev/* device, UUID=, /mnt* mountpoint, linux* kernel_version, digits number").
