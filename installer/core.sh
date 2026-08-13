#!/usr/bin/env bash
# =============================================================================
# SCROW — core foundation
# =============================================================================
# Shared globals, paths, color identity, logging and small helpers used by the
# whole installer. This file is pure bash: sourcing it runs no external
# commands and never touches the network, the package database or the
# filesystem beyond reading VERSION. Startup stays fast by design.
# =============================================================================

set -uo pipefail

# -----------------------------------------------------------------------------
# Paths
# -----------------------------------------------------------------------------
# Root of the current installer tree (the repository root when run from a
# clone, or the self-contained copy at ~/.local/share/scrow/installer when run
# via the `scrow` command).
SCROW_INSTALLER_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCROW_REPO="${SCROW_REPO:-$SCROW_INSTALLER_SRC}"

SCROW_STATE_DIR="${SCROW_STATE_DIR:-$HOME/.local/share/scrow}"
SCROW_BACKUP_DIR="$SCROW_STATE_DIR/backups"
SCROW_LOG_DIR="$SCROW_STATE_DIR/logs"
SCROW_MANIFEST="$SCROW_STATE_DIR/manifest"
SCROW_STATE_FILE="$SCROW_STATE_DIR/state"
SCROW_CURRENT_LOG="$SCROW_LOG_DIR/scrow.log"

SCROW_REPO_URL="${SCROW_REPO_URL:-https://github.com/midn8crow/scrow.git}"
SCROW_REPO_BRANCH="${SCROW_REPO_BRANCH:-main}"

SCROW_DRY_RUN="${SCROW_DRY_RUN:-0}"
SCROW_VERSION="$(cat "$SCROW_REPO/VERSION" 2>/dev/null | tr -d '[:space:]')"
SCROW_VERSION="${SCROW_VERSION:-0.0.0}"

# -----------------------------------------------------------------------------
# Color identity (restrained, deliberate). The accent is used sparingly —
# selection, status, headings — so it reads as a highlight, not noise.
# -----------------------------------------------------------------------------
C_RESET=$'\033[0m'
C_BOLD=$'\033[1m'
C_FAINT=$'\033[2m'
C_ACCENT=$'\033[38;5;141m'   # mauve — primary accent (SCROW identity)
C_OK=$'\033[38;5;114m'       # mint  — success / ready
C_WARN=$'\033[38;5;222m'     # amber — warning
C_ERR=$'\033[38;5;203m'      # red   — error / destructive
C_DIM=$'\033[38;5;245m'      # muted secondary text
C_HAIR=$'\033[38;5;239m'     # hairlines, rules
C_SELBG=$'\033[48;5;238m'    # selected-row background
C_BTN_BG=$'\033[48;5;141m'   # focused button fill
C_BTN_FG=$'\033[38;5;16m'    # focused button text

# -----------------------------------------------------------------------------
# Logging (only used by operations, never on the startup path)
# -----------------------------------------------------------------------------
scrow_log_init() {
    [[ "$SCROW_DRY_RUN" == "1" ]] && return 0
    mkdir -p "$SCROW_LOG_DIR"
    {
        echo "============================================="
        echo "SCROW session started $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Version  : $SCROW_VERSION"
        echo "Command  : $*"
        echo "Source   : $SCROW_REPO"
        echo "============================================="
    } >> "$SCROW_CURRENT_LOG"
    SCROW_LOG_READY=1
}

scrow_log() {
    [[ "${SCROW_LOG_READY:-0}" == "1" ]] || return 0
    printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$1" >> "$SCROW_CURRENT_LOG"
}

# Run a command, tee-ing its output into the log. Returns its exit code.
scrow_run() {
    local desc="$1"
    shift
    scrow_log "RUN $desc: $*"
    if [[ "$SCROW_DRY_RUN" == "1" ]]; then
        echo "  [dry-run] ${C_DIM}$*${C_RESET}"
        return 0
    fi
    local rc=0
    {
        echo "--- $desc"
        echo "--- cmd: $*"
        "$@" 2>&1
        rc=$?
        echo "--- exit: $rc"
    } >> "$SCROW_CURRENT_LOG"
    return $rc
}

# Run a command as root, tee-ing into the log. Returns its exit code.
scrow_run_sudo() {
    local desc="$1"
    shift
    scrow_log "RUN(SUDO) $desc: $*"
    if [[ "$SCROW_DRY_RUN" == "1" ]]; then
        echo "  [dry-run] ${C_DIM}sudo $*${C_RESET}"
        return 0
    fi
    scrow_need_root
    local rc=0
    {
        echo "--- $desc"
        echo "--- cmd: sudo $*"
        sudo "$@" 2>&1
        rc=$?
        echo "--- exit: $rc"
    } >> "$SCROW_CURRENT_LOG"
    return $rc
}

