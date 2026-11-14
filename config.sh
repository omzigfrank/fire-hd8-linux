# Build settings for Fire HD 8 Linux. Sourced by the build scripts.

# GitHub repository that hosts the releases and the update repository (GitHub Pages).
GITHUB_REPO="${GITHUB_REPO:-omzigfrank/fire-hd8-linux}"

# Over-the-air update repository that tablets add to /etc/apk/repositories.
# Published to the gh-pages branch by packaging/publish.sh.
UPDATE_REPO_URL="${UPDATE_REPO_URL:-https://${GITHUB_REPO%%/*}.github.io/${GITHUB_REPO#*/}/alpine/v3.24/douglas}"

ALPINE_BRANCH=v3.24
ALPINE_RELEASE=3.24.4
ALPINE_MIRROR="${ALPINE_MIRROR:-https://dl-cdn.alpinelinux.org/alpine}"

KERNEL_VERSION=7.3.4

# Where builds happen (needs ~15 GB) and where results go.
WORK="${WORK:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/build}"
OUT="${OUT:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/out}"

# abuild signing key for the update repository. KEEP THE PRIVATE KEY SAFE AND BACKED UP:
# without it you cannot publish updates that existing tablets will accept.
KEY_DIR="${KEY_DIR:-$HOME/.config/fire-hd8-linux/keys}"
