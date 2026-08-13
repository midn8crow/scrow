#!/usr/bin/env bash
# =============================================================================
# SCROW — engine (install / refresh / upgrade / repair / reset / remove)
# =============================================================================

# --- install -----------------------------------------------------------------
# scrow_engine_install [names...]  (defaults to all uninstalled components)
scrow_engine_install() {
    local -a wanted=("$@")
    if [[ ${#wanted[@]} -eq 0 ]]; then
        local name
        for name in $(scrow_component_names); do
            scrow_component_installed "$name" || wanted+=("$name")
        done
    fi
    if [[ ${#wanted[@]} -eq 0 ]]; then
        echo "  ${C_OK}Nothing to install — all components already present.${C_RESET}"
        return 0
    fi

    echo
    echo "  ${C_ACCENT}SCROW Install${C_RESET}"
    echo "  ${C_DIM}Installing: ${wanted[*]}${C_RESET}"
    echo

    scrow_backup_autobackup

    local name
    for name in "${wanted[@]}"; do
        scrow_config_component_skipped "$name" && { echo "  ${C_DIM}Skip $name (config)${C_RESET}"; continue; }
        scrow_install_component "$name"
    done

    scrow_services_apply
    scrow_install_command
    scrow_state_set INSTALLED 1
    scrow_state_set INSTALL_DATE "$(date '+%Y-%m-%d %H:%M:%S')"
    scrow_state_set SCROW_VERSION "$SCROW_VERSION"
    echo
    echo "  ${C_OK}Install complete.${C_RESET}"
    echo "  ${C_DIM}Log: $SCROW_CURRENT_LOG${C_RESET}"
}

# Make `scrow` available from anywhere: symlink the running launcher into
# ~/.local/bin. A symlink (not a copy) keeps the launcher's SCROW_DIR
# resolving to the real installer tree, so the modules it sources stay
# correct regardless of where the repository lives.
scrow_install_command() {
    local launcher="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/scrow"
    if [[ "$SCROW_DRY_RUN" == "1" ]]; then
        echo "  [dry-run] ln -sfn $launcher $HOME/.local/bin/scrow"
        return 0
    fi
    mkdir -p "$HOME/.local/bin"
    ln -sfn "$launcher" "$HOME/.local/bin/scrow"
    echo "  ${C_OK}scrow command installed → $HOME/.local/bin/scrow${C_RESET}"
    if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        echo "  ${C_DIM}Note: add $HOME/.local/bin to your PATH to run \`scrow\` from any directory.${C_RESET}"
    fi
}

# Install a single component: deps → packages → deploy → manifest → post.
scrow_install_component() {
    local name="$1"
    echo
    echo "  ${C_ACCENT}› ${name}${C_RESET}"

    scrow_need_root

    # AUR helper required for any AUR packages.
    if [[ -n "$(scrow_component_aur "$name")" ]]; then
        scrow_pm_install_paru
    fi

    scrow_install_deps "$name"
    scrow_install_packages "$name"
    scrow_install_files "$name"
}

scrow_install_deps() {
    local name="$1" dep
    for dep in $(scrow_component_needs "$name"); do
        if ! scrow_component_installed "$dep" && ! scrow_config_component_skipped "$dep"; then
            echo "  ${C_DIM}dependency: $dep${C_RESET}"
            scrow_install_component "$dep"
        fi
    done
}

scrow_install_packages() {
    local name="$1" pkg
    for pkg in $(scrow_component_packages "$name"); do
        scrow_config_pkg_skipped "$pkg" && continue
        scrow_pm_install "$pkg" || return 1
    done
    for pkg in $(scrow_component_aur "$name"); do
        scrow_config_pkg_skipped "$pkg" && continue
        scrow_pm_install "$pkg" || return 1
    done
}

scrow_install_files() {
    local name="$1"
    scrow_deploy_component "$name"
    scrow_manifest_build "$name"
    scrow_component_post "$name"
    scrow_state_add_components "$name"
    scrow_log "installed component: $name"
}

# --- refresh ---------------------------------------------------------------
# Re-check every managed file of the given components (default: all installed)
# and deploy any that are missing or changed since the manifest was written.
declare -A SCROW_SYNCED=()

# One pass over the manifest building a "already in sync" map, so the per-file
# refresh loop is a single associative lookup instead of re-parsing TSV rows.
# "In sync" is decided against what is LIVE on disk (current manifest hashes
# can be stale), so refresh actually re-deploys user-modified files.
scrow_build_synced_map() {
    SCROW_SYNCED=()
    local line rel src t
    scrow_target_sha_load
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        scrow_tsv "$line"
        rel="${SCROW_MF[0]}"
        if [[ "${SCROW_MF[2]}" == "l" ]]; then
            t="$(scrow_target "$rel")"
            [[ -L "$t" && "$(readlink "$t" 2>/dev/null)" == "${SCROW_MF[3]}" ]] && SCROW_SYNCED["$rel"]=1
        else
            src="${SCROW_MF[3]#@}"
            [[ -z "$src" || "$src" == "${SCROW_MF[3]}" ]] && src="$rel"
            scrow_sha_cache_get "$src"
            t="$(scrow_target "$rel")"
            if [[ -n "$SCROW_SHA_CACHE_RET" && ! -L "$t" && -e "$t" ]]; then
                scrow_target_sha_get "$t"
                [[ "$SCROW_TARGET_SHA_RET" == "$SCROW_SHA_CACHE_RET" ]] && SCROW_SYNCED["$rel"]=1
            fi
        fi
    done < <(scrow_manifest_lines)
}

scrow_engine_refresh() {
    local -a names=("$@")
    [[ ${#names[@]} -eq 0 ]] && names=( $(scrow_state_components) )
    echo
    echo "  ${C_ACCENT}SCROW Refresh${C_RESET}"
    echo "  ${C_DIM}Checking: ${names[*]}${C_RESET}"
    echo

    scrow_backup_autobackup

    scrow_manifest_index_load
    scrow_sha_cache_load
    scrow_build_synced_map

    local name path
    for name in "${names[@]}"; do
        scrow_component_exists "$name" || { echo "  ${C_WARN}Unknown component: $name${C_RESET}"; continue; }
        echo "  ${C_ACCENT}› ${name}${C_RESET}"
        for path in $(scrow_component_paths "$name"); do
            [[ ! -e "$SCROW_REPO/$path" && ! -L "$SCROW_REPO/$path" ]] && continue
            scrow_refresh_path "$path"
        done
    done
    scrow_manifest_rebuild "${names[@]}"
    echo
    echo "  ${C_OK}Refresh complete.${C_RESET}"
}

scrow_refresh_path() {
    local path="$1" file full
    local -a files=()
    while IFS= read -r file; do
        [[ -n "$file" ]] && files+=("$file")
    done < <(scrow_repo_files "$path")

    local -i updated=0
    if [[ -d "$SCROW_REPO/$path" ]]; then
        for full in "${files[@]}"; do
            [[ -n "${SCROW_SYNCED[$full]:-}" ]] && continue
            updated+=1
            if [[ "$SCROW_DRY_RUN" == "1" ]]; then
                continue
            fi
            scrow_backup_existing "$full" "$(scrow_manifest_owner "$full")"
            scrow_deploy_path "$full"
        done
    else
        [[ -n "${SCROW_SYNCED[$path]:-}" ]] && return
        updated=1
        [[ "$SCROW_DRY_RUN" == "1" ]] || {
            scrow_backup_existing "$path" ""
            scrow_deploy_path "$path"
        }
    fi
    if (( updated > 0 )); then
        echo "  ${C_DIM}→ $path: $updated file(s) to update${C_RESET}"
    fi
}

scrow_manifest_owner() {
    local rel="$1" line
    line="${SCROW_MANIFEST_INDEX[$rel]:-}"
    if [[ -z "$line" ]]; then
        line="$(scrow_manifest_lines | awk -F'\t' -v p="$rel" '$1 == p { print; exit }')"
    fi
    [[ -n "$line" ]] && printf '%s' "${line##*$'\t'}"
}

# --- upgrade ----------------------------------------------------------------
# System packages, AUR, then rebuild the manifest (official hashes change).
scrow_engine_upgrade() {
    echo
    echo "  ${C_ACCENT}SCROW Upgrade${C_RESET}"
    [[ "$SCROW_DRY_RUN" == "1" ]] && { echo "  [dry-run] pacman -Syu + paru -Sua"; return 0; }
    scrow_need_root
    scrow_run_sudo "system upgrade" pacman -Syu --noconfirm || return 1
    if command -v paru >/dev/null 2>&1; then
        scrow_run "aur upgrade" paru -Sua --noconfirm || return 1
    fi
    scrow_pm_cache
    echo "  ${C_DIM}Updating manifest hashes…${C_RESET}"
    scrow_manifest_rebuild
    echo
    echo "  ${C_OK}Upgrade complete.${C_RESET}"
}

# --- repair -----------------------------------------------------------------
# Restore managed files to the official repository state.
scrow_engine_repair() {
    echo
    echo "  ${C_ACCENT}SCROW Repair${C_RESET}"

    scrow_backup_autobackup

    local line rel status
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        rel="${line%%$'\t'*}"
        status="${line##*$'\t'}"
        echo "  ${C_DIM}$status: $rel${C_RESET}"
        scrow_backup_existing "$rel" "repair"
        scrow_deploy_path "$rel"
    done < <(scrow_manifest_out_of_sync)
    scrow_manifest_rebuild
    echo
    echo "  ${C_OK}Repair complete.${C_RESET}"
}

# --- restore ----------------------------------------------------------------
# Restore managed files from an automatic backup (distinct from RESET, which
# removes everything, and REPAIR, which restores the official repo state).
scrow_engine_restore() {
    echo
    echo "  ${C_ACCENT}SCROW Restore (from backup)${C_RESET}"
    local -a backups=()
    local b
    while IFS= read -r b; do
        [[ -n "$b" ]] && backups+=("$b")
    done < <(scrow_backup_available)
    if [[ ${#backups[@]} -eq 0 ]]; then
        echo "  ${C_WARN}No automatic backups found in $(scrow_backup_dir)/AUTO_BACKUP.${C_RESET}"
        return 1
    fi
    echo
    echo "  ${C_DIM}Available backups (newest first):${C_RESET}"
    local -i i
    for i in "${!backups[@]}"; do
        printf '  %2d)  %s\n' "$((i + 1))" "${backups[$i]}"
    done
    echo
    local choice="${1:-}"
    if [[ -z "$choice" ]]; then
        read -r -p "  Restore which backup? [1-${#backups[@]}] " choice || choice="1"
    fi
    if [[ ! "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#backups[@]} )); then
        echo "  ${C_WARN}Invalid selection.${C_RESET}"
        return 1
    fi
    local ts="${backups[$((choice - 1))]}"
    local root
    root="$(scrow_backup_dir)/AUTO_BACKUP/$ts"
    echo "  ${C_DIM}Restoring from $ts …${C_RESET}"
    if [[ "$SCROW_DRY_RUN" == "1" ]]; then
        echo "  [dry-run] restore all files from $root"
        return 0
    fi
    [[ -f "$root/manifest" ]] || { echo "  ${C_WARN}Backup manifest missing in $root${C_RESET}"; return 1; }
    local line rel src dest
    local -i restored=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        scrow_tsv "$line"
        rel="${SCROW_MF[0]}"
        src="$root/$rel"
        [[ ! -e "$src" && ! -L "$src" ]] && continue
        dest="$(scrow_target "$rel")"
        mkdir -p "$(dirname "$dest")"
        scrow_backup_existing "$rel" "pre-restore"
        if [[ -L "$src" ]]; then
            rm -f "$dest"
            ln -sfn "$(readlink "$src")" "$dest"
        elif [[ -d "$src" ]]; then
            cp -a "$src"/. "$dest"/ 2>/dev/null || true
        else
            cp -a "$src" "$dest" 2>/dev/null || true
        fi
        restored+=1
    done < "$root/manifest"
    scrow_manifest_rebuild
    echo "  ${C_OK}Restored $restored file(s) from $ts.${C_RESET}"
}

# --- reset ------------------------------------------------------------------
# Disable SCROW services, remove every managed path, drop manifest & state.
scrow_engine_reset() {
    echo
    echo "  ${C_ACCENT}SCROW Reset${C_RESET}"
    if [[ "${SCROW_ASSUME_YES:-0}" != "1" ]]; then
        read -r -p "  Remove ALL SCROW-managed files and configuration? [y/N] " answer
        [[ "$answer" =~ ^[yY]$ ]] || { echo "  ${C_DIM}Aborted.${C_RESET}"; return 1; }
    fi

    scrow_backup_autobackup

    local line rel dest
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        scrow_tsv "$line"
        rel="${SCROW_MF[0]}"
        dest="$(scrow_target "$rel")"
        [[ ! -e "$dest" && ! -L "$dest" ]] && continue
        if [[ "$SCROW_DRY_RUN" == "1" ]]; then
            echo "  [dry-run] remove: $rel"
        else
            rm -rf "$dest" 2>/dev/null || true
            echo "  ${C_DIM}removed: $rel${C_RESET}"
        fi
    done < <(scrow_manifest_lines)

    if [[ -L "$HOME/.local/bin/scrow" ]]; then
        if [[ "$SCROW_DRY_RUN" == "1" ]]; then
            echo "  [dry-run] remove: $HOME/.local/bin/scrow"
        else
            rm -f "$HOME/.local/bin/scrow"
            echo "  ${C_DIM}removed: $HOME/.local/bin/scrow${C_RESET}"
        fi
    fi

    scrow_services_disable_owned
    scrow_manifest_clear
    scrow_state_set INSTALLED 0
    scrow_state_set COMPONENTS ""
    scrow_state_set SERVICES ""
    scrow_state_set INSTALL_DATE ""
    echo
    echo "  ${C_OK}SCROW reset complete.${C_RESET}"
}

# --- remove component -------------------------------------------------------
scrow_engine_remove_component() {
    local name="$1"
    scrow_component_exists "$name" || { echo "  ${C_WARN}Unknown component: $name${C_RESET}"; return 1; }
    if [[ "${SCROW_ASSUME_YES:-0}" != "1" ]]; then
        read -r -p "  Remove component '$name' (files, not packages)? [y/N] " answer
        [[ "$answer" =~ ^[yY]$ ]] || { echo "  ${C_DIM}Aborted.${C_RESET}"; return 1; }
    fi

    scrow_backup_autobackup

    local line rel dest
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        scrow_tsv "$line"
        rel="${SCROW_MF[0]}"
        [[ "${SCROW_MF[6]}" != "$name" ]] && continue
        dest="$(scrow_target "$rel")"
        [[ ! -e "$dest" && ! -L "$dest" ]] && continue
        if [[ "$SCROW_DRY_RUN" == "1" ]]; then
            echo "  [dry-run] remove: $rel"
        else
            rm -rf "$dest" 2>/dev/null || true
            echo "  ${C_DIM}removed: $rel${C_RESET}"
        fi
    done < <(scrow_manifest_lines)

    scrow_manifest_rebuild
    scrow_state_remove_components "$name"
    echo
    echo "  ${C_OK}Component '$name' removed.${C_RESET}"
}
