#!/usr/bin/env bash
# =============================================================================
# SCROW — engine (install / refresh / upgrade / repair / reset / remove)
# =============================================================================

# --- repository (bootstrap mode) ----------------------------------------------
# The one-line bootstrap ships only the self-contained installer core. The full
# repository — the dotfiles, themes, cursors and binaries a component installs —
# is fetched here, lazily, the first time an operation needs it, as ONE tarball
# with real progress. After the first fetch this is a no-op, and everything
# (SCROW_REPO, manifest, SHA, deploy) works exactly as in a manual clone.
#
# A bootstrap install has no .git, so "Update SCROW" re-fetches the same tarball
# and merges it over the existing tree (see scrow_repo_fetch). Manual clones are
# left untouched: they keep .git and update with git pull.
scrow_repo_present() {
    [[ -d "$SCROW_REPO/.config" ]]
}

# Download + verify + extract + merge the full repository tarball. Used by
# scrow_ensure_repo (first run) and scrow_engine_update (re-fetch). Real
# progress via scrow_progress_run, bounded timeouts, fail-fast with the log
# path, and no duplicate download paths.
scrow_repo_fetch() {
    local fetch="$SCROW_STATE_DIR/repo-fetch"
    local archive="$SCROW_STATE_DIR/scrow-repo.tar.gz"
    rm -rf "$fetch"
    mkdir -p "$fetch"

    echo "  ${C_DIM}Downloading repository…${C_RESET}"
    if ! scrow_progress_run "Fetching SCROW files" curl -fL --progress-bar --proto '=https' \
            --connect-timeout 15 --max-time 300 --retry 3 --retry-delay 2 --retry-all-errors \
            -o "$archive" "$SCROW_TARBALL_URL"; then
        rm -f "$archive"
        printf '\r\033[K'
        echo "  ${C_ERR}Could not download SCROW component files.${C_RESET}"
        echo "  ${C_DIM}Check the network and try again. Details: $SCROW_CURRENT_LOG${C_RESET}"
        return 1
    fi
    printf '\r\033[K'
    if ! gzip -t "$archive" 2>/dev/null; then
        rm -f "$archive"
        echo "  ${C_ERR}Downloaded SCROW files are incomplete or corrupt.${C_RESET}"
        return 1
    fi
    echo "  ${C_DIM}Extracting SCROW files…${C_RESET}"
    if ! tar -xzf "$archive" --strip-components=1 -C "$fetch"; then
        rm -rf "$fetch" "$archive"
        echo "  ${C_ERR}Could not unpack SCROW component files.${C_RESET}"
        return 1
    fi
    rm -f "$archive"

    if [[ ! -d "$fetch/.config" ]]; then
        rm -rf "$fetch"
        echo "  ${C_ERR}SCROW component files could not be fetched.${C_RESET}"
        echo "  ${C_DIM}Details: $SCROW_CURRENT_LOG${C_RESET}"
        return 1
    fi

    # Merge the fetched repository into the installer tree so the layout is
    # identical to a manual clone. cp -a merges directories and overwrites the
    # (identical) installer core files.
    if ! cp -a "$fetch"/. "$SCROW_REPO"/ 2>/dev/null; then
        rm -rf "$fetch"
        echo "  ${C_ERR}Could not place SCROW component files.${C_RESET}"
        return 1
    fi
    rm -rf "$fetch"
    scrow_log "repository fetched into $SCROW_REPO"
    echo "  ${C_OK}SCROW component files ready.${C_RESET}"
}

scrow_ensure_repo() {
    scrow_repo_present && return 0
    if [[ "$SCROW_DRY_RUN" == "1" ]]; then
        echo "  [dry-run] fetch SCROW repository into $SCROW_REPO"
        return 0
    fi
    echo
    echo "  ${C_ACCENT}SCROW files${C_RESET}"
    echo "  ${C_DIM}Fetching SCROW component files (first run only)…${C_RESET}"
    scrow_repo_fetch
}

# --- install -----------------------------------------------------------------
# Plan resolution: resolve the dependency graph ONCE into an ordered install
# plan (dependencies before dependents) so every component is processed exactly
# once — dependency installs are never repeated in the main loop.
declare -a SCROW_PLAN=()
declare -A SCROW_PLAN_SEEN=() SCROW_PLAN_STATUS=() SCROW_PLAN_REASON=()

scrow_plan_resolve() {
    SCROW_PLAN=()
    SCROW_PLAN_SEEN=()
    SCROW_PLAN_STATUS=()
    SCROW_PLAN_REASON=()
    local name
    for name in "$@"; do
        [[ -n "$name" ]] || continue
        scrow_plan_add "$name"
    done
}

