#!/bin/bash
# SPDX-License-Identifier: MIT
# Build the Fire HD 8 Linux root filesystem image: out/rootfs.img.gz
# Needs the update repository from packaging/build.sh. Run as root: sudo rootfs/build.sh
#
# The image is an ext4 filesystem (label douglas-root) just big enough for its contents; it is
# written to the start of the userdata partition and grown to fill it on first boot.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "$here/../config.sh"
R=$WORK/rootfs
REPO=$OUT/repo/alpine/$ALPINE_BRANCH/douglas
[ -f "$REPO/aarch64/APKINDEX.tar.gz" ] || { echo "run packaging/build.sh first" >&2; exit 1; }

# start from scratch - but never delete while anything is still mounted inside
for m in sys proc dev repo var/cache/apk; do umount -lR "$R/$m" 2>/dev/null || true; done
if grep -qs " $R/" /proc/mounts; then echo "something is still mounted under $R" >&2; exit 1; fi
rm -rf "$R"

pkgs=$(sed 's/#.*//' "$here/packages.txt" | tr -s ' \n' ' ')
mkdir -p "$R"
"$here/../scripts/alpine-chroot.sh" "$R" true      # unpack minirootfs
mkdir -p "$R/repo" "$R/var/cache/apk" "$WORK/apk-cache"
mount --bind "$OUT/repo/alpine/$ALPINE_BRANCH/douglas" "$R/repo"
mount --bind "$WORK/apk-cache" "$R/var/cache/apk"     # keep downloads between builds
trap 'umount -l "$R/repo" "$R/var/cache/apk" 2>/dev/null || true' EXIT
cp "$here/../packaging/douglas-base/douglas-repo.rsa.pub" "$R/etc/apk/keys/"
echo /repo >> "$R/etc/apk/repositories"

"$here/../scripts/alpine-chroot.sh" "$R" sh -euc "
	apk update
	apk add $pkgs

	# services
	for s in devfs dmesg udev udev-trigger udev-settle hwdrivers cgroups; do rc-update add \$s sysinit; done
	for s in hostname bootmisc syslog; do rc-update add \$s boot; done
	for s in dbus elogind networkmanager bluetooth alsa iio-sensor-proxy tinydm local; do rc-update add \$s default; done
	for s in mount-ro killprocs savecache; do rc-update add \$s shutdown; done

	# the desktop user: auto-login, screen PIN 1234 until changed in the first-run dialog
	adduser -D -s /bin/sh -G users -g 'Tablet user' user
	for g in wheel video input audio netdev plugdev; do addgroup user \$g; done
	echo 'user:1234' | chpasswd
	passwd -l root
	echo 'permit persist :wheel' > /etc/doas.d/20-wheel.conf
	echo 'TINYDM_USER=user' >> /etc/conf.d/tinydm
	tinydm-set-session -f -s /usr/share/wayland-sessions/plasma-mobile.desktop

	flatpak remote-add --system --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

	echo fire-hd8 > /etc/hostname
	ln -sf /usr/share/zoneinfo/UTC /etc/localtime
	echo 'LABEL=douglas-root / ext4 rw,noatime 0 1' > /etc/fstab
"

# final repository list: Alpine + the online update repository (douglas-base adds it too)
sed -i '\|^/repo$|d' "$R/etc/apk/repositories"
grep -qxF "$UPDATE_REPO_URL" "$R/etc/apk/repositories" || echo "$UPDATE_REPO_URL" >> "$R/etc/apk/repositories"
umount -l "$R/repo"; rmdir "$R/repo"
umount -l "$R/var/cache/apk"

# nothing unit-specific may ship in the image
rm -f "$R/etc/machine-id" "$R"/etc/dropbear/*_host_key* "$R"/etc/ssh/ssh_host_* \
	"$R/etc/resolv.conf" "$R"/root/.ash_history "$R"/var/cache/apk/*
rm -rf "$R"/var/lib/douglas "$R"/tmp/* "$R"/var/log/*
for m in sys proc dev; do umount -lR "$R/$m" 2>/dev/null || true; done

# ext4 image sized to the contents plus 20 % (grown on the tablet at first boot)
used=$(du -s --block-size=1M "$R" | cut -f1)
size=$(( used * 12 / 10 + 256 ))
rm -f "$OUT/rootfs.img"
mkfs.ext4 -q -L douglas-root -O ^metadata_csum_seed -E root_owner=0:0 -d "$R" "$OUT/rootfs.img" "${size}M"
e2fsck -fy "$OUT/rootfs.img" >/dev/null || true
e2fsck -fn "$OUT/rootfs.img"
gzip -9nf "$OUT/rootfs.img"
(cd "$OUT" && sha256sum rootfs.img.gz > rootfs.img.gz.sha256)
ls -l "$OUT/rootfs.img.gz"
