#!/bin/bash
# SPDX-License-Identifier: MIT
# Create and enter an Alpine aarch64 chroot on an x86_64 Linux host (via qemu-user binfmt).
# Used to build packages natively and to assemble the root filesystem.
#
#   alpine-chroot.sh DIR [command...]   (as root)
#
# Host needs: qemu-user-static with binfmt registered for aarch64, curl, tar.
set -euo pipefail
. "$(dirname "$0")/../config.sh"

dir=$1; shift
[ "$(id -u)" = 0 ] || { echo "run as root" >&2; exit 1; }

if [ ! -x "$dir/bin/busybox" ]; then
	mkdir -p "$dir" "$WORK/cache"
	tarball="alpine-minirootfs-$ALPINE_RELEASE-aarch64.tar.gz"
	url="$ALPINE_MIRROR/$ALPINE_BRANCH/releases/aarch64/$tarball"
	if [ ! -f "$WORK/cache/$tarball" ]; then
		curl -fL -o "$WORK/cache/$tarball" "$url"
		curl -fL -o "$WORK/cache/$tarball.sha256" "$url.sha256"
	fi
	(cd "$WORK/cache" && sha256sum -c "$tarball.sha256")
	tar -xpf "$WORK/cache/$tarball" -C "$dir"
	printf '%s/%s/main\n%s/%s/community\n' "$ALPINE_MIRROR" "$ALPINE_BRANCH" \
		"$ALPINE_MIRROR" "$ALPINE_BRANCH" > "$dir/etc/apk/repositories"
fi

[ -e /proc/sys/fs/binfmt_misc/status ] || mount -t binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc
if ! grep -qs enabled /proc/sys/fs/binfmt_misc/qemu-aarch64; then
	update-binfmts --enable qemu-aarch64 2>/dev/null || {
		echo "qemu-aarch64 binfmt is not registered (install qemu-user-static / qemu-user-binfmt)" >&2
		exit 1
	}
fi

cp -L /etc/resolv.conf "$dir/etc/resolv.conf"
for m in dev proc sys; do
	if ! mountpoint -q "$dir/$m"; then
		mount --rbind "/$m" "$dir/$m"
		# Without this, unmounting the chroot's copies propagates back and unmounts the
		# host's own /dev, /proc and /sys submounts.
		mount --make-rslave "$dir/$m"
	fi
done
cleanup() { for m in sys proc dev; do umount -lR "$dir/$m" 2>/dev/null || true; done; }
trap cleanup EXIT

if [ $# -gt 0 ]; then
	chroot "$dir" /usr/bin/env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin HOME=/root "$@"
fi