scrow_plan_add() {
    local name="$1"
    [[ -n "${SCROW_PLAN_SEEN[$name]:-}" ]] && return 0
    SCROW_PLAN_SEEN[$name]=1
    if ! scrow_component_exists "$name"; then
        SCROW_PLAN_STATUS[$name]="failed"
        SCROW_PLAN_REASON[$name]="unknown component"
        echo "  ${C_WARN}Unknown component: $name${C_RESET}"
        return 0
    fi
    if scrow_config_component_skipped "$name"; then
        SCROW_PLAN_STATUS[$name]="skipped"
        SCROW_PLAN_REASON[$name]="disabled in config (COMPONENTS_SKIP)"
        return 0
    fi
    if scrow_component_installed "$name"; then
        SCROW_PLAN_STATUS[$name]="configured"
        SCROW_PLAN_REASON[$name]="already installed"
        return 0
    fi
    local dep
    for dep in $(scrow_component_needs "$name"); do
        scrow_plan_add "$dep"
    done
    SCROW_PLAN+=("$name")
    SCROW_PLAN_STATUS[$name]="pending"
}

# scrow_engine_install [names...]  (defaults to all uninstalled components)
scrow_engine_install() {
    local -a wanted=("$@")
    if [[ ${#wanted[@]} -eq 0 ]]; then
        local name
        for name in $(scrow_component_names); do
            scrow_component_installed "$name" || wanted+=("$name")
        done
    fi

    scrow_plan_resolve "${wanted[@]}"

    local -a todo=()
    local name
    for name in "${SCROW_PLAN[@]}"; do todo+=("$name"); done

    if [[ ${#todo[@]} -eq 0 ]]; then
        # Nothing new to install. Converge any already-configured components
        # that were explicitly requested so a re-run stays in sync cheaply.
        local -i any=0 rc=0
        for name in "${wanted[@]}"; do
            if [[ "${SCROW_PLAN_STATUS[$name]:-}" == "configured" ]]; then
                scrow_converge_component "$name" || rc=1
                any=1
            fi
        done
        if (( any == 0 )); then
            echo "  ${C_OK}Nothing to install — all components already present.${C_RESET}"
            return 0
        fi
        return $rc
    fi

    echo
    echo "  ${C_ACCENT}SCROW Install${C_RESET}"
    echo "  ${C_DIM}Installing: ${todo[*]}${C_RESET}"
    echo

    scrow_ensure_repo || return 1
    scrow_backup_autobackup

    local -i failures=0
    for name in "${todo[@]}"; do
        scrow_install_component "$name" || failures+=1
    done

    # Keep explicitly-requested already-configured components in sync.
    for name in "${wanted[@]}"; do
        [[ "${SCROW_PLAN_STATUS[$name]:-}" == "configured" ]] || continue
        scrow_converge_component "$name" || failures+=1
    done

    if ! scrow_install_command; then
        SCROW_PLAN_STATUS[scrow]="failed"
        SCROW_PLAN_REASON[scrow]="command symlink failed"
        failures+=1
    fi

    local -i configured=0 skipped=0 failed_names=0 total=0
    local n
    local -a all_names=( "${wanted[@]}" )
    for n in "${todo[@]}"; do
        case " ${all_names[*]} " in *" $n "*) continue ;; esac
        all_names+=( "$n" )
    done
    for n in "${all_names[@]}"; do
        total+=1
        case "${SCROW_PLAN_STATUS[$n]:-}" in
            configured) configured+=1 ;;
            skipped)    skipped+=1 ;;
            failed)     failed_names+=1 ;;
        esac
    done
    (( failures > 0 )) && failed_names=$failures

    echo
    if (( failed_names > 0 )); then
        echo "  ${C_ERR}${configured}/${total} components configured${C_RESET}"
        echo "  ${C_ERR}${failed_names} failed:${C_RESET}"
        for n in "${all_names[@]}"; do
            [[ "${SCROW_PLAN_STATUS[$n]:-}" == "failed" ]] || continue
            echo "    ${C_ERR}✗ ${n} — ${SCROW_PLAN_REASON[$n]:-unknown reason}${C_RESET}"
        done
        [[ "${SCROW_PLAN_STATUS[scrow]:-}" == "failed" ]] && \
            echo "    ${C_ERR}✗ scrow — ${SCROW_PLAN_REASON[scrow]}${C_RESET}"
        (( skipped > 0 )) && {
            echo "  ${C_DIM}${skipped} skipped:${C_RESET}"
            for n in "${all_names[@]}"; do
                [[ "${SCROW_PLAN_STATUS[$n]:-}" == "skipped" ]] || continue
                echo "    ${C_DIM}− ${n} — ${SCROW_PLAN_REASON[$n]:-}${C_RESET}"
            done
        }
        echo "  ${C_DIM}Log: $SCROW_CURRENT_LOG${C_RESET}"
        return 1
    fi

    scrow_state_set INSTALLED 1
    scrow_state_set INSTALL_DATE "$(date '+%Y-%m-%d %H:%M:%S')"
    scrow_state_set SCROW_VERSION "$SCROW_VERSION"
    echo "  ${C_OK}${configured}/${total} components configured successfully${C_RESET}"
    if (( skipped > 0 )); then
        echo "  ${C_DIM}${skipped} skipped (optional post-install not enabled):${C_RESET}"
        for n in "${all_names[@]}"; do
            [[ "${SCROW_PLAN_STATUS[$n]:-}" == "skipped" ]] || continue
            echo "    ${C_DIM}− ${n} — ${SCROW_PLAN_REASON[$n]:-}${C_RESET}"
        done
    fi
    echo "  ${C_OK}Install complete.${C_RESET}"
    echo "  ${C_DIM}Log: $SCROW_CURRENT_LOG${C_RESET}"
    return 0
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
    mkdir -p "$HOME/.local/bin" 2>/dev/null || return 1
    ln -sfn "$launcher" "$HOME/.local/bin/scrow" || return 1
    echo "  ${C_OK}scrow command installed → $HOME/.local/bin/scrow${C_RESET}"
    if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        echo "  ${C_DIM}Note: add $HOME/.local/bin to your PATH to run \`scrow\` from any directory.${C_RESET}"
    fi
}

# Install a single component: deps are already ordered by the plan, so this is
# strictly packages → deploy → ownership → post → validate. A component is only
# recorded as configured after EVERY required stage succeeds.
scrow_install_component() {
    local name="$1"
    local -a steps=()
    local -i rc=0

    echo
    echo "  ${C_ACCENT}› ${name}${C_RESET}"
    SCROW_PLAN_STATUS[$name]="installing"

    scrow_need_root

    # AUR helper required for any AUR packages.
    if [[ -n "$(scrow_component_aur "$name")" ]]; then
        echo "  ${C_DIM}  Installing packages...${C_RESET}"
        if ! scrow_pm_install_paru; then
            scrow_fail_component "$name" "paru (AUR helper) installation failed"
            return 1
        fi
    fi

    echo "  ${C_DIM}  Installing packages...${C_RESET}"
    if ! scrow_install_packages "$name"; then
        scrow_fail_component "$name" "package installation failed"
        return 1
    fi
    steps+=(packages)

    echo "  ${C_DIM}  Deploying configuration...${C_RESET}"
    if ! scrow_deploy_component "$name"; then
        scrow_fail_component "$name" "configuration deployment failed"
        return 1
    fi
    if ! scrow_manifest_build "$name"; then
        scrow_fail_component "$name" "ownership recording failed"
        return 1
    fi
    steps+=(config)

    SCROW_POST_SERVICES=0
    echo "  ${C_DIM}  Applying post-install...${C_RESET}"
    scrow_component_post "$name"
    rc=$?
    if (( rc == 2 )); then
        SCROW_PLAN_STATUS[$name]="skipped"
        SCROW_PLAN_REASON[$name]="optional post-install not enabled"
        echo "  ${C_WARN}  − ${name} — skipped: optional post-install not enabled${C_RESET}"
        return 0
    elif (( rc != 0 )); then
        scrow_fail_component "$name" "post-install failed"
        scrow_manifest_remove_component "$name"
        return 1
    fi
    steps+=(post)
    (( SCROW_POST_SERVICES == 1 )) && steps+=(services)

    echo "  ${C_DIM}  Validating...${C_RESET}"
    if ! scrow_component_validate "$name"; then
        scrow_fail_component "$name" "validation failed — declared files not deployed"
        scrow_manifest_remove_component "$name"
        return 1
    fi
    steps+=(validate)

    scrow_state_add_components "$name"
    scrow_log "installed component: $name"
    SCROW_PLAN_STATUS[$name]="configured"
    SCROW_PLAN_REASON[$name]=""
    printf '  %s %-14s %s\n' "${C_OK}✓${C_RESET}" "$name" "${steps[*]// / · }"
    return 0
}

scrow_fail_component() {
    local name="$1" reason="$2"
    SCROW_PLAN_STATUS[$name]="failed"
    SCROW_PLAN_REASON[$name]="$reason"
    echo "  ${C_ERR}✗ ${name} — ${reason}${C_RESET}"
    scrow_log "FAILED component: $name ($reason)"
}

# Install every declared package (official then AUR) for a component. Returns
# 1 as soon as a package installation fails — a component with missing
# packages is incomplete and must not be marked configured.
declare -A SCROW_PLAN_PKGS=()

scrow_install_packages() {
    local name="$1" pkg
    for pkg in $(scrow_component_packages "$name"); do
        scrow_config_pkg_skipped "$pkg" && continue
        if [[ -n "${SCROW_PLAN_PKGS[$pkg]:-}" ]]; then
            continue
        fi
        scrow_pm_install "$pkg" || return 1
        SCROW_PLAN_PKGS[$pkg]=1
    done
    for pkg in $(scrow_component_aur "$name"); do
        scrow_config_pkg_skipped "$pkg" && continue
        if [[ -n "${SCROW_PLAN_PKGS[$pkg]:-}" ]]; then
            continue
        fi
        scrow_pm_install "$pkg" || return 1
        SCROW_PLAN_PKGS[$pkg]=1
    done
}

# Validate that every declared path of a component is actually present on the
# system after deployment. Returns 1 when anything declared is missing.
scrow_component_validate() {
    local name="$1" p t f rel
    local -i rc=0
    [[ "$SCROW_DRY_RUN" == "1" ]] && return 0
    for p in $(scrow_component_paths "$name"); do
        [[ ! -e "$SCROW_REPO/$p" && ! -L "$SCROW_REPO/$p" ]] && continue
        t="$(scrow_target "$p")"
        if [[ -d "$SCROW_REPO/$p" ]]; then
            if [[ ! -d "$t" ]]; then
                echo "  ${C_ERR}      missing directory: $p${C_RESET}"
                rc=1
                continue
            fi
            while IFS= read -r f; do
                [[ -n "$f" ]] || continue
                rel="${f#$p/}"
                [[ -e "$t/$rel" || -L "$t/$rel" ]] || {
                    echo "  ${C_ERR}      missing file: $p/$rel${C_RESET}"
                    rc=1
                }
            done < <(scrow_repo_files "$p")
        elif [[ -L "$SCROW_REPO/$p" ]]; then
            [[ -L "$t" ]] || { echo "  ${C_ERR}      missing symlink: $p${C_RESET}"; rc=1; }
        else
            [[ -e "$t" ]] || { echo "  ${C_ERR}      missing file: $p${C_RESET}"; rc=1; }
        fi
    done
    return $rc
}

# Deploy any repo files of an already-configured component that are missing or
# out of sync with the repository. Never touches packages or services — used to
# converge configured components cheaply during re-install / update.
scrow_converge_component() {
    local name="$1" path full t
    local -i updated=0 rc=0
    for path in $(scrow_component_paths "$name"); do
        [[ ! -e "$SCROW_REPO/$path" && ! -L "$SCROW_REPO/$path" ]] && continue
        while IFS= read -r full; do
            [[ -n "$full" ]] || continue
            t="$(scrow_target "$full")"
            if [[ -L "$SCROW_REPO/$full" ]]; then
                [[ -L "$t" && "$(readlink "$t")" == "$(readlink "$SCROW_REPO/$full")" ]] && continue
            elif [[ -e "$t" ]]; then
                continue
            fi
            scrow_backup_existing "$full" "$name"
            scrow_deploy_path "$full" || rc=1
            updated+=1
        done < <(scrow_repo_files "$path")
    done
    (( updated > 0 )) && echo "  ${C_DIM}→ ${name}: ${updated} file(s) refreshed${C_RESET}"
    scrow_manifest_build "$name"
    return $rc
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

    scrow_ensure_repo || return 1

    scrow_backup_autobackup

    scrow_manifest_index_load
    scrow_sha_cache_load
    scrow_build_synced_map

    local name path
    local -i failed=0
    for name in "${names[@]}"; do
        scrow_component_exists "$name" || { echo "  ${C_WARN}Unknown component: $name${C_RESET}"; continue; }
        echo "  ${C_ACCENT}› ${name}${C_RESET}"
        for path in $(scrow_component_paths "$name"); do
            [[ ! -e "$SCROW_REPO/$path" && ! -L "$SCROW_REPO/$path" ]] && continue
            scrow_refresh_path "$path" || failed=1
        done
    done
    scrow_manifest_rebuild "${names[@]}"
    echo
    if (( failed != 0 )); then
        echo "  ${C_ERR}Refresh did not complete — see the log.${C_RESET}"
        return 1
    fi
    echo "  ${C_OK}Refresh complete.${C_RESET}"
}

scrow_refresh_path() {
    local path="$1" file full
    local -a files=()
    while IFS= read -r file; do
        [[ -n "$file" ]] && files+=("$file")
    done < <(scrow_repo_files "$path")

    local -i updated=0 failed=0
    if [[ -d "$SCROW_REPO/$path" ]]; then
        for full in "${files[@]}"; do
            [[ -n "${SCROW_SYNCED[$full]:-}" ]] && continue
            updated+=1
            if [[ "$SCROW_DRY_RUN" == "1" ]]; then
                continue
            fi
            scrow_backup_existing "$full" "$(scrow_manifest_owner "$full")"
            scrow_deploy_path "$full" || failed=1
        done
    else
        [[ -n "${SCROW_SYNCED[$path]:-}" ]] && return 0
        updated=1
        [[ "$SCROW_DRY_RUN" == "1" ]] || {
            scrow_backup_existing "$path" ""
            scrow_deploy_path "$path" || failed=1
        }
    fi
    if (( updated > 0 )); then
        echo "  ${C_DIM}→ $path: $updated file(s) to update${C_RESET}"
    fi
    return $failed
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
    scrow_ensure_repo || return 1
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
# Restore the COMPLETE state of every installed component: missing packages,
# missing/modified/newly-added files, then re-run post-install (caches,
# generated config, services) for anything that changed. Reports failures
# instead of claiming success.
scrow_engine_repair() {
    echo
    echo "  ${C_ACCENT}SCROW Repair${C_RESET}"

    scrow_ensure_repo || return 1
    scrow_backup_autobackup

    local -a names=( $(scrow_state_components) )
    if [[ ${#names[@]} -eq 0 ]]; then
        echo "  ${C_WARN}Nothing installed to repair.${C_RESET}"
        return 0
    fi

    scrow_manifest_index_load
    scrow_sha_cache_load
    scrow_build_synced_map

    local name path full t
    local -i failed=0
    local prc
    for name in "${names[@]}"; do
        scrow_component_exists "$name" || { echo "  ${C_WARN}Unknown component: $name${C_RESET}"; continue; }
        echo "  ${C_ACCENT}› ${name}${C_RESET}"

        scrow_need_root

        echo "  ${C_DIM}  Checking packages…${C_RESET}"
        if ! scrow_install_packages "$name"; then
            echo "  ${C_ERR}  ✗ ${name} — package restoration failed${C_RESET}"
            failed=1
            continue
        fi

        local -i comp_changed=0
        for path in $(scrow_component_paths "$name"); do
            [[ ! -e "$SCROW_REPO/$path" && ! -L "$SCROW_REPO/$path" ]] && continue
            if [[ -d "$SCROW_REPO/$path" ]]; then
                while IFS= read -r full; do
                    [[ -n "$full" ]] || continue
                    [[ -n "${SCROW_SYNCED[$full]:-}" ]] && continue
                    comp_changed=1
                    [[ "$SCROW_DRY_RUN" == "1" ]] || {
                        scrow_backup_existing "$full" "$name"
                        scrow_deploy_path "$full" || failed=1
                    }
                done < <(scrow_repo_files "$path")
            else
                [[ -n "${SCROW_SYNCED[$path]:-}" ]] && continue
                comp_changed=1
                [[ "$SCROW_DRY_RUN" == "1" ]] || {
                    scrow_backup_existing "$path" "$name"
                    scrow_deploy_path "$path" || failed=1
                }
            fi
        done

        if (( comp_changed == 1 )); then
            echo "  ${C_DIM}  files restored — re-applying post-install…${C_RESET}"
            SCROW_POST_SERVICES=0
            scrow_component_post "$name"
            prc=$?
            if (( prc == 2 )); then
                echo "  ${C_WARN}  (skipped) optional post-install not enabled${C_RESET}"
            elif (( prc != 0 )); then
                echo "  ${C_ERR}  ✗ ${name} — post-install failed during repair${C_RESET}"
                failed=1
            fi
        fi
        scrow_manifest_build "$name"
    done

    echo "  ${C_DIM}Ensuring required services…${C_RESET}"
    scrow_services_apply || { echo "  ${C_ERR}service configuration failed${C_RESET}"; failed=1; }

    scrow_manifest_rebuild "${names[@]}"

    echo
    if (( failed != 0 )); then
        echo "  ${C_ERR}Repair did not complete — see the log.${C_RESET}"
        return 1
    fi
    echo "  ${C_OK}Repair complete — components are back to the official state.${C_RESET}"
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
