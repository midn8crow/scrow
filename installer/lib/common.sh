#!/usr/bin/env bash
# =============================================================================
# SCROW — common functions
# =============================================================================
# Colors, constants, logging, x()/v()/die(), sudo keepalive, backup.

# ── Colors ────────────────────────────────────────────────────────────────────
C_RST='\033[0m'
C_BOLD='\033[1m'
C_RED='\033[31m'
C_GRN='\033[32m'
C_YLW='\033[33m'
C_BLU='\033[34m'
C_CYN='\033[36m'
C_DIM='\033[2m'
C_OK="${C_GRN}"
C_ERR="${C_RED}"
C_WARN="${C_YLW}"
C_ACT="${C_CYN}"

# ── Constants ─────────────────────────────────────────────────────────────────
REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
export REPO_ROOT

SCROW_VERSION="$(cat "$REPO_ROOT/VERSION" 2>/dev/null || echo "0.0.0")"
export SCROW_VERSION

export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
export XDG_BIN_HOME="${XDG_BIN_HOME:-$HOME/.local/bin}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"

SCROW_BACKUP_DIR="$XDG_DATA_HOME/scrow/backups"
SCROW_MANIFEST="$XDG_DATA_HOME/scrow/manifest.tsv"

# ── Distro detection ──────────────────────────────────────────────────────────
SCROW_DISTRO_ID="unknown"
SCROW_DISTRO_FAMILY="unknown"
detect_distro() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        source /etc/os-release
        SCROW_DISTRO_ID="${ID:-unknown}"
        SCROW_DISTRO_FAMILY="${ID_LIKE:-$SCROW_DISTRO_ID}"
    fi
}
detect_distro

# ── Persistent log ────────────────────────────────────────────────────────────
SCROW_LOG_DIR="${XDG_STATE_HOME}/scrow"
SCROW_LOG_FILE="$SCROW_LOG_DIR/install-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$SCROW_LOG_DIR" 2>/dev/null

_log() {
    printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >> "$SCROW_LOG_FILE" 2>/dev/null
}

# ── Error reporting ───────────────────────────────────────────────────────────
_die_with_details() {
    local description="$1" cmd_str="$2" rc="$3" stderr_output="$4" suggestion="$5"

    printf "\n"
    printf "${C_ERR}${C_BOLD}  ╔══════════════════════════════════════════════════════════╗${C_RST}\n"
    printf "${C_ERR}${C_BOLD}  ║                    INSTALLATION FAILED                   ║${C_RST}\n"
    printf "${C_ERR}${C_BOLD}  ╚══════════════════════════════════════════════════════════╝${C_RST}\n"
    printf "\n"
    printf "  ${C_ERR}${C_BOLD}Failed operation:${C_RST} %s\n" "$description"
    printf "  ${C_ERR}${C_BOLD}Command:${C_RST}          %s\n" "$cmd_str"
    printf "  ${C_ERR}${C_BOLD}Exit code:${C_RST}        %s\n" "$rc"
    printf "\n"

    if [[ -n "$stderr_output" ]]; then
        printf "  ${C_ERR}${C_BOLD}Error output:${C_RST}\n"
        while IFS= read -r line; do
            printf "    ${C_ERR}%s${C_RST}\n" "$line"
        done <<< "$stderr_output"
        printf "\n"
    fi

    if [[ -n "$suggestion" ]]; then
        printf "  ${C_BOLD}${C_ACT}Suggested fix:${C_RST}\n"
        printf "    %s\n" "$suggestion"
        printf "\n"
    fi

    printf "  ${C_DIM}Full log: %s${C_RST}\n" "$SCROW_LOG_FILE"
    printf "\n"
    _log "FATAL: $description failed (exit $rc)"
    [[ -n "$stderr_output" ]] && _log "STDERR: $stderr_output"
}

