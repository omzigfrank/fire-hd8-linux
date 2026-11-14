#!/bin/bash
# SPDX-License-Identifier: MIT
# Build the signed over-the-air packages (douglas-base, douglas-kernel) into
#   out/repo/alpine/v3.24/douglas/aarch64/   (APKINDEX.tar.gz + *.apk)
# Needs out/boot.img from kernel/build.sh. Run as root: sudo packaging/build.sh
#
# The first run creates the repository signing key in $KEY_DIR (see config.sh). Back it up:
# tablets only accept updates signed with the key whose public half they already have.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "$here/../config.sh"
CH=$WORK/chroot-build
[ -f "$OUT/boot.img" ] || { echo "out/boot.img missing: run kernel/build.sh first" >&2; exit 1; }

# signing key (private key stays outside the repository)
mkdir -p "$KEY_DIR"; chmod 700 "$KEY_DIR"
if [ ! -f "$KEY_DIR/douglas-repo.rsa" ]; then
	openssl genrsa -out "$KEY_DIR/douglas-repo.rsa" 4096
	chmod 600 "$KEY_DIR/douglas-repo.rsa"
	echo "created a new signing key in $KEY_DIR - back it up"
fi
openssl rsa -in "$KEY_DIR/douglas-repo.rsa" -pubout -out "$here/douglas-base/douglas-repo.rsa.pub" 2>/dev/null
[ -n "${SUDO_USER:-}" ] && chown -R "$SUDO_USER" "$KEY_DIR"
echo "$UPDATE_REPO_URL" > "$here/douglas-base/repository-url"

# stage the package sources in the chroot
rm -rf "$CH/build"
mkdir -p "$CH/build/douglas" "$CH/build/keys"
cp -r "$here/douglas-base" "$here/douglas-kernel" "$CH/build/douglas/"
cp "$OUT/boot.img" "$CH/build/douglas/douglas-kernel/boot.img"
sed -i "s|https://github.com/OWNER/REPO|https://github.com/$GITHUB_REPO|" "$CH"/build/douglas/*/APKBUILD
cp "$KEY_DIR/douglas-repo.rsa" "$CH/build/keys/"
cp "$here/douglas-base/douglas-repo.rsa.pub" "$CH/build/keys/"

"$here/../scripts/alpine-chroot.sh" "$CH" sh -euc '
	apk update >/dev/null
	apk add alpine-sdk >/dev/null
	cp /build/keys/douglas-repo.rsa.pub /etc/apk/keys/
	export PACKAGER="Fire HD 8 Linux builder <noreply@localhost>"
	export PACKAGER_PRIVKEY=/build/keys/douglas-repo.rsa
	export REPODEST=/build/packages
	for p in douglas-base douglas-kernel; do
		cd /build/douglas/$p
		abuild -F checksum
		abuild -F -r
	done
	rm -f /build/keys/douglas-repo.rsa
'

dest=$OUT/repo/alpine/$ALPINE_BRANCH/douglas/aarch64
mkdir -p "$dest"
cp "$CH"/build/packages/douglas/aarch64/*.apk "$dest/"
cp "$CH"/build/packages/douglas/aarch64/APKINDEX.tar.gz "$dest/"
rm -rf "$CH/build"
ls -l "$dest"