# Prompt for sudo up front for the current session (only when root is needed).
scrow_need_root() {
    [[ "$SCROW_DRY_RUN" == "1" ]] && return 0
    if ! sudo -n true 2>/dev/null; then
        echo "  ${C_DIM}SCROW needs root for this step.${C_RESET}"
        sudo -v
    fi
}

# -----------------------------------------------------------------------------
# Small helpers
# -----------------------------------------------------------------------------
scrow_sha() {
    sha256sum "$1" 2>/dev/null | cut -d' ' -f1
}

# Bulk hash cache: hashes every repo file in ONE sha256sum pass instead of
# forking per file. Used by the dashboard analysis and refresh loops so the
# UI stays fast. Lazy-loaded on first access.
declare -A SCROW_SHA_CACHE=()
SCROW_SHA_CACHE_LOADED=0

scrow_sha_cache_load() {
    # Hashes the files SCROW actually cares about (manifest f-entries) in ONE
    # sha256sum pass. Defined in core.sh but uses scrow_tsv/scrow_manifest_lines
    # from the ownership module — resolved at call time, never at source time.
    SCROW_SHA_CACHE=()
    SCROW_SHA_CACHE_LOADED=1
    local -a srcs=() uniq=()
    local line src
    local -A seen=()
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        scrow_tsv "$line"
        [[ "${SCROW_MF[2]}" != "f" ]] && continue
        src="${SCROW_MF[3]#@}"
        [[ -z "$src" || "$src" == "${SCROW_MF[3]}" ]] && src="${SCROW_MF[0]}"
        srcs+=("$src")
    done < <(scrow_manifest_lines)
    for src in "${srcs[@]}"; do
        [[ -n "${seen[$src]:-}" ]] && continue
        seen[$src]=1
        uniq+=("$src")
    done
    local h f
    if [[ ${#uniq[@]} -gt 0 ]]; then
        while IFS=' ' read -r h f; do
            [[ -z "$h" || -z "$f" ]] && continue
            f="${f#./}"
            SCROW_SHA_CACHE["$f"]="$h"
        done < <(cd "$SCROW_REPO" && printf '%s\0' "${uniq[@]}" | xargs -0 sha256sum 2>/dev/null)
    fi
}

SCROW_SHA_CACHE_RET=""
scrow_sha_cache_get() {
    # repo-relative path; callers should scrow_sha_cache_load first. Result is
    # returned in $SCROW_SHA_CACHE_RET (no subshell so hot loops stay fast).
    SCROW_SHA_CACHE_RET=""
    local rel="$1" h
    [[ -z "$rel" ]] && return
    if [[ "$SCROW_SHA_CACHE_LOADED" != "1" ]]; then
        SCROW_SHA_CACHE_RET="$(scrow_sha "$SCROW_REPO/$rel" 2>/dev/null)"
        return
    fi
    h="${SCROW_SHA_CACHE[$rel]:-}"
    if [[ -z "$h" ]]; then
        h="$(scrow_sha "$SCROW_REPO/$rel" 2>/dev/null)"
        [[ -n "$h" ]] && SCROW_SHA_CACHE["$rel"]="$h"
    fi
    SCROW_SHA_CACHE_RET="$h"
}

# Live-disk hash cache: hashes every manifest target ON THE SYSTEM in ONE
# sha256sum pass, so the Doctor/repair compare against what is actually on
# disk instead of the last-known "current" value recorded at manifest build.
# Lazy-loaded on first access. Missing targets are simply absent from the map.
declare -A SCROW_TARGET_SHA=()
SCROW_TARGET_SHA_LOADED=0

scrow_target_sha_load() {
    SCROW_TARGET_SHA=()
    SCROW_TARGET_SHA_LOADED=1
    local -a tgts=() uniq=()
    local -A seen=()
    local line rel t
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        rel="${line%%$'\t'*}"
        t="$(scrow_target "$rel")"
        [[ -n "${seen[$t]:-}" ]] && continue
        seen[$t]=1
        uniq+=("$t")
    done < <(scrow_manifest_lines)
    if [[ ${#uniq[@]} -gt 0 ]]; then
        while IFS=' ' read -r h f; do
            [[ -z "$h" || -z "$f" ]] && continue
            SCROW_TARGET_SHA["$f"]="$h"
        done < <(printf '%s\0' "${uniq[@]}" | xargs -0 sha256sum 2>/dev/null)
    fi
}

SCROW_TARGET_SHA_RET=""
scrow_target_sha_get() {
    # target path (scrow_target output). Result in $SCROW_TARGET_SHA_RET.
    SCROW_TARGET_SHA_RET=""
    local t="$1"
    [[ -z "$t" ]] && return
    if [[ "$SCROW_TARGET_SHA_LOADED" != "1" ]]; then scrow_target_sha_load; fi
    SCROW_TARGET_SHA_RET="${SCROW_TARGET_SHA[$t]:-}"
}
