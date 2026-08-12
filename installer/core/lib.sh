#!/usr/bin/env bash
# =============================================================================
# SCROW - core library
# =============================================================================
# Shared globals, paths, logging and helpers for the whole installer.
# This file is sourced by install.sh and every installer module.
# =============================================================================

set -uo pipefail

# -----------------------------------------------------------------------------
# Globals / paths
# -----------------------------------------------------------------------------
export SCROW_SELF="$0"
export SCROW_REPO="${SCROW_REPO:-}"
if [[ -z "$SCROW_REPO" ]]; then
    SCROW_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

export SCROW_VERSION="$(cat "$SCROW_REPO/VERSION" 2>/dev/null | tr -d '[:space:]')"
export SCROW_VERSION="${SCROW_VERSION:-0.0.0}"

export SCROW_STATE_DIR="$HOME/.local/share/scrow"
export SCROW_INSTALLER_DIR="$SCROW_STATE_DIR/installer"
export SCROW_REPO_DIR="$SCROW_STATE_DIR/repo"
export SCROW_BACKUP_DIR="$SCROW_STATE_DIR/backups"
export SCROW_LOG_DIR="$SCROW_STATE_DIR/logs"
export SCROW_MANIFEST="$SCROW_STATE_DIR/manifest"
export SCROW_STATE_FILE="$SCROW_STATE_DIR/state"
export SCROW_VERSIONS_DIR="$SCROW_STATE_DIR/versions"
export SCROW_CURRENT_LOG="$SCROW_LOG_DIR/scrow.log"

export SCROW_DRY_RUN="${SCROW_DRY_RUN:-0}"
export SCROW_UI="${SCROW_UI:-tui}"

# -----------------------------------------------------------------------------
# Colors (restrained catppuccin-inspired palette)
# -----------------------------------------------------------------------------
C_RESET=$'\033[0m'
C_BOLD=$'\033[1m'
C_FAINT=$'\033[2m'
C_REV=$'\033[7m'
C_ACCENT=$'\033[38;5;117m'
C_PURPLE=$'\033[38;5;141m'
C_OK=$'\033[38;5;114m'
C_WARN=$'\033[38;5;222m'
C_ERR=$'\033[38;5;210m'
C_DIM=$'\033[38;5;245m'

# -----------------------------------------------------------------------------
# Logging
# -----------------------------------------------------------------------------
scrow_log_init() {
    mkdir -p "$SCROW_LOG_DIR"
    {
        echo "=================================================="
        echo "SCROW session started $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Version : $SCROW_VERSION"
        echo "Command : $*"
        echo "Source  : $SCROW_REPO"
        echo "=================================================="
    } >> "$SCROW_CURRENT_LOG"
}

scrow_log() {
    local level="${2:-INFO}"
    echo "[$(date '+%H:%M:%S')] [$level] $1" >> "$SCROW_CURRENT_LOG"
}

scrow_log_run() {
    # Run a command capturing its output into the log. Returns its exit code.
    local desc="$1"
    shift
    scrow_log "RUN $desc"
    if [[ "$SCROW_DRY_RUN" == "1" ]]; then
        scrow_log "DRY-RUN (skipped): $*"
        echo "  [dry-run] ${C_DIM}$*${C_RESET}" >&2
        return 0
    fi
    {
        echo "--- $desc"
        echo "--- cmd: $*"
        "$@" 2>&1
        echo "--- exit: $?"
    } >> "$SCROW_CURRENT_LOG" 2>&1 || true
}

scrow_log_tee() {
    # Run a command, keep its output flowing into the log only.
    local desc="$1"
    shift
    scrow_log "RUN $desc"
    if [[ "$SCROW_DRY_RUN" == "1" ]]; then
        scrow_log "DRY-RUN (skipped): $*"
        echo "  [dry-run] ${C_DIM}$*${C_RESET}" >&2
        return 0
    fi
    {
        echo "--- $desc"
        echo "--- cmd: $*"
        "$@" 2>&1
        echo "--- exit: $?"
    } >> "$SCROW_CURRENT_LOG"
}

# -----------------------------------------------------------------------------
# sudo handling (only invoked for operations that truly need root)
# -----------------------------------------------------------------------------
scrow_need_root() {
    if [[ "$SCROW_DRY_RUN" == "1" ]]; then
        return 0
    fi
    if ! sudo -n true 2>/dev/null; then
        ui_info "Root access is required for this step."
        sudo -v
    fi
    scrow_log "sudo privileges validated"
}

scrow_run_sudo() {
    # Run a command with sudo, captured to the log.
    local desc="$1"
    shift
    scrow_log "RUN(SUDO) $desc"
    if [[ "$SCROW_DRY_RUN" == "1" ]]; then
        scrow_log "DRY-RUN (skipped): sudo $*"
        echo "  [dry-run] ${C_DIM}sudo $*${C_RESET}" >&2
        return 0
    fi
    {
        echo "--- $desc"
        echo "--- cmd: sudo $*"
        sudo "$@" 2>&1
        echo "--- exit: $?"
    } >> "$SCROW_CURRENT_LOG" 2>&1 || true
}

# -----------------------------------------------------------------------------
# Generic helpers
# -----------------------------------------------------------------------------
scrow_die() {
    scrow_log "FATAL $1"
    ui_error "$1"
    exit 1
}

scrow_sha() {
    sha256sum "$1" 2>/dev/null | cut -d' ' -f1
}

scrow_is_symlink() {
    [[ -L "$1" ]]
}

scrow_realpath() {
    # portable-ish realpath
    if command -v realpath >/dev/null 2>&1; then
        realpath "$1"
    else
        readlink -f "$1"
    fi
}

scrow_mkdir() {
    mkdir -p "$1"
}

scrow_banner_small() {
    # Small, restrained brand line used inside panels.
    printf '%sSCROW%s %s• Arch Linux • Hyprland%s\n' "$C_BOLD" "$C_RESET" "$C_DIM" "$C_RESET"
}

# The easter egg. Branding only, never functional.
scrow_egg() {
    echo "${C_FAINT}Itachi is Goat 🐦‍⬛${C_RESET}"
}
