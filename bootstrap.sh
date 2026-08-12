#!/usr/bin/env bash
# =============================================================================
# SCROW — one-line bootstrap
# =============================================================================
# Fetches the SCROW repository, pins to the tagged release matching VERSION
# when available, and launches the installer. Small by design: all real
# logic lives in the version-controlled repository.
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

printf 'SCROW — Arch Linux • Hyprland\n'
printf 'Fetching SCROW installer…\n'

mkdir -p "$(dirname "$SCROW_BOOT_DIR")"

if [[ -d "$SCROW_BOOT_DIR/.git" ]]; then
    printf 'Refreshing local copy…\n'
    git -C "$SCROW_BOOT_DIR" fetch --quiet origin 2>/dev/null || true
    git -C "$SCROW_BOOT_DIR" reset --hard "origin/$SCROW_BOOT_BRANCH" >/dev/null 2>&1 || true
else
    git clone --depth 1 --branch "$SCROW_BOOT_BRANCH" \
        https://github.com/midn8crow/scrow.git "$SCROW_BOOT_DIR" >/dev/null 2>&1 || {
        printf 'SCROW: could not download the installer. Check your connection.\n' >&2
        exit 1
    }
fi

ver="$(cat "$SCROW_BOOT_DIR/VERSION" 2>/dev/null | tr -d '[:space:]')"
if [[ -n "$ver" ]] && git -C "$SCROW_BOOT_DIR" rev-parse -q --verify "refs/tags/v$ver" >/dev/null 2>&1; then
    git -C "$SCROW_BOOT_DIR" checkout --quiet "v$ver" 2>/dev/null || true
    printf 'Using verified release v%s\n' "$ver"
else
    printf 'Using branch %s\n' "$SCROW_BOOT_BRANCH"
fi

printf 'Starting the SCROW Installer…\n\n'
exec bash "$SCROW_BOOT_DIR/install.sh" "$@"
