#!/usr/bin/env bash
# =============================================================================
# SCROW — backups
# =============================================================================
# Before SCROW touches a managed path it copies the current state into the
# backup directory, which also stores a manifest snapshot so restores are
# possible after any change.
#
# Layout (kept compatible with earlier SCROW versions):
#   $BACKUP_DIR/
#     AUTO_BACKUP/YYYYMMDD_HHMMSS/manifest  + mirrored tree (full manifest
#                                            backup before install/update)
#     $SCROW_PACKAGE_DATE/_PRE/… + _POST/…  (per-package backups)
# =============================================================================

scrow_backup_dir() {
    if [[ -n "${SCROW_BACKUP_CUSTOM:-}" ]]; then
        printf '%s' "$SCROW_BACKUP_CUSTOM"
    else
        printf '%s' "$SCROW_BACKUP_DIR"
    fi
}

# Copy the current (soon-to-be-overwritten) state of a managed path to the
# backup dir. Returns early when nothing to back up.
#   scrow_backup_existing <rel> [label]
# label: sub-directory under $SCROW_PACKAGE_DATE grouping the backup
# (a component name, "repair", "pre-restore", …). Empty backs up to $DATE/.
scrow_backup_existing() {
    local rel="$1" label="${2:-}"
    [[ "$SCROW_DRY_RUN" == "1" ]] && { echo "  [dry-run] backup $rel"; return 0; }
    local dest src
    dest="$(scrow_target "$rel")"
    [[ ! -e "$dest" && ! -L "$dest" ]] && return 0
    src="$(scrow_backup_dir)/$SCROW_PACKAGE_DATE/$label"
    mkdir -p "$(dirname "$src/$rel")"
    # Best-effort safety copy — a failed backup must never abort the operation,
    # but it is reported so it is not silently lost.
    if ! cp -a "$dest" "$src/$rel" 2>/dev/null; then
        echo "  ${C_WARN}  ! could not back up $rel (continuing)${C_RESET}"
    fi
}

# Full-manifest backup before an install/update/reset run.
scrow_backup_autobackup() {
    [[ "${SCROW_AUTO_BACKUP:-1}" != "1" ]] && return 0
    local dest
    dest="$(scrow_backup_dir)/AUTO_BACKUP/$SCROW_PACKAGE_DATE"
    echo "  ${C_DIM}Backing up current state → $dest${C_RESET}"
    if [[ "$SCROW_DRY_RUN" == "1" ]]; then
        echo "  [dry-run] backup manifest + managed files to $dest"
        return 0
    fi
    mkdir -p "$dest"
    local -i failed=0
    cp -a "$SCROW_MANIFEST" "$dest/manifest" 2>/dev/null || failed+=1
    local line rel dest_path
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        scrow_tsv "$line"
        rel="${SCROW_MF[0]}"
        dest_path="$(scrow_target "$rel")"
        [[ ! -e "$dest_path" && ! -L "$dest_path" ]] && continue
        mkdir -p "$(dirname "$dest/$rel")"
        if [[ -L "$dest_path" ]]; then
            cp -aP "$dest_path" "$dest/$rel" 2>/dev/null || failed+=1
        elif [[ -d "$dest_path" ]]; then
            cp -a "$dest_path" "$dest/$rel" 2>/dev/null || failed+=1
        else
            cp -a "$dest_path" "$dest/$rel" 2>/dev/null || failed+=1
        fi
    done < <(scrow_manifest_lines)
    scrow_log "auto-backup complete ($dest)"
    if (( failed > 0 )); then
        echo "  ${C_WARN}  ${failed} file(s) could not be backed up (continuing)${C_RESET}"
    fi
}

# List available automatic backups, newest first.
scrow_backup_available() {
    ls -1t "$(scrow_backup_dir)/AUTO_BACKUP" 2>/dev/null
}
