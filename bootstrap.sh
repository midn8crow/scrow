#!/usr/bin/env bash
# =============================================================================
# SCROW — one-line bootstrap
# =============================================================================
# Tiny by design: clone the repository into a temporary directory, launch
# the installer from inside it, then remove the clone.
#
#   curl -fsSL https://raw.githubusercontent.com/midn8crow/scrow/main/bootstrap.sh | bash
#
# Environment overrides:
#   SCROW_REPO_URL    git clone URL (default: https://github.com/midn8crow/scrow.git)
#   SCROW_REPO_BRANCH branch to clone (default: main)
# =============================================================================

set -uo pipefail

SCROW_REPO_URL="${SCROW_REPO_URL:-https://github.com/midn8crow/scrow.git}"
SCROW_REPO_BRANCH="${SCROW_REPO_BRANCH:-main}"

printf 'SCROW · Arch Linux · Hyprland\n\n'

for cmd in git mktemp; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        printf 'SCROW: %s is required to install SCROW.\n' "$cmd" >&2
        exit 1
    fi
done

SCROW_TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/scrow-XXXXXX" 2>/dev/null)" \
    || SCROW_TMP_DIR="$(mktemp -d 2>/dev/null)"
if [[ -z "$SCROW_TMP_DIR" || ! -d "$SCROW_TMP_DIR" ]]; then
    printf 'SCROW: could not create a temporary directory.\n' >&2
    exit 1
fi

scrow_boot_cleanup() {
    rm -rf "$SCROW_TMP_DIR" 2>/dev/null
}
scrow_boot_exit() {
    scrow_boot_cleanup
    exit "$1"
}
trap scrow_boot_cleanup EXIT
trap 'scrow_boot_exit 130' INT
trap 'scrow_boot_exit 143' TERM
trap 'scrow_boot_exit 129' HUP

printf 'Downloading SCROW…\n'
if ! git clone --depth 1 --branch "$SCROW_REPO_BRANCH" \
    -- "$SCROW_REPO_URL" "$SCROW_TMP_DIR"; then
    printf 'SCROW: could not clone the SCROW repository.\n' >&2
    printf 'Check your network, then retry:\n' >&2
    printf '  curl -fsSL https://raw.githubusercontent.com/midn8crow/scrow/main/bootstrap.sh | bash\n' >&2
    exit 1
fi

if [[ ! -f "$SCROW_TMP_DIR/setup" ]]; then
    printf 'SCROW: clone succeeded but setup not found in %s.\n' "$SCROW_TMP_DIR" >&2
    exit 1
fi

# When piped, give the installer the user's actual terminal
if [[ ! -t 0 ]] && ( : < /dev/tty ) 2>/dev/null; then
    bash "$SCROW_TMP_DIR/setup" "${@:-full}" < /dev/tty
else
    bash "$SCROW_TMP_DIR/setup" "${@:-full}"
fi
exit $?