# ── x() — Execute with status output ─────────────────────────────────────────
x() {
    local description="$1"; shift
    local cmd=("$@")
    local cmd_str="${cmd[*]}"
    _log "RUN: $cmd_str"

    printf "${C_DIM}  [%s]${C_RST} " "$description"

    local stderr_file stdout_file
    stderr_file="$(mktemp)"
    stdout_file="$(mktemp)"

    "${cmd[@]}" > "$stdout_file" 2> "$stderr_file"
    local rc=$?

    if [[ -s "$stdout_file" ]]; then
        cat "$stdout_file" >> "$SCROW_LOG_FILE" 2>/dev/null
        cat "$stdout_file"
    fi
    rm -f "$stdout_file"

    local stderr_output
    stderr_output="$(cat "$stderr_file")"
    rm -f "$stderr_file"

    if (( rc == 0 )); then
        printf "${C_OK}[ OK ]${C_RST}\n"
        _log "OK: $description"
        return 0
    fi

    _log "FAIL: $description (exit $rc)"
    [[ -n "$stderr_output" ]] && _log "STDERR: $stderr_output"
    printf "${C_ERR}[FAIL]${C_RST}\n"

    local suggestion=""
    if [[ "$cmd_str" == *"pacman"* ]]; then
        suggestion="$(diagnose_pacman_failure "$stderr_output" "$rc")"
    fi
    _die_with_details "$description" "$cmd_str" "$rc" "$stderr_output" "$suggestion"
    exit 1
}

# ── v() — Verbose execute ─────────────────────────────────────────────────────
v() {
    local description="$1"; shift
    local cmd=("$@")
    local cmd_str="${cmd[*]}"
    _log "RUN (verbose): $cmd_str"

    printf "${C_DIM}  [%s]${C_RST}\n" "$description"

    local logfile
    logfile="$(mktemp)"
    "${cmd[@]}" > "$logfile" 2>&1
    local rc=$?

    cat "$logfile"
    cat "$logfile" >> "$SCROW_LOG_FILE" 2>/dev/null
    rm -f "$logfile"

    if (( rc != 0 )); then
        _log "FAIL: $description (exit $rc)"
        local suggestion=""
        if [[ "$cmd_str" == *"pacman"* ]]; then
            suggestion="$(diagnose_pacman_failure "$(cat "$logfile" 2>/dev/null)" "$rc")"
        fi
        _die_with_details "$description" "$cmd_str" "$rc" "$(cat "$logfile" 2>/dev/null)" "$suggestion"
        exit 1
    fi
    _log "OK: $description"
    return 0
}

# ── try() — Ignore failure ────────────────────────────────────────────────────
try() { "$@" 2>/dev/null || true; }

# ── Pacman failure diagnosis ──────────────────────────────────────────────────
diagnose_pacman_failure() {
    local stderr_output="$1" rc="$2"

    if [[ "$stderr_output" == *"unable to lock database"* ]] || \
       [[ "$stderr_output" == *"Could not lock"* ]] || \
       [[ "$stderr_output" == *"db.lck"* ]] || \
       [[ -f /var/lib/pacman/db.lck ]]; then
        local lock_pid
        lock_pid="$(grep -oP '(?<=by process )\d+' <<< "$stderr_output" 2>/dev/null || true)"
        if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
            printf "Another pacman process (PID %s) holds the lock. Wait for it to finish, then re-run." "$lock_pid"
        else
            printf "Stale pacman lock file detected. Run:\n  sudo rm /var/lib/pacman/db.lck\nThen re-run the installer."
        fi
        return 0
    fi

    if [[ "$stderr_output" == *"invalid or corrupted"* ]] || \
       [[ "$stderr_output" == *"keyring"* ]] || \
       [[ "$stderr_output" == *"signature"* ]] || \
       [[ "$stderr_output" == *"unknown trust"* ]]; then
        printf "Pacman keyring issue. Run:\n  sudo pacman -Sy archlinux-keyring\n  sudo pacman -Su\nThen re-run."
        return 0
    fi

    if [[ "$stderr_output" == *"Could not resolve host"* ]] || \
       [[ "$stderr_output" == *"Connection refused"* ]] || \
       [[ "$stderr_output" == *"Connection timed out"* ]] || \
       [[ "$stderr_output" == *"Network is unreachable"* ]]; then
        printf "Network issue. Check your internet connection and DNS, then re-run."
        return 0
    fi

    if [[ "$stderr_output" == *"404 Not Found"* ]] || \
       [[ "$stderr_output" == *"failed retrieving file"* ]]; then
        printf "Mirror issue. Try:\n  sudo pacman -Syy\n  sudo pacman -Syu\nOr check /etc/pacman.d/mirrorlist."
        return 0
    fi

    if [[ "$stderr_output" == *"failed to commit transaction"* ]]; then
        printf "Transaction conflict. Check the error above. Try: sudo pacman -Syyu"
        return 0
    fi

    if (( rc != 0 )); then
        printf "Pacman failed with exit code %d. Check the error output above." "$rc"
    fi
    return 0
}

