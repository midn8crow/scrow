#!/usr/bin/env bash
# =============================================================================
# SCROW — restore backup
# =============================================================================
# Lists available backups and restores the user's choice.

action_restore() {
    printf "\n${C_BOLD}${C_CYN}  SCROW — Restore Backup${C_RST}\n\n"

    if [[ ! -d "$SCROW_BACKUP_DIR" ]] || [[ -z "$(ls -A "$SCROW_BACKUP_DIR" 2>/dev/null)" ]]; then
        printf "${C_WARN}  No backups found in: %s${C_RST}\n" "$SCROW_BACKUP_DIR"
        return 0
    fi

    # List backup sets (grouped by timestamp)
    printf "  Available backups:\n\n"
    local backups=()
    local i=0
    local f
    for f in "$SCROW_BACKUP_DIR"/*.bak; do
        [[ -f "$f" ]] || continue
        ((i++))
        backups+=("$f")
        printf "    %2d) %s\n" "$i" "$(basename "$f")"
    done

    if (( i == 0 )); then
        printf "${C_WARN}  No backup files found.${C_RST}\n"
        return 0
    fi

    printf "\n  Enter number to restore (or 'q' to cancel): "
    read -r choice

    [[ "$choice" == "q" || "$choice" == "Q" ]] && return 0

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#backups[@]} )); then
        printf "${C_ERR}  Invalid selection.${C_RST}\n"
        return 1
    fi

    local backup_file="${backups[$((choice-1))]}"
    # Extract original path from backup filename
    local orig_name
    orig_name="$(basename "$backup_file")"
    orig_name="${orig_name%%.*}"  # Remove first .timestamp.bak

    printf "\n  Restoring: %s\n" "$orig_name"

    # Find the matching deployed item and restore
    if [[ -d "$backup_file" ]]; then
        local dest="$HOME/$orig_name"
        mkdir -p "$dest"
        cp -a "$backup_file"/* "$dest/" 2>/dev/null || true
    elif [[ -f "$backup_file" ]]; then
        local dest="$HOME/$orig_name"
        mkdir -p "$(dirname "$dest")"
        cp -a "$backup_file" "$dest" 2>/dev/null || true
    fi

    printf "${C_OK}  Restored successfully.${C_RST}\n\n"
}
