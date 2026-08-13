#!/usr/bin/env bash
# =============================================================================
# SCROW — one-line bootstrap
# =============================================================================
# Downloads the SCROW repository and launches the installer. Uses curl + tar,
# so it works on a bare system that has no git yet (git is only needed later,
# and the installer installs it as part of the Utilities component).
#
#   curl -fsSL https://raw.githubusercontent.com/midn8crow/scrow/main/bootstrap.sh | bash
#
# Environment overrides:
#   SCROW_BOOT_DIR     where the repository is fetched (default:
#                      ~/.local/share/scrow/bootstrap)
#   SCROW_BOOT_BRANCH  branch to fetch (default: main)
# =============================================================================

set -uo pipefail

SCROW_BOOT_DIR="${SCROW_BOOT_DIR:-$HOME/.local/share/scrow/bootstrap}"
SCROW_BOOT_BRANCH="${SCROW_BOOT_BRANCH:-main}"
SCROW_REPO_URL="${SCROW_REPO_URL:-https://github.com/midn8crow/scrow.git}"

printf 'SCROW — Arch Linux • Hyprland\n'
printf 'Fetching SCROW installer…\n'

mkdir -p "$(dirname "$SCROW_BOOT_DIR")"

# Always start from a clean copy — never trust a stale/partial previous
# download (that is what previously caused phantom "check your connection"
# failures and broken re-installs).
rm -rf "$SCROW_BOOT_DIR"
mkdir -p "$SCROW_BOOT_DIR"

got_repo=0
if command -v git >/dev/null 2>&1; then
    if git clone --depth 1 --branch "$SCROW_BOOT_BRANCH" "$SCROW_REPO_URL" "$SCROW_BOOT_DIR"; then
        got_repo=1
    else
        rm -rf "$SCROW_BOOT_DIR"
        mkdir -p "$SCROW_BOOT_DIR"
    fi
fi

if (( ! got_repo )); then
    # No git installed (or the git clone failed): fall back to a plain
    # tarball download, which only needs curl + tar.
    if ! curl -fsSL --connect-timeout 8 \
        "https://github.com/midn8crow/scrow/archive/refs/heads/$SCROW_BOOT_BRANCH.tar.gz" \
        | tar -xz --strip-components=1 -C "$SCROW_BOOT_DIR"; then
        printf 'SCROW: could not download the installer. Check your connection.\n' >&2
        exit 1
    fi
fi

ver="$(cat "$SCROW_BOOT_DIR/VERSION" 2>/dev/null | tr -d '[:space:]')"
if (( got_repo )) && [[ -n "$ver" ]] \
    && git -C "$SCROW_BOOT_DIR" rev-parse -q --verify "refs/tags/v$ver" >/dev/null 2>&1; then
    git -C "$SCROW_BOOT_DIR" checkout --quiet "v$ver" 2>/dev/null || true
    printf 'Using verified release v%s\n' "$ver"
else
    printf 'Using branch %s\n' "$SCROW_BOOT_BRANCH"
fi

printf 'Starting the SCROW Installer…\n\n'
exec bash "$SCROW_BOOT_DIR/install.sh" "$@"
