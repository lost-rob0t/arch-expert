% Arch Linux specific playbooks.
:- set_prolog_flag(double_quotes, string).

problem(initramfs_missing, "Boot drops to an emergency shell or panics very early; initramfs missing or stale.", [boot, initramfs, mkinitcpio, arch]).
symptom(initramfs_missing, "'not a valid ELF' or 'no init found' at boot").
symptom(initramfs_missing, "emergency shell after systemd starts").
diag(initramfs_missing, 1, t("ls", [literal("-l"), literal("/mnt/boot")]), "check for initramfs images and kernel versions").
diag(initramfs_missing, 2, t("lsblk", [literal("-f")]), "find where /boot lives").
fix(initramfs_missing, 1, cmd(t("mount", [slot(device, "/dev/nvme0n1p2"), slot(mountpoint, "/mnt")]), "mount the root filesystem")).
fix(initramfs_missing, 2, cmd(t("arch-chroot", [slot(mountpoint, "/mnt")]), "enter the installed system")).
fix(initramfs_missing, 3, cmd(t("mkinitcpio", [literal("-p"), slot(kernel_version, "linux")]), "regenerate initramfs images (inside the chroot)")).
fix(initramfs_missing, 4, prose("If /boot is a separate partition mount it first; verify the kernel package is installed: pacman -Q linux")).

problem(arch_bootloader_grub, "GRUB broken or missing on an Arch system.", [boot, uefi, grub, arch]).
symptom(arch_bootloader_grub, "GRUB rescue prompt or no menu on an Arch install").
diag(arch_bootloader_grub, 1, t("efibootmgr", [literal("-v")]), "check the arch boot entry exists and points at the right ESP").
diag(arch_bootloader_grub, 2, t("ls", [literal("/mnt/boot/grub")]), "check grub files on the mounted system").
fix(arch_bootloader_grub, 1, cmd(t("arch-chroot", [slot(mountpoint, "/mnt")]), "enter the installed system (root and ESP mounted)")).
fix(arch_bootloader_grub, 2, cmd(t("grub-install", [literal("--target=x86_64-efi"), literal("--efi-directory=/boot"), literal("--bootloader-id=arch")]), "reinstall GRUB for UEFI; adjust --efi-directory if your ESP differs")).
fix(arch_bootloader_grub, 3, cmd(t("grub-mkconfig", [literal("-o"), literal("/boot/grub/grub.cfg")]), "regenerate the GRUB menu")).

problem(pacman_db_duplicate, "pacman database has duplicate package-version directories; transactions abort.", [pacman, database, arch]).
symptom(pacman_db_duplicate, "'duplicate database entry' during -Syu").
symptom(pacman_db_duplicate, "pacman -Qq fails with db errors").
diag(pacman_db_duplicate, 1, t("ls", [literal("/mnt/var/lib/pacman/local")]), "look for the same pkg-version appearing twice").
diag(pacman_db_duplicate, 2, t("pacman", [literal("-Qkk"), slot(package, "glibc")]), "verify a suspect package's files (inside the chroot)").
fix(pacman_db_duplicate, 1, prose("Inside the chroot: for each duplicated <pkg>-<version> directory in /var/lib/pacman/local keep the newest and remove the stale one, then pacman -Syyu.")).
fix(pacman_db_duplicate, 2, cmd(t("pacman", [literal("-Syyu")]), "resync databases after repair")).

problem(keyring_unknown_sig, "pacman refuses packages signed with unknown keys.", [pacman, keys, signature, arch]).
symptom(keyring_unknown_sig, "'error: signature from ... is unknown trust'").
diag(keyring_unknown_sig, 1, t("pacman", [literal("-Q"), slot(package, "archlinux-keyring")]), "check installed keyring version").
diag(keyring_unknown_sig, 2, t("date", []), "wrong clock invalidates signatures").
fix(keyring_unknown_sig, 1, cmd(t("timedatectl", [literal("set-ntp"), literal("true")]), "sync clock first if the date output was wrong")).
fix(keyring_unknown_sig, 2, cmd(t("pacman", [literal("-Sy"), slot(package, "archlinux-keyring")]), "refresh the keyring package")).
fix(keyring_unknown_sig, 3, cmd(t("pacman-key", [literal("--refresh-keys")]), "refresh signing keys (slow; only if step 2 was not enough)")).
