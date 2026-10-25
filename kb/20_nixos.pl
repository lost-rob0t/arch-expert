% NixOS specific playbooks.
:- set_prolog_flag(double_quotes, string).

problem(nixos_broken_generation, "Latest NixOS generation is broken; boot into the previous one and roll back.", [boot, generations, nixos]).
symptom(nixos_broken_generation, "system fails to boot after nixos-rebuild switch").
symptom(nixos_broken_generation, "new boot shows the problem, older boot menu entries work").
diag(nixos_broken_generation, 1, t("ls", [literal("-l"), literal("/nix/var/nix/profiles")]), "list system generations and their links").
diag(nixos_broken_generation, 2, t("nix-env", [literal("--list-generations"), literal("-p"), literal("/nix/var/nix/profiles/system")]), "generation numbers and dates (on the mounted system)").
fix(nixos_broken_generation, 1, prose("Reboot and pick the previous generation in the GRUB 'NixOS - Profile' submenu; then from the running old system: nixos-rebuild switch --rollback.")).
fix(nixos_broken_generation, 2, cmd(t("nixos-enter", [literal("--root"), slot(mountpoint, "/mnt")]), "enter the mounted system from rescue media")).
fix(nixos_broken_generation, 3, cmd(t("nixos-rebuild", [literal("boot"), literal("--rollback")]), "point the bootloader back at the last good generation (inside the target)")).
fix(nixos_broken_generation, 4, cmd(t("nixos-rebuild", [literal("build-vm")]), "test the fixed configuration in a VM before switching (once bootable)")).

problem(nixos_bootloader_broken, "NixOS bootloader entries missing or EFI reset; reinstall from rescue media.", [boot, uefi, bootloader, nixos]).
symptom(nixos_bootloader_broken, "no NixOS entry in the firmware boot menu").
symptom(nixos_bootloader_broken, "systemd-boot or GRUB prompt instead of the NixOS menu").
diag(nixos_bootloader_broken, 1, t("efibootmgr", [literal("-v")]), "check whether a NixOS boot entry exists").
diag(nixos_bootloader_broken, 2, t("lsblk", [literal("-f")]), "identify the ESP and the root partition").
diag(nixos_bootloader_broken, 3, t("mount", [slot(device, "/dev/nvme0n1p1"), literal("/mnt/boot")]), "mount the ESP before reinstalling (root must already be at /mnt)").
fix(nixos_bootloader_broken, 1, cmd(t("nixos-enter", [literal("--root"), slot(mountpoint, "/mnt")]), "enter the installed system with ESP mounted")).
fix(nixos_bootloader_broken, 2, cmd(t("nixos-rebuild", [literal("boot"), literal("--install-bootloader")]), "rebuild the boot entry and reinstall the bootloader")).
fix(nixos_bootloader_broken, 3, prose("If the system is unbootable for other reasons too, mount root and ESP, then run: nixos-install --root /mnt --no-root-passwd --flake <flake#host> to repair in place.")).

problem(nix_store_corrupt, "nix store paths damaged (disk errors, interrupted writes); rebuilds or boots fail with hash mismatches.", [nix, store, nixos]).
symptom(nix_store_corrupt, "hash mismatch / corrupted path errors from nix").
symptom(nix_store_corrupt, "systemd fails to start units pointing at missing store paths").
diag(nix_store_corrupt, 1, t("journalctl", [literal("-xb"), literal("-p"), literal("3"), literal("--no-pager")]), "find which store paths fail").
diag(nix_store_corrupt, 2, t("nix-store", [literal("--verify"), literal("--check-contents")]), "verify store integrity on the mounted system (slow)").
fix(nix_store_corrupt, 1, cmd(t("nix-store", [literal("--verify"), literal("--check-contents"), literal("--repair")]), "repair what can be re-downloaded (needs network)")).
fix(nix_store_corrupt, 2, cmd(t("nix-store", [literal("-q"), literal("--requisites"), literal("/run/current-system")]), "walk the closure and spot missing paths")).
fix(nix_store_corrupt, 3, prose("Boot the previous generation from the GRUB submenu while repairs run; the old closure is usually intact.")).
