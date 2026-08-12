#!/usr/bin/env bash
# =============================================================================
# SCROW - automatic backup system
# =============================================================================
# Backups are created automatically before any potentially destructive
# operation. They are stored under ~/.local/share/scrow/backups/.
#
# Layout of one backup:
#   info        metadata (date, reason, SCROW version)
#   manifest    copy of the manifest at backup time
#   state       copy of SCROW state
#   files/      user files (mirrors $HOME structure)
#   system/     system files (mirrors / structure)
#   symlinks    "relpath<TAB>target" for managed symlinks
# =============================================================================

SCROW_BACKUP_PATH=""

_scrow_backup_reason_slug() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/-\{2,\}/-/g; s/^-//; s/-$//'
}

scrow_backup_create() {
    # scrow_backup_create <reason>  -> creates a backup, sets $SCROW_BACKUP_PATH
    local reason="$1" dir
    mkdir -p "$SCROW_BACKUP_DIR"
    dir="$SCROW_BACKUP_DIR/$(date +%Y-%m-%d_%H%M%S)__$(_scrow_backup_reason_slug "$reason")"
    SCROW_BACKUP_PATH="$dir"

    ui_step "Creating automatic backup ($reason)…"
    scrow_log "backup create: $reason -> $dir"
    if [[ "$SCROW_DRY_RUN" == "1" ]]; then
        ui_dim "  [dry-run] would create backup at $dir"
        return 0
    fi

    mkdir -p "$dir/files" "$dir/system"

    {
        echo "DATE=$(date '+%Y-%m-%d %H:%M:%S')"
        echo "REASON=$reason"
        echo "SCROW_VERSION=$SCROW_VERSION"
        echo "SOURCE=$SCROW_REPO"
    } > "$dir/info"

    if [[ -f "$SCROW_MANIFEST" ]]; then
        cp -a "$SCROW_MANIFEST" "$dir/manifest"
    fi
    if [[ -f "$SCROW_STATE_FILE" ]]; then
        cp -a "$SCROW_STATE_FILE" "$dir/state"
    fi

    local nuser=0 nsystem=0 nsym=0 line rel scope type link target
    : > "$dir/symlinks"
    while IFS=$'\t' read -r rel scope type link _official _current _comp; do
        [[ -z "$rel" ]] && continue
        if [[ "$type" == "l" ]]; then
            printf '%s\t%s\n' "$rel" "$link" >> "$dir/symlinks"
            nsym=$(( nsym + 1 ))
        fi
        target="$(scrow_target "$rel")"
        [[ -e "$target" || -L "$target" ]] || continue
        if [[ "$scope" == "system" ]]; then
            if sudo -n true 2>/dev/null; then
                ( cd / && cp -a --parents "$rel" "$dir/system/" ) 2>/dev/null \
                    || { scrow_need_root; ( cd / && sudo cp -a --parents "$rel" "$dir/system/" ); }
            else
                ( cd / && cp -a --parents "$rel" "$dir/system/" ) 2>/dev/null
            fi
            nsystem=$(( nsystem + 1 ))
        else
            ( cd "$HOME" && cp -a --parents "$rel" "$dir/files/" ) 2>/dev/null
            nuser=$(( nuser + 1 ))
        fi
    done < <(scrow_manifest_lines)

    ui_ok "Backup saved → $dir"
    ui_dim "  files: $nuser   system: $nsystem   symlinks: $nsym"
    scrow_log "backup done: $dir (files=$nuser system=$nsystem symlinks=$nsym)"
}

scrow_backup_list() {
    # Populates SCROW_BACKUPS with "dir<TAB>date<TAB>reason"
    SCROW_BACKUPS=()
    local d date reason
    for d in "$SCROW_BACKUP_DIR"/*__*; do
        [[ -d "$d" ]] || continue
        reason="${d##*__}"
        date="${d##*/}"
        date="${date%%__*}"
        SCROW_BACKUPS+=("$d|$date|$reason")
    done
    [[ ${#SCROW_BACKUPS[@]} -gt 0 ]]
}

scrow_backup_verify() {
    # Returns 0 if the backup looks complete.
    local dir="$1"
    [[ -d "$dir" && -f "$dir/info" ]]
}

scrow_backup_restore() {
    # scrow_backup_restore <dir>
    local dir="$1"
    if ! scrow_backup_verify "$dir"; then
        ui_err "Backup is incomplete or missing: $dir"
        scrow_log "restore: invalid backup $dir"
        return 1
    fi
    scrow_log "restore start: $dir"
    if [[ "$SCROW_DRY_RUN" == "1" ]]; then
        ui_dim "  [dry-run] would restore from $dir"
        return 0
    fi

    if [[ -d "$dir/files" ]] && [[ -n "$(ls -A "$dir/files" 2>/dev/null)" ]]; then
        ui_step "Restoring configuration files…"
        ( cd "$HOME" && cp -a "$dir/files/." "$HOME/" )
    fi

    if [[ -d "$dir/system" ]] && [[ -n "$(ls -A "$dir/system" 2>/dev/null)" ]]; then
        ui_step "Restoring system files…"
        scrow_need_root
        scrow_log_tee "restore system files" sudo cp -a "$dir/system/." "/"
    fi

    if [[ -f "$dir/symlinks" ]]; then
        ui_step "Restoring symlinks…"
        local rel link target
        while IFS=$'\t' read -r rel link; do
            [[ -z "$rel" ]] && continue
            target="$(scrow_target "$rel")"
            mkdir -p "$(dirname "$target")"
            rm -f "$target"
            ln -sfn "$link" "$target"
        done < "$dir/symlinks"
    fi

    [[ -f "$dir/manifest" ]] && cp -a "$dir/manifest" "$SCROW_MANIFEST"
    [[ -f "$dir/state" ]] && cp -a "$dir/state" "$SCROW_STATE_FILE"

    scrow_log "restore complete: $dir"
}

scrow_backup_summary() {
    local dir="$1" date reason version nf ns nsy
    date=""; reason=""; version=""
    [[ -f "$dir/info" ]] && {
        . "$dir/info"
    }
    nf=$(find "$dir/files" -type f -o -type l 2>/dev/null | wc -l)
    ns=$(find "$dir/system" -type f -o -type l 2>/dev/null | wc -l)
    nsy=$(wc -l < "$dir/symlinks" 2>/dev/null | tr -d ' ')
    printf 'date=%s reason=%s version=%s files=%s system=%s symlinks=%s\n' \
        "$date" "$reason" "$version" "$nf" "$ns" "$nsy"
}
