#!/usr/bin/env bash
# =============================================================================
# SCROW — install state
# =============================================================================
# SCROW tracks its own installation state in a single KEY=VALUE file
# (~/.local/share/scrow/state). The file is read once into memory at startup
# so the dashboard never touches the disk repeatedly; writes update both the
# in-memory copy and the file.
# =============================================================================

# In-memory copy of the state file (associative array).
declare -A SCROW_STATE_VARS=()

scrow_state_init() {
    SCROW_STATE_VARS=(
        [SCROW_VERSION]="$SCROW_VERSION"
        [INSTALLED]=0
        [COMPONENTS]=""
        [SERVICES]=""
        [EXTRA]=""
        [INSTALL_DATE]=""
    )
    if [[ -f "$SCROW_STATE_FILE" ]]; then
        local k v
        while IFS='=' read -r k v; do
            [[ -z "$k" || "$k" == \#* ]] && continue
            SCROW_STATE_VARS[$k]="$v"
        done < "$SCROW_STATE_FILE"
    fi
}

scrow_state_write() {
    [[ "$SCROW_DRY_RUN" == "1" ]] && return 0
    mkdir -p "$SCROW_STATE_DIR"
    local k
    for k in SCROW_VERSION INSTALLED COMPONENTS SERVICES EXTRA INSTALL_DATE; do
        printf '%s=%s\n' "$k" "${SCROW_STATE_VARS[$k]:-}"
    done > "$SCROW_STATE_FILE.tmp"
    mv -f "$SCROW_STATE_FILE.tmp" "$SCROW_STATE_FILE"
    scrow_log "state written"
}

scrow_state_get() {
    printf '%s' "${SCROW_STATE_VARS[$1]:-}"
}

scrow_state_set() {
    SCROW_STATE_VARS[$1]="$2"
    scrow_state_write
    scrow_log "state: $1=$2"
}

scrow_state_components() {
    printf '%s\n' ${SCROW_STATE_VARS[COMPONENTS]:-} | sed '/^$/d'
}

# Add components (names) to the installed set, deduplicating.
scrow_state_add_components() {
    local current="${SCROW_STATE_VARS[COMPONENTS]:-}" name
    for name in "$@"; do
        [[ " $current " == *" $name "* ]] || current="$current $name"
    done
    current="$(printf '%s' "$current" | tr -s ' ' | sed 's/^ *//; s/ *$//')"
    SCROW_STATE_VARS[COMPONENTS]="$current"
    scrow_state_write
}

# Remove components (names) from the installed set.
scrow_state_remove_components() {
    local current="${SCROW_STATE_VARS[COMPONENTS]:-}" name
    for name in "$@"; do
        current="${current// $name/}"
        current="$(printf '%s\n' $current | sed '/^$/d' | tr '\n' ' ' | sed 's/ $//')"
    done
    SCROW_STATE_VARS[COMPONENTS]="$current"
    scrow_state_write
}

scrow_state_services() {
    printf '%s\n' ${SCROW_STATE_VARS[SERVICES]:-} | sed '/^$/d'
}

scrow_state_add_service() {
    local svc="$1" current="${SCROW_STATE_VARS[SERVICES]:-}"
    [[ " $current " == *" $svc "* ]] || SCROW_STATE_VARS[SERVICES]="$current $svc"
    SCROW_STATE_VARS[SERVICES]="$(printf '%s' "${SCROW_STATE_VARS[SERVICES]}" | sed 's/^ *//; s/ *$//')"
    scrow_state_write
}
