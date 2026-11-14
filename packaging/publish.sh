#!/bin/bash
# SPDX-License-Identifier: MIT
# Publish a release:
#   * the signed update repository (out/repo) to the gh-pages branch -> GitHub Pages, which
#     every installed tablet checks for updates (Discover shows them, douglas-kernel flashes)
#   * boot.img, rootfs.img.gz, checksums and the installer as a GitHub Release (with --release)
#
#   packaging/publish.sh            update repository only (an OTA update)
#   packaging/publish.sh --release  also create the GitHub Release vVERSION for new installs
#
# Needs: git, gh (logged in with `gh auth login`), and GITHUB_REPO set in config.sh.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
top=$(cd "$here/.." && pwd)
. "$top/config.sh"
[ -n "$GITHUB_REPO" ] || { echo "set GITHUB_REPO in config.sh" >&2; exit 1; }
[ -f "$OUT/repo/alpine/$ALPINE_BRANCH/douglas/aarch64/APKINDEX.tar.gz" ] || { echo "run packaging/build.sh first" >&2; exit 1; }

# --- update repository on gh-pages ---------------------------------------------------------
pages=$(mktemp -d)
trap 'rm -rf "$pages"' EXIT
if git -C "$top" ls-remote --exit-code --heads "https://github.com/$GITHUB_REPO.git" gh-pages >/dev/null 2>&1; then
	git clone --quiet --depth 1 --branch gh-pages "https://github.com/$GITHUB_REPO.git" "$pages"
else
	git -C "$pages" init --quiet -b gh-pages
	git -C "$pages" remote add origin "https://github.com/$GITHUB_REPO.git"
fi
dest=$pages/alpine/$ALPINE_BRANCH/douglas/aarch64
mkdir -p "$dest"
# keep only what the new index lists (old package files would just waste space)
rm -f "$dest"/*.apk
cp "$OUT/repo/alpine/$ALPINE_BRANCH/douglas/aarch64/"* "$dest/"
touch "$pages/.nojekyll"
cat > "$pages/index.html" <<EOF
<!doctype html><meta charset="utf-8"><title>Fire HD 8 Linux updates</title>
<p>This is the over-the-air update repository for
<a href="https://github.com/$GITHUB_REPO">Fire HD 8 Linux</a>.
Tablets use <code>$UPDATE_REPO_URL</code>.</p>
EOF
git -C "$pages" add -A
if git -C "$pages" diff --cached --quiet; then
	echo "update repository unchanged"
else
	git -C "$pages" -c user.name="Fire HD 8 Linux release" -c user.email="noreply@github.com" \
		commit --quiet -m "Update repository: $(cd "$dest" && ls *.apk | tr '\n' ' ')"
	git -C "$pages" push --quiet origin gh-pages
	echo "update repository published: $UPDATE_REPO_URL"
fi
gh api -X POST "repos/$GITHUB_REPO/pages" -f "source[branch]=gh-pages" -f "source[path]=/" >/dev/null 2>&1 || true

# --- GitHub Release ------------------------------------------------------------------------
if [ "${1:-}" = --release ]; then
	ver=$(sed -n 's/^pkgver=//p' "$here/douglas-base/APKBUILD")-k$KERNEL_VERSION
	for f in boot.img rootfs.img.gz; do [ -f "$OUT/$f" ] || { echo "missing out/$f" >&2; exit 1; }; done
	(cd "$OUT" && sha256sum boot.img rootfs.img.gz > SHA256SUMS)
	cp "$top/tools/install.sh" "$OUT/install.sh"
	sed "s|OWNER/REPO|$GITHUB_REPO|g" "$top/docs/RELEASE_NOTES.md" > "$OUT/RELEASE_NOTES.md"
	gh release create "v$ver" --repo "$GITHUB_REPO" --title "Fire HD 8 Linux $ver" \
		--notes-file "$OUT/RELEASE_NOTES.md" \
		"$OUT/boot.img" "$OUT/rootfs.img.gz" "$OUT/SHA256SUMS" "$OUT/install.sh"
fi
