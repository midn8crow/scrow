#!/usr/bin/env bash
# =============================================================================
# SCROW — core functions
# =============================================================================
# Shared helper functions used by all installer scripts.

# ── Persistent log file ───────────────────────────────────────────────────────
SCROW_LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/scrow"
SCROW_LOG_FILE="$SCROW_LOG_DIR/install-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$SCROW_LOG_DIR" 2>/dev/null

# Write a timestamped line to the log
_log() {
    printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >> "$SCROW_LOG_FILE" 2>/dev/null
}

# ── Error reporting screen ────────────────────────────────────────────────────
# Shows the user exactly what failed, why, and what to do about it.
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

# ── x() — Execute a command with status output ───────────────────────────────
# Usage: x <description> <command> [args...]
# Shows success/failure. On failure: shows real error, suggests fix, exits.
x() {
    local description="$1"
    shift
    local cmd=("$@")

    local cmd_str="${cmd[*]}"
    _log "RUN: $cmd_str"

    printf "${C_DIM}  [%s]${C_RST} " "$description"

    local stderr_file stdout_file
    stderr_file="$(mktemp)"
    stdout_file="$(mktemp)"

    # Run command, capture both stdout and stderr separately.
    # Process substitution >() swallows exit codes, so use explicit files.
    "${cmd[@]}" > "$stdout_file" 2> "$stderr_file"
    local rc=$?

    # Tee stdout to log and terminal
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

    # Diagnose the failure and suggest a fix
    local suggestion=""
    if [[ "$cmd_str" == *"pacman"* ]]; then
        suggestion="$(diagnose_pacman_failure "$stderr_output" "$rc")"
    fi

    _die_with_details "$description" "$cmd_str" "$rc" "$stderr_output" "$suggestion"
    exit 1
}

# ── v() — Execute a command verbosely (show output in real time) ─────────────
# Usage: v <description> <command> [args...]
# Shows all output in real time. On failure: shows error, suggests fix, exits.
v() {
    local description="$1"
    shift
    local cmd=("$@")

    local cmd_str="${cmd[*]}"
    _log "RUN (verbose): $cmd_str"

    printf "${C_DIM}  [%s]${C_RST}\n" "$description"

    local logfile
    logfile="$(mktemp)"

    # Run command, capture all output to logfile, then display.
    # Using file capture instead of pipe to reliably get the exit code.
    "${cmd[@]}" > "$logfile" 2>&1
    local rc=$?

    # Display captured output
    cat "$logfile"

    # Append to persistent log
    cat "$logfile" >> "$SCROW_LOG_FILE" 2>/dev/null
    rm -f "$logfile"

    if (( rc != 0 )); then
        local stderr_output
        stderr_output="$(cat "$logfile" 2>/dev/null || true)"
        rm -f "$logfile"

        _log "FAIL: $description (exit $rc)"

        local suggestion=""
        if [[ "$cmd_str" == *"pacman"* ]]; then
            suggestion="$(diagnose_pacman_failure "$stderr_output" "$rc")"
        fi

        _die_with_details "$description" "$cmd_str" "$rc" "$stderr_output" "$suggestion"
        exit 1
    fi

    rm -f "$logfile"
    _log "OK: $description"
    return 0
}

# ── pacman failure diagnosis ──────────────────────────────────────────────────
# Inspects stderr and suggests the right fix for common Arch failures.
diagnose_pacman_failure() {
    local stderr_output="$1"
    local rc="$2"

    # Database lock
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

    # Keyring / signature issues
    if [[ "$stderr_output" == *"invalid or corrupted"* ]] || \
       [[ "$stderr_output" == *"keyring"* ]] || \
       [[ "$stderr_output" == *"signature"* ]] || \
       [[ "$stderr_output" == *"unknown trust"* ]] || \
       [[ "$stderr_output" == *"missing signature"* ]]; then
        printf "Pacman keyring or package signature issue. Run:\n  sudo pacman -Sy archlinux-keyring\n  sudo pacman -Su\nThen re-run the installer."
        return 0
    fi

    # Mirror / network issues
    if [[ "$stderr_output" == *"Could not resolve host"* ]] || \
       [[ "$stderr_output" == *"Connection refused"* ]] || \
       [[ "$stderr_output" == *"Connection timed out"* ]] || \
       [[ "$stderr_output" == *"Network is unreachable"* ]] || \
       [[ "$stderr_output" == *"Failed to connect"* ]]; then
        printf "Network connectivity issue. Check your internet connection and DNS, then re-run."
        return 0
    fi

    # Mirror sync / 404 errors
    if [[ "$stderr_output" == *"404 Not Found"* ]] || \
       [[ "$stderr_output" == *"failed retrieving file"* ]] || \
       [[ "$stderr_output" == *" HttpStatusCode"* ]]; then
        printf "Mirror sync issue. Try:\n  sudo pacman -Syy\n  sudo pacman -Syu\nOr check /etc/pacman.d/mirrorlist for working mirrors."
        return 0
    fi

    # Failed to commit transaction (corrupted packages, conflicts, etc.)
    if [[ "$stderr_output" == *"failed to commit transaction"* ]]; then
        printf "Transaction conflict or corruption. Check the error details above.\nYou may need to force-refresh: sudo pacman -Syyu"
        return 0
    fi

    # Generic failure (only when rc != 0)
    if (( rc == 1 )); then
        printf "Pacman exited with error. Check the error output above for details."
    elif (( rc == 2 )); then
        printf "Pacman encountered a fatal error (code 2). This usually means a configuration problem.\nCheck /etc/pacman.conf and /etc/pacman.d/mirrorlist."
    elif (( rc == 130 )) || (( rc == 137 )); then
        printf "Pacman was interrupted (signal %d). If this persists, check for a stale lock:\n  sudo rm /var/lib/pacman/db.lck" "$rc"
    elif (( rc != 0 )); then
        printf "Pacman failed with exit code %d. Check the error output above." "$rc"
    fi
    return 0
}