# ── pacman_update ─────────────────────────────────────────────────────────────
pacman_update() {
    if [[ -f /var/lib/pacman/db.lck ]]; then
        local lock_pid
        lock_pid="$(lsof /var/lib/pacman/db.lck 2>/dev/null | awk 'NR>1{print $2}' || true)"
        if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
            printf "${C_ERR}  Error: Pacman is locked by PID %s.${C_RST}\n" "$lock_pid"
            exit 1
        else
            printf "${C_WARN}  Removing stale pacman lock…${C_RST}\n"
            sudo rm -f /var/lib/pacman/db.lck
        fi
    fi

    printf "${C_DIM}  [refresh archlinux-keyring]${C_RST} "
    if sudo pacman -Sy --noconfirm archlinux-keyring 2>/dev/null; then
        printf "${C_OK}[ OK ]${C_RST}\n"
    else
        printf "${C_WARN}[WARN]${C_RST} non-fatal, continuing\n"
    fi

    printf "${C_DIM}  [pacman -Syu]${C_RST} "
    local stderr_file
    stderr_file="$(mktemp)"
    if sudo pacman -Syu --noconfirm 2>"$stderr_file"; then
        printf "${C_OK}[ OK ]${C_RST}\n"
        rm -f "$stderr_file"
        return 0
    fi
    local rc=$?
    local stderr_output
    stderr_output="$(cat "$stderr_file")"
    rm -f "$stderr_file"

    if [[ "$stderr_output" == *"nothing to do"* ]]; then
        printf "${C_OK}[ OK ]${C_RST} (already up to date)\n"
        return 0
    fi
    printf "${C_ERR}[FAIL]${C_RST}\n"
    local suggestion
    suggestion="$(diagnose_pacman_failure "$stderr_output" "$rc")"
    _die_with_details "system update" "sudo pacman -Syu --noconfirm" "$rc" "$stderr_output" "$suggestion"
    exit 1
}

# ── Sudo keepalive ────────────────────────────────────────────────────────────
SCROW_SUDO_PID=""
make_sudo_keepalive() {
    if [[ -z "${SCROW_SUDO_PID:-}" ]] || ! kill -0 "$SCROW_SUDO_PID" 2>/dev/null; then
        sudo -v 2>/dev/null
        ( while sudo -n true 2>/dev/null; do sleep 45; done ) &
        SCROW_SUDO_PID=$!
    fi
}
stop_sudo_keepalive() {
    if [[ -n "${SCROW_SUDO_PID:-}" ]] && kill -0 "$SCROW_SUDO_PID" 2>/dev/null; then
        kill "$SCROW_SUDO_PID" 2>/dev/null || true
        wait "$SCROW_SUDO_PID" 2>/dev/null || true
    fi
}

# ── Backup ────────────────────────────────────────────────────────────────────
backup_file() {
    local target="$1"
    if [[ -e "$target" || -L "$target" ]]; then
        mkdir -p "$SCROW_BACKUP_DIR"
        local relpath="${target#$HOME/}"
        local backup_name="$SCROW_BACKUP_DIR/${relpath//\//__}.$(date +%Y%m%d-%H%M%S).bak"
        cp -a "$target" "$backup_name" 2>/dev/null || true
        printf "${C_DIM}  backed up: %s → %s${C_RST}\n" "$target" "$backup_name"
        _log "Backed up: $target → $backup_name"
    fi
}

# ── Prevent root ──────────────────────────────────────────────────────────────
prevent_sudo_or_root() {
    if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
        printf "${C_ERR}Error: Do not run SCROW installer as root.${C_RST}\n"
        exit 1
    fi
}

# ── Temp file tracking ────────────────────────────────────────────────────────
SCROW_TMPFILES=()
register_tmp() { SCROW_TMPFILES+=("$1"); }
cleanup_tmpfiles() {
    local f
    for f in "${SCROW_TMPFILES[@]}"; do
        rm -rf "$f" 2>/dev/null
    done
}
