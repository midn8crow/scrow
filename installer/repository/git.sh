#!/usr/bin/env bash
# =============================================================================
# SCROW - source repository handling
# =============================================================================
# SCROW keeps a self-contained mirror of the official repository under
# ~/.local/share/scrow/repo so that `scrow` works from any directory and
# Update / Reset always operate against a clean official state.
# =============================================================================

SCROW_REPO_URL="https://github.com/midn8crow/scrow.git"
SCROW_REPO_BRANCH="main"

# -----------------------------------------------------------------------------
# Mirror management
# -----------------------------------------------------------------------------
scrow_repo_ensure_mirror() {
    # Creates the official mirror if it does not exist yet.
    if [[ -d "$SCROW_REPO_DIR/.git" ]]; then
        return 0
    fi
    ui_step "Fetching official SCROW repository…"
    if [[ "$SCROW_DRY_RUN" == "1" ]]; then
        ui_dim "  [dry-run] git clone --depth 1 $SCROW_REPO_URL -> $SCROW_REPO_DIR"
        return 0
    fi
    mkdir -p "$SCROW_STATE_DIR"
    [[ "$SCROW_LOG_READY" == "1" ]] || scrow_log_init "$SCROW_SELF"
    if git clone --depth 1 --branch "$SCROW_REPO_BRANCH" "$SCROW_REPO_URL" "$SCROW_REPO_DIR" \
        >> "$SCROW_CURRENT_LOG" 2>&1; then
        ui_ok "Repository mirror ready"
    else
        ui_warn "Could not clone the official repository (offline?)"
        scrow_log "ERROR repo clone failed"
        return 1
    fi
}

scrow_repo_refresh() {
    # Pulls the mirror to the latest official state.
    [[ -d "$SCROW_REPO_DIR/.git" ]] || { scrow_repo_ensure_mirror || return 1; }
    if [[ "$SCROW_DRY_RUN" == "1" ]]; then
        ui_dim "  [dry-run] git fetch + reset --hard origin/$SCROW_REPO_BRANCH in $SCROW_REPO_DIR"
        return 0
    fi
    ui_step "Refreshing official repository…"
    if git -C "$SCROW_REPO_DIR" fetch origin >> "$SCROW_CURRENT_LOG" 2>&1 \
       && git -C "$SCROW_REPO_DIR" reset --hard "origin/$SCROW_REPO_BRANCH" >> "$SCROW_CURRENT_LOG" 2>&1; then
        ui_ok "Repository refreshed"
        return 0
    fi
    ui_warn "Could not refresh the repository (network?)"
    scrow_log "ERROR repo refresh failed"
    return 1
}

# -----------------------------------------------------------------------------
# Version checks
# -----------------------------------------------------------------------------
scrow_repo_local_version() {
    # Version stored in the current SCROW source tree.
    [[ -f "$SCROW_REPO/VERSION" ]] && cat "$SCROW_REPO/VERSION" | tr -d '[:space:]'
}

scrow_repo_remote_version() {
    # Latest version on origin/main of the mirror.
    local d="${1:-$SCROW_REPO_DIR}"
    [[ -d "$d/.git" ]] || return 1
    git -C "$d" fetch origin >/dev/null 2>&1
    git -C "$d" show "origin/$SCROW_REPO_BRANCH:VERSION" 2>/dev/null | tr -d '[:space:]'
}

scrow_repo_version_cmp() {
    # 0 if equal, 2 if $1 is newer than $2, 1 otherwise.
    [[ "$1" == "$2" ]] && return 0
    if [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" == "$1" ]]; then
        return 2
    fi
    return 1
}
