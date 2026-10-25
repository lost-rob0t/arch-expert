% Bundled arch-expert knowledge base, distro-neutral core.
% Distro-specific playbooks live in 10_arch.pl and 20_nixos.pl.
% User problems recorded with `arch-expert add` overlay everything here.
:- set_prolog_flag(double_quotes, string).

% ---------------------------------------------------------------- boot

problem(system_wont_boot, "System fails to boot; inspect the installed system from rescue media.", [boot, recovery, chroot]).
symptom(system_wont_boot, "hangs or resets after firmware").
symptom(system_wont_boot, "no bootloader menu; straight to firmware").
symptom(system_wont_boot, "bootloop").
diag(system_wont_boot, 1, t("lsblk", [literal("-f")]), "identify the root (and ESP) partition, its filesystem and existing mounts").
diag(system_wont_boot, 2, t("blkid", []), "confirm UUIDs that /etc/fstab expects").
diag(system_wont_boot, 3, t("efibootmgr", [literal("-v")]), "list UEFI boot entries and their disk/partition targets").
fix(system_wont_boot, 1, cmd(t("mount", [slot(device, "/dev/nvme0n1p2"), slot(mountpoint, "/mnt")]), "mount the root filesystem")).
fix(system_wont_boot, 2, cmd(t("mount", [slot(device, "/dev/nvme0n1p1"), literal("/mnt/boot")]), "mount the ESP under the root (UEFI systems) if you will reinstall a bootloader")).
fix(system_wont_boot, 3, cmd(t("arch-chroot", [slot(mountpoint, "/mnt")]), "enter the installed system (Arch; on other distros see the prose note)")).
fix(system_wont_boot, 4, prose("Chroot variants: Arch -> arch-chroot /mnt; NixOS -> nixos-enter --root /mnt; others: mount --rbind /dev /proc /sys into /mnt and chroot /mnt. Then inspect the previous boot: journalctl -b -1 -p 3, check /boot and the bootloader.")).

problem(fstab_mount_fail, "Boot hangs waiting for a filesystem; fstab entry wrong or device gone.", [boot, fstab, mount]).
symptom(fstab_mount_fail, "'dependency failed for /path' during boot").
symptom(fstab_mount_fail, "systemd times out waiting for a device").
diag(fstab_mount_fail, 1, t("findmnt", [literal("--verify")]), "check fstab consistency (from inside the mounted system)").
diag(fstab_mount_fail, 2, t("blkid", []), "compare real device UUIDs with fstab entries").
diag(fstab_mount_fail, 3, t("systemctl", [literal("list-units"), literal("--state=failed")]), "see which mount units failed").
fix(fstab_mount_fail, 1, cmd(t("mount", [slot(device, "/dev/sda2"), slot(mountpoint, "/mnt")]), "mount the system to edit fstab")).
fix(fstab_mount_fail, 2, prose("Fix or remove the wrong entry in /mnt/etc/fstab (use the blkid output), then reboot.")).

problem(bootloader_missing, "UEFI firmware finds no boot entry; bootloader missing or overwritten.", [boot, uefi, bootloader]).
symptom(bootloader_missing, "boots straight into firmware setup or another OS").
symptom(bootloader_missing, "boot entry points at a stale disk").
diag(bootloader_missing, 1, t("efibootmgr", [literal("-v")]), "list UEFI boot entries and their disk/partition targets").
diag(bootloader_missing, 2, t("ls", [literal("/mnt/boot")]), "check kernel and bootloader files exist on the mounted system").
diag(bootloader_missing, 3, t("ls", [literal("/mnt/boot/EFI")]), "look for existing EFI bootloaders (grub, systemd, limine...)").
fix(bootloader_missing, 1, prose("Reinstall the bootloader from inside the target's chroot; the exact command is distro-specific (see the arch and nixos playbooks) and depends on which bootloader /boot contains.")).
fix(bootloader_missing, 2, prose("No OS at all on the disk: boot any live media and reinstall/reconfigure the bootloader from there.")).

% ---------------------------------------------------------------- services

problem(failed_service, "One or more systemd units are in a failed state.", [systemd, services]).
symptom(failed_service, "red 'FAILED' at boot or 'systemctl --failed' output").
diag(failed_service, 1, t("systemctl", [literal("--failed")]), "list failed units").
diag(failed_service, 2, t("journalctl", [literal("-u"), slot(service, "sshd.service"), literal("-b"), literal("--no-pager")]), "read the unit's log for this boot").
diag(failed_service, 3, t("journalctl", [literal("-xb"), literal("-p"), literal("3"), literal("--no-pager")]), "all errors from this boot for context").
fix(failed_service, 1, cmd(t("systemctl", [literal("restart"), slot(service, "sshd.service")]), "restart the failed unit after fixing its root cause")).
fix(failed_service, 2, cmd(t("systemctl", [literal("status"), slot(service, "sshd.service")]), "confirm it came back up")).

% ---------------------------------------------------------------- disk

problem(disk_full, "Root or /boot filesystem is full; writes and updates fail.", [disk, space]).
symptom(disk_full, "'no space left on device'").
symptom(disk_full, "package managers fail to install anything").
diag(disk_full, 1, t("df", [literal("-h")]), "see which mount is full").
diag(disk_full, 2, t("du", [literal("-xh"), literal("/"), literal("--max-depth=2")]), "find the biggest trees (slow; run from the full mount)").
fix(disk_full, 1, cmd(t("journalctl", [literal("--vacuum-size=200M")]), "shrink old journal logs")).
fix(disk_full, 2, prose("Package caches: pacman -Sc / apt clean / dnf clean all — whatever this host uses.")).
fix(disk_full, 3, cmd(t("pacman", [literal("-Rns"), slot(package, "unused-pkg")]), "remove an unused package and its deps (Arch)")).
fix(disk_full, 4, cmd(t("apt", [literal("remove"), slot(package, "unused-pkg")]), "remove an unused package (Debian family)")).

% ---------------------------------------------------------------- network

problem(no_network, "No network after boot; wired or wireless link is down.", [network, wifi]).
symptom(no_network, "no default route / DNS resolution fails").
diag(no_network, 1, t("ip", [literal("link")]), "check interface state (UP/DOWN) and names").
diag(no_network, 2, t("rfkill", [literal("list")]), "check for soft/hard wireless blocks").
diag(no_network, 3, t("dmesg", [literal("--level=err,warn")]), "look for firmware load failures for the NIC").
fix(no_network, 1, cmd(t("dhcpcd", []), "request a lease on the wired link (or: dhclient / NetworkManager nmcli)").
fix(no_network, 2, prose("Wireless via iwd: iwctl, then 'station wlan0 scan' and 'station wlan0 connect <ssid>'; or use nmcli on NetworkManager systems.")).
fix(no_network, 3, prose("Missing firmware usually names the package in dmesg (e.g. linux-firmware); install it once a link is up.")).

% ---------------------------------------------------------------- time

problem(time_skew, "System clock is wrong, breaking TLS and package signatures.", [time, clock]).
symptom(time_skew, "certificates 'not yet valid' / 'expired' in curl or browsers").
symptom(time_skew, "package signature errors despite correct keys").
diag(time_skew, 1, t("timedatectl", []), "compare local time, RTC and NTP sync state").
fix(time_skew, 1, cmd(t("timedatectl", [literal("set-ntp"), literal("true")]), "enable NTP sync")).
fix(time_skew, 2, cmd(t("hwclock", [literal("--systohc")]), "write correct time back to the RTC (after sync, inside the chroot)")).
