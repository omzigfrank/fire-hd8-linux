#!/bin/bash
# SPDX-License-Identifier: MIT
# Install Fire HD 8 Linux on an unlocked Fire HD 8 (2017, "douglas") from a PC.
#
#   tools/install.sh boot.img rootfs.img.gz
#
# Requirements: the tablet is unlocked with amonet and booted into TWRP (recovery_x), and
# connected over USB with `adb devices` showing it in "recovery" state. Works on Linux and
# macOS, and on Windows from Git Bash or WSL with adb installed.
#
# What it does:
#   1. checks it is talking to a Fire HD 8 (douglas) in TWRP and finds the partitions
#   2. backs up to ./douglas-backup-<date>/ on the PC: Fire OS's /data/nvram (Wi-Fi
#      calibration and MAC address) and the current boot_x; also leaves the NVRAM backup on
#      the tablet's cache partition, where Linux picks it up at first boot
#   3. after you type YES: writes the root filesystem to userdata (ERASES all Fire OS user
#      data and apps) and the kernel to boot_x, verifies both, and reboots
# The Fire OS system partition is not touched; Linux reads the Wi-Fi firmware from it.
set -euo pipefail
boot=${1:-}; rootfs=${2:-}
[ -f "$boot" ] && [ -f "$rootfs" ] || { sed -n '2,20p' "$0"; exit 2; }
command -v adb >/dev/null || { echo "adb not found (install Android platform-tools)" >&2; exit 1; }

say() { printf '\n== %s\n' "$*"; }
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }
# adb shell must not read our stdin (it would swallow the YES answer), and older adbd does not
# return the remote exit status, so tests print yes/no instead.
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*'   # Git Bash: keep /cache etc. as tablet paths
ash() { adb shell "$@" </dev/null | tr -d '\r'; }
has() { [ "$(ash "if $1; then echo yes; else echo no; fi")" = yes ]; }

say "Checking the tablet"
[ "$(adb get-state 2>/dev/null | tr -d '\r')" = recovery ] || die "no tablet in recovery (TWRP) mode; boot TWRP and run 'adb devices'"
dev=$(ash getprop ro.product.device)
case "$dev" in *douglas*) ;; *) die "this is '$dev', not a Fire HD 8 2017 (douglas)" ;; esac
bn=$(ash 'for d in /dev/block/platform/*/by-name /dev/block/platform/*/*/by-name /dev/block/by-name; do [ -e $d/boot_x ] && echo $d && break; done')
[ -n "$bn" ] || die "boot_x partition not found - is the tablet unlocked with amonet?"
for p in boot_x userdata cache system; do
	has "[ -e $bn/$p ]" || die "partition $p not found in $bn"
done
echo "device: $dev, partitions: $bn"

udsize=$(ash "blockdev --getsize64 \$(readlink -f $bn/userdata)")
bxsize=$(ash "blockdev --getsize64 \$(readlink -f $bn/boot_x)")
bootsize=$(wc -c < "$boot" | tr -d ' ')
rootsize=$(gzip -l "$rootfs" | awk 'NR==2 { print $2 }')
if [ "$rootsize" = 0 ] || [ "$rootsize" -lt 1000000 ]; then
	rootsize=$(gzip -dc "$rootfs" | wc -c | tr -d ' ')   # gzip -l wraps above 4 GiB
fi
[ "$bootsize" -le "$bxsize" ] || die "boot.img ($bootsize) is larger than boot_x ($bxsize)"
[ "$rootsize" -le "$udsize" ] || die "root filesystem ($rootsize) is larger than userdata ($udsize)"
[ "$(head -c 8 "$boot")" = "ANDROID!" ] || die "$boot is not a boot image"

backup="douglas-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$backup"
say "Backing up to ./$backup"
ash "mount /cache 2>/dev/null; mount /data 2>/dev/null; true"
if has "[ -d /data/nvram ]"; then
	ash "tar czf /cache/douglas-nvram.tgz -C /data nvram || rm -f /cache/douglas-nvram.tgz; sync"
	has "[ -s /cache/douglas-nvram.tgz ]" || die "could not back up /data/nvram"
	adb pull /cache/douglas-nvram.tgz "$backup/douglas-nvram.tgz"
	echo "saved Wi-Fi calibration (NVRAM) to the PC and the cache partition"
elif has "[ -s /cache/douglas-nvram.tgz ] && tar tzf /cache/douglas-nvram.tgz | grep -q WIFI"; then
	adb pull /cache/douglas-nvram.tgz "$backup/douglas-nvram.tgz"
	echo "reusing the NVRAM backup already on the cache partition"
else
	echo "WARNING: no /data/nvram and no earlier backup: Wi-Fi may not work after installing."
	echo "         If you have a douglas-nvram.tgz from an earlier install, push it first:"
	echo "         adb push douglas-nvram.tgz /cache/"
fi
adb pull "$bn/boot_x" "$backup/boot_x.img"

say "Ready to install"
echo "This ERASES the userdata partition (all Fire OS apps, accounts, photos and files)"
echo "and replaces the kernel on boot_x. The Fire OS system partition stays untouched."
read -r -p "Type YES to continue: " ok || ok=
[ "$ok" = YES ] || die "cancelled"

ash "umount /data 2>/dev/null; umount /sdcard 2>/dev/null; true"
say "Writing the root filesystem ($((rootsize / 1048576)) MiB) - this takes a few minutes"
gzip -dc "$rootfs" | adb exec-in "dd of=$bn/userdata bs=4194304"
say "Verifying"
want=$(gzip -dc "$rootfs" | sha256sum | cut -d' ' -f1)
have=$(ash "head -c $rootsize $bn/userdata | sha256sum" | cut -d' ' -f1)
[ "$want" = "$have" ] || die "root filesystem verification failed (the tablet still boots TWRP; try again)"

say "Writing the kernel"
adb exec-in "dd of=$bn/boot_x bs=1048576" < "$boot"
want=$(sha256sum < "$boot" | cut -d' ' -f1)
have=$(ash "head -c $bootsize $bn/boot_x | sha256sum" | cut -d' ' -f1)
[ "$want" = "$have" ] || die "kernel verification failed; restore with: adb exec-in \"dd of=$bn/boot_x\" < $backup/boot_x.img"

say "Done - restarting into Fire HD 8 Linux"
echo "First boot takes a little longer (it grows the filesystem and sets up Wi-Fi)."
echo "The screen PIN is 1234 until you choose your own in the welcome dialog."
echo "Keep ./$backup somewhere safe."
adb reboot