# ── pacman_update — Safe system update with diagnostics ──────────────────────
# Handles: fresh keyrings, stale databases, lock files, mirror issues.
# Never blindly deletes lock files. Never disables signature checking.
pacman_update() {
    # Step 1: Check for stale lock file BEFORE attempting anything
    if [[ -f /var/lib/pacman/db.lck ]]; then
        local lock_pid
        lock_pid="$(lsof /var/lib/pacman/db.lck 2>/dev/null | awk 'NR>1{print $2}' || true)"
        if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
            printf "${C_ERR}  Error: Pacman is locked by another process (PID %s).${C_RST}\n" "$lock_pid"
            printf "${C_ERR}  Wait for it to finish or kill it, then re-run.${C_RST}\n"
            exit 1
        else
            printf "${C_WARN}  Warning: Stale pacman lock file found (no active process).${C_RST}\n"
            printf "${C_WARN}  Removing stale lock...${C_RST}\n"
            sudo rm -f /var/lib/pacman/db.lck
            _log "Removed stale pacman lock file"
        fi
    fi

    # Step 2: Refresh keyring first (fixes stale keyring on fresh installs)
    printf "${C_DIM}  [%s]${C_RST} " "refresh archlinux-keyring"
    _log "RUN: sudo pacman -Sy --noconfirm archlinux-keyring"

    local stderr_file
    stderr_file="$(mktemp)"
    if sudo pacman -Sy --noconfirm archlinux-keyring > >(tee -a "$SCROW_LOG_FILE" 2>/dev/null) 2>"$stderr_file"; then
        printf "${C_OK}[ OK ]${C_RST}\n"
        _log "OK: archlinux-keyring refreshed"
    else
        local rc=$?
        local stderr_output
        stderr_output="$(cat "$stderr_file")"
        rm -f "$stderr_file"

        # Keyring refresh failure is often non-fatal on already-fresh systems
        if [[ "$stderr_output" == *"nothing to do"* ]] || [[ "$stderr_output" == *"is up to date"* ]]; then
            printf "${C_OK}[ OK ]${C_RST} (already up to date)\n"
            _log "OK: archlinux-keyring already up to date"
        else
            printf "${C_WARN}[WARN]${C_RST} keyring refresh failed (non-fatal, continuing)\n"
            _log "WARN: keyring refresh failed (exit $rc): $stderr_output"
        fi
    fi

    # Step 3: Full system update
    printf "${C_DIM}  [%s]${C_RST} " "pacman -Syu"
    _log "RUN: sudo pacman -Syu --noconfirm"

    stderr_file="$(mktemp)"
    if sudo pacman -Syu --noconfirm > >(tee -a "$SCROW_LOG_FILE" 2>/dev/null) 2>"$stderr_file"; then
        printf "${C_OK}[ OK ]${C_RST}\n"
        rm -f "$stderr_file"
        _log "OK: system updated"
        return 0
    fi

    local rc=$?
    local stderr_output
    stderr_output="$(cat "$stderr_file")"
    rm -f "$stderr_file"

    _log "FAIL: pacman -Syu (exit $rc)"
    [[ -n "$stderr_output" ]] && _log "STDERR: $stderr_output"

    printf "${C_ERR}[FAIL]${C_RST}\n"

    # If the only issue is "nothing to do", that's fine
    if [[ "$stderr_output" == *"nothing to do"* ]]; then
        printf "${C_OK}  System is already up to date.${C_RST}\n"
        _log "OK: system already up to date"
        return 0
    fi

    local suggestion
    suggestion="$(diagnose_pacman_failure "$stderr_output" "$rc")"
    _die_with_details "system update" "sudo pacman -Syu --noconfirm" "$rc" "$stderr_output" "$suggestion"
    exit 1
}

# ── try() — Execute a command, ignore failure ─────────────────────────────────
try() {
    "$@" 2>/dev/null || true
}

# ── prevent_sudo_or_root() — Abort if running as root or with sudo ───────────
prevent_sudo_or_root() {
    if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
        printf "${C_ERR}Error: Do not run SCROW installer as root.${C_RST}\n"
        printf "${C_ERR}The installer will use sudo when needed.${C_RST}\n"
        exit 1
    fi
}

# ── git_auto_unshallow() — Ensure full git history if needed ──────────────────
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

# ── make_sudo_keepalive() — Keep sudo credentials alive in background ────────
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

# ── backup_file() — Backup an existing file before overwriting ────────────────
backup_file() {
    local target="$1"
    if [[ -e "$target" || -L "$target" ]]; then
        mkdir -p "$SCROW_BACKUP_DIR"
        local backup_name
        backup_name="$SCROW_BACKUP_DIR/$(basename "$target").$(date +%Y%m%d-%H%M%S).bak"
        cp -a "$target" "$backup_name" 2>/dev/null || true
        printf "${C_DIM}  backed up: %s → %s${C_RST}\n" "$target" "$backup_name"
        _log "Backed up: $target → $backup_name"
    fi
}

# ── showfun() — Display a function name with styling ──────────────────────────
showfun() {
    printf "${C_ACT}[%s]:${C_RST} " "$0"
    printf "${C_BOLD}%s${C_RST}\n" "$1"
}
