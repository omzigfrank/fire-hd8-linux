#!/bin/bash
# SPDX-License-Identifier: MIT
# Regenerate kernel/patches/ from a modified kernel tree.
#
#   scripts/gen-patches.sh VANILLA_TREE MODIFIED_TREE
#
# Every changed file goes into exactly one patch, chosen by path (first match wins).
set -euo pipefail
van=$(cd "$1" && pwd); mod=$(cd "$2" && pwd)
outdir=$(cd "$(dirname "$0")/../kernel/patches" && pwd)

# patch-name  path-patterns (extended regex on the file path)
areas=(
	"0001-dt-bindings-and-mt8163-douglas-device-tree|^(arch/arm64/boot/dts/|include/dt-bindings/|Documentation/devicetree/)"
	"0002-arm64-douglas-smp-and-firmware-scanout|^arch/arm64/"
	"0003-drm-sysfb-douglas-backlight-and-zero-copy|^drivers/gpu/drm/"
	"0004-sound-mt8163-afe-mt6323-codec-douglas-card|^(sound/|drivers/mfd/mt6397-core.c)"
	"0005-mt6625l-wifi-bluetooth-gen2-connectivity|^drivers/misc/|^drivers/soc/mediatek/mtk-pmic-wrap.c"
	"0006-mmc-genpd-keep-powered-for-s2idle|^(drivers/mmc/core/|drivers/pmdomain/core.c)"
	"0007-mt8163-soc-drivers|^(drivers/|include/)"
	"0008-misc|."
)

# (diff exits 1 when trees differ, which is the point here)
files=$( { diff -rqN -x '*.orig' -x '*.rej' -x '.git' -x 'include-prefixes' "$van" "$mod" || true; } \
	| sed -E "s|^Files $van/(.*) and .* differ$|\1|" | sort)

rm -f "$outdir"/*.patch
declare -A taken
for entry in "${areas[@]}"; do
	name=${entry%%|*}; re=${entry#*|}
	out="$outdir/$name.patch"
	: > "$out.tmp"
	for f in $files; do
		[ -n "${taken[$f]:-}" ] && continue
		echo "$f" | grep -qE "$re" || continue
		taken[$f]=1
		diff -uN --label "a/$f" --label "b/$f" "$van/$f" "$mod/$f" >> "$out.tmp" || true
	done
	if [ -s "$out.tmp" ]; then
		{ echo "Fire HD 8 (2017, douglas): ${name#*-}"; echo; echo "---"; cat "$out.tmp"; } > "$out"
		echo "$(grep -c '^+++ ' "$out") files  ${out##*/}"
	fi
	rm -f "$out.tmp"
done
