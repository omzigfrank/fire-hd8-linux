#!/bin/bash
# SPDX-License-Identifier: MIT
# Build the Fire HD 8 kernel and boot image: out/boot.img
#
# Host (Debian/Ubuntu): build-essential bc bison flex libssl-dev libelf-dev cpio python3
#                       gcc-aarch64-linux-gnu curl xz-utils, plus qemu-user-static for the
#                       initramfs busybox (fetched from Alpine through the build chroot).
# Run as root (the chroot step needs it):  sudo kernel/build.sh
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "$here/../config.sh"
V=$KERNEL_VERSION
SRC=$WORK/linux-$V
KOUT=$WORK/kernel-out
CROSS=${CROSS_COMPILE:-aarch64-linux-gnu-}
mkdir -p "$WORK/cache" "$OUT"

# 1. Linux source, verified against kernel.org's checksum list
tarball=linux-$V.tar.xz
if [ ! -f "$WORK/cache/$tarball" ]; then
	curl -fL -o "$WORK/cache/$tarball" "https://cdn.kernel.org/pub/linux/kernel/v${V%%.*}.x/$tarball"
	curl -fL -o "$WORK/cache/sha256sums.asc" "https://cdn.kernel.org/pub/linux/kernel/v${V%%.*}.x/sha256sums.asc"
fi
(cd "$WORK/cache" && grep " $tarball\$" sha256sums.asc | sha256sum -c -)

# 2. Fresh tree + patches (re-extracted every time so patches always apply to pristine code)
rm -rf "$SRC"
tar -xJf "$WORK/cache/$tarball" -C "$WORK"
for p in "$here"/patches/*.patch; do
	echo "applying ${p##*/}"
	patch -d "$SRC" -p1 --quiet --forward < "$p"
done

# 3. Configure and build
mkdir -p "$KOUT"
cp "$here/config/douglas_defconfig" "$SRC/arch/arm64/configs/douglas_defconfig"
make -C "$SRC" O="$KOUT" ARCH=arm64 CROSS_COMPILE="$CROSS" douglas_defconfig
make -C "$SRC" O="$KOUT" ARCH=arm64 CROSS_COMPILE="$CROSS" -j"$(nproc)" \
	Image mediatek/mt8163-amazon-douglas.dtb

# 4. Initramfs: static busybox from Alpine + kernel/initramfs/init
IR=$WORK/initramfs
rm -rf "$IR"; mkdir -p "$IR"/{bin,dev,proc,sys,run,tmp,newroot}
"$here/../scripts/alpine-chroot.sh" "$WORK/chroot-build" sh -c \
	'apk add --no-cache busybox-static >/dev/null && cp /bin/busybox.static /tmp/busybox.static'
cp "$WORK/chroot-build/tmp/busybox.static" "$IR/bin/busybox"
install -m755 "$here/initramfs/init" "$IR/init"
(cd "$IR" && find . | sort | cpio --quiet -o -H newc --owner=0:0 | gzip -9n) > "$WORK/initramfs.cpio.gz"

# 5. Boot image
python3 "$here/boot/mkboot.py" --cross "$CROSS" \
	--image "$KOUT/arch/arm64/boot/Image" \
	--dtb "$KOUT/arch/arm64/boot/dts/mediatek/mt8163-amazon-douglas.dtb" \
	--initramfs "$WORK/initramfs.cpio.gz" \
	--out "$OUT/boot.img"
(cd "$OUT" && sha256sum boot.img > boot.img.sha256)
