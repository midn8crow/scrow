#!/usr/bin/env bash
# =============================================================================
# SCROW — core functions
# =============================================================================
# Shared helper functions used by all installer scripts.
# Modeled after end-4/dots-hyprland's functions.sh.

# -----------------------------------------------------------------------------
# x() — Execute a command with status output
# -----------------------------------------------------------------------------
# Usage: x <description> <command> [args...]
# Prints the description, runs the command, shows success/failure.
# On failure: retries once, then exits the installer.
x() {
    local description="$1"
    shift
    local cmd=("$@")

    printf "${C_DIM}  [%s]${C_RST} " "$description"
    if "${cmd[@]}" >/dev/null 2>&1; then
        printf "${C_OK}[ OK ]${C_RST}\n"
        return 0
    fi

    # Retry once
    printf "${C_WARN}[FAIL] retrying…${C_RST} "
    if "${cmd[@]}" >/dev/null 2>&1; then
        printf "${C_OK}[ OK ]${C_RST}\n"
        return 0
    fi

    printf "${C_ERR}[FAIL]${C_RST}\n"
    printf "${C_ERR}  Command failed:${C_RST} %s\n" "${cmd[*]}"
    printf "${C_ERR}  Aborting installation.${C_RST}\n"
    exit 1
}

# -----------------------------------------------------------------------------
# v() — Execute a command verbosely (show output)
# -----------------------------------------------------------------------------
# Usage: v <description> <command> [args...]
# Like x(), but pipes output to the terminal in real time.
# Uses a simple approach: run command, capture exit code, print result.
v() {
    local description="$1"
    shift
    local cmd=("$@")

    printf "${C_DIM}  [%s]${C_RST}\n" "$description"
    local logfile
    logfile="$(mktemp)"
    local rc=0
    "${cmd[@]}" 2>&1 | tee "$logfile"; rc=${PIPESTATUS[0]}
    rm -f "$logfile"

    if (( rc != 0 )); then
        printf "${C_ERR}  Command failed (exit %d):${C_RST} %s\n" "$rc" "${cmd[*]}"
        printf "${C_ERR}  Aborting installation.${C_RST}\n"
        exit 1
    fi
    return 0
}

# -----------------------------------------------------------------------------
# try() — Execute a command, ignore failure
# -----------------------------------------------------------------------------
try() {
    "$@" 2>/dev/null
}

# -----------------------------------------------------------------------------
# prevent_sudo_or_root() — Abort if running as root or with sudo
# -----------------------------------------------------------------------------
prevent_sudo_or_root() {
    if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
        printf "${C_ERR}Error: Do not run SCROW installer as root.${C_RST}\n"
        printf "${C_ERR}The installer will use sudo when needed.${C_RST}\n"
        exit 1
    fi
}

# -----------------------------------------------------------------------------
# git_auto_unshallow() — Ensure full git history if needed
# -----------------------------------------------------------------------------
git_auto_unshallow() {
    if [[ -d "$REPO_ROOT/.git" ]]; then
        local head
        head="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null)"
        if [[ -z "$head" ]]; then
            printf "${C_WARN}  Fetching full git history…${C_RST}\n"
            git -C "$REPO_ROOT" fetch --unshallow 2>/dev/null || true
        fi
    fi
}

# -----------------------------------------------------------------------------
# make_sudo_keepalive() — Keep sudo credentials alive in background
# -----------------------------------------------------------------------------
SCROW_SUDO_PID=""
make_sudo_keepalive() {
    if [[ -z "$SCROW_SUDO_PID" ]] || ! kill -0 "$SCROW_SUDO_PID" 2>/dev/null; then
        sudo -v 2>/dev/null
        ( while sudo -n true 2>/dev/null; do sleep 45; done ) &
        SCROW_SUDO_PID=$!
    fi
}

stop_sudo_keepalive() {
    if [[ -n "$SCROW_SUDO_PID" ]] && kill -0 "$SCROW_SUDO_PID" 2>/dev/null; then
        kill "$SCROW_SUDO_PID" 2>/dev/null
        wait "$SCROW_SUDO_PID" 2>/dev/null
    fi
}

# -----------------------------------------------------------------------------
# backup_file() — Backup an existing file before overwriting
# -----------------------------------------------------------------------------
backup_file() {
    local target="$1"
    if [[ -e "$target" || -L "$target" ]]; then
        mkdir -p "$SCROW_BACKUP_DIR"
        local backup_name
        backup_name="$SCROW_BACKUP_DIR/$(basename "$target").$(date +%Y%m%d-%H%M%S).bak"
        cp -a "$target" "$backup_name" 2>/dev/null || true
        printf "${C_DIM}  backed up: %s → %s${C_RST}\n" "$target" "$backup_name"
    fi
}

# -----------------------------------------------------------------------------
# showfun() — Display a function name with styling
# -----------------------------------------------------------------------------
showfun() {
    printf "${C_ACT}[%s]:${C_RST} " "$0"
    printf "${C_BOLD}%s${C_RST}\n" "$1"
}
