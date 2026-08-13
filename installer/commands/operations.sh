#!/usr/bin/env bash
# =============================================================================
# SCROW - operations
# =============================================================================
# Full installation, custom installation, update, reset, restore, uninstall,
# verification and the `scrow` launcher install. Every operation that can
# overwrite, replace or remove configuration creates an automatic backup first.
# =============================================================================

SCROW_FLOW_COMPS=()
SCROW_PLAN_REPO=()
SCROW_PLAN_AUR=()
SCROW_APPLY_SECURITY=""
SCROW_SET_SHELL=""
SCROW_RESTORE_TARGET=""
SCROW_DISABLE_SERVICES=0

# -----------------------------------------------------------------------------
# Planning
# -----------------------------------------------------------------------------
scrow_check_dependencies() {
    local tool
    local missing=0
    for tool in bash git curl sudo pacman; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            ui_err "Missing required tool: $tool"
            missing=1
        fi
    done
    return $missing
}

scrow_preflight() {
    # Returns 0 when the system is ready. Runs before any change.
    scrow_detect_system || return 1
    scrow_check_dependencies || return 1
    scrow_detect_gpu
    scrow_detect_laptop
    return 0
}

# Fill SCROW_PLAN_REPO / SCROW_PLAN_AUR for the given components (plus GPU
# driver packages when a Hyprland session is included).
scrow_plan_for_components() {
    local names=("$@")
    local -A seen=()
    SCROW_PLAN_REPO=()
    SCROW_PLAN_AUR=()
    local name pkgs aur p g need_gpu=0
    for name in "${names[@]}"; do
        [[ "$name" == "hyprland" ]] && need_gpu=1
        pkgs="$(scrow_component_packages "$name")"
        aur="$(scrow_component_aur "$name")"
        for p in $pkgs; do
            [[ -n "${seen[$p]:-}" ]] && continue
            seen[$p]=1
            SCROW_PLAN_REPO+=("$p")
        done
        for p in $aur; do
            [[ -n "${seen[$p]:-}" ]] && continue
            seen[$p]=1
            SCROW_PLAN_AUR+=("$p")
        done
    done
    if (( need_gpu )); then
        for g in $(scrow_gpu_packages); do
            [[ -n "${seen[$g]:-}" ]] && continue
            seen[$g]=1
            SCROW_PLAN_REPO+=("$g")
        done
    fi
}

_scrow_component_list_text() {
    local names=("$@") out=""
    local n
    for n in "${names[@]}"; do
        out+="$(scrow_component_title "$n"), "
    done
    printf '%s' "${out%, }"
}

_scrow_plan_summary() {
    # $1 = title, rest = component names
    local title="$1"
    shift
    local names=("$@")
    ui_text ""
    ui_text "${C_BOLD}${title}${C_RESET}"
    ui_hr
    ui_text "  GPU:        $(scrow_gpu_desc)     Device: $([[ "$SCROW_LAPTOP" == "1" ]] && echo Laptop || echo Desktop)"
    ui_text "  Components: $(_scrow_component_list_text "${names[@]}")"
    ui_text "  Packages:   ${#SCROW_PLAN_REPO[@]} via pacman  ·  ${#SCROW_PLAN_AUR[@]} via AUR (paru)"
    ui_text "  Existing SCROW-managed files are backed up automatically."
    if [[ "$SCROW_DRY_RUN" == "1" ]]; then
        ui_text ""
        ui_text "  ${C_DIM}DRY RUN — nothing will be changed.${C_RESET}"
        ui_text "  ${C_DIM}Pacman:${C_RESET}  ${SCROW_PLAN_REPO[*]:-none}"
        [[ ${#SCROW_PLAN_AUR[@]} -gt 0 ]] && ui_text "  ${C_DIM}AUR:${C_RESET}     ${SCROW_PLAN_AUR[*]}"
    fi
    ui_hr
    ui_text ""
}

# -----------------------------------------------------------------------------
# Install flow (shared by full / custom / update / reset / restore / uninstall)
# -----------------------------------------------------------------------------
SCROW_FLOW_FAILED=0
SCROW_FLOW_FAILED_LABEL=""

# scrow_install_flow <title> <"label|func">...
# Runs each phase. Returns 0 on success, 1 if any phase failed.
scrow_install_flow() {
    local title="$1"
    shift
    local -a entries=("$@")
    local -a labels=() fns=()
    local entry i rc

    for entry in "${entries[@]}"; do
        labels+=("${entry%%|*}")
        fns+=("${entry#*|}")
    done

    if [[ "$SCROW_DRY_RUN" == "1" ]]; then
        ui_text "${C_BOLD}${title} (dry run)${C_RESET}"
        ui_hr
        for i in "${!labels[@]}"; do
            ui_step "${labels[$i]}"
            "${fns[$i]}"
        done
        ui_hr
        ui_text ""
        SCROW_FLOW_FAILED=0
        return 0
    fi

    UI_QUIET=1
    ui_progress_start "$title"
    for entry in "${labels[@]}"; do
        ui_progress_add "$entry"
    done
    ui_progress_run

    SCROW_FLOW_FAILED=0
    SCROW_FLOW_FAILED_LABEL=""
    for i in "${!labels[@]}"; do
        ui_progress_set "$i" 2
        rc=0
        "${fns[$i]}" || rc=$?
        if (( rc == 0 )); then
            ui_progress_set "$i" 1
        else
            ui_progress_set "$i" 3
            SCROW_FLOW_FAILED=1
            SCROW_FLOW_FAILED_LABEL="${labels[$i]}"
        fi
    done
    ui_progress_finish
    UI_QUIET=0
    return $SCROW_FLOW_FAILED
}

# -----------------------------------------------------------------------------
# Failure / success panels
# -----------------------------------------------------------------------------
_scrow_view_log() {
    ui_clear
    ui_text "${C_BOLD}SCROW Log${C_RESET} — ${SCROW_CURRENT_LOG}"
    ui_hr
    if [[ -f "$SCROW_CURRENT_LOG" ]]; then
        tail -n 50 "$SCROW_CURRENT_LOG"
    else
        ui_dim "  (no log available)"
    fi
    ui_hr
    ui_pause
}

_scrow_failure_panel() {
    # $1 = retry function name, $2 = context description
    local retry_fn="$1" ctx="$2"
    while :; do
        ui_clear
        ui_alert err "Operation Failed" "The step “$SCROW_FLOW_FAILED_LABEL” did not complete.

${ctx:-A safety backup was created before changes were made.}
You can retry the operation, inspect the log, or go back."
        printf '\n  %s[R]%s Retry    %s[L]%s View Log    %s[B]%s Back\n' \
            "$C_BOLD" "$C_RESET" "$C_BOLD" "$C_RESET" "$C_BOLD" "$C_RESET"
        ui_readkey
        case "$UI_KEY" in
            r|R) "$retry_fn"; return $? ;;
            l|L) _scrow_view_log; continue ;;
            *)   return 1 ;;
        esac
    done
}

_scrow_success_panel() {
    local title="$1"
    ui_clear
    ui_alert ok "$title" "SCROW ${C_BOLD}v$SCROW_VERSION${C_RESET} is ready.

  ${C_ACCENT}scrow${C_RESET}  — open the SCROW Manager from anywhere
  Logs:   ${SCROW_CURRENT_LOG}

Itachi is Goat 🐦⬛"
    ui_pause
}

# -----------------------------------------------------------------------------
# Flow phase helpers
# -----------------------------------------------------------------------------
_scrow_flow_backup()          { scrow_backup_create "before-full-install"; }
_scrow_flow_backup_custom()   { scrow_backup_create "before-custom-install"; }
_scrow_flow_backup_update()   { scrow_backup_create "before-update"; }
_scrow_flow_backup_reset()    { scrow_backup_create "before-reset"; }
_scrow_flow_backup_restore()  { scrow_backup_create "before-restore"; }
_scrow_flow_backup_uninstall(){ scrow_backup_create "before-uninstall"; }

_scrow_flow_packages() {
    scrow_pkg_install "SCROW packages" "${SCROW_PLAN_REPO[@]}" "${SCROW_PLAN_AUR[@]}"
}

_scrow_flow_deploy() {
    scrow_deploy_components "${SCROW_FLOW_COMPS[@]}"
    scrow_manifest_rebuild "${SCROW_FLOW_COMPS[@]}"
}

_scrow_flow_post() {
    local n
    for n in "${SCROW_FLOW_COMPS[@]}"; do
        scrow_component_post "$n"
    done
    # Post hooks may have deployed system files (e.g. security hardening);
    # regenerate the manifest so every owned file is recorded.
    scrow_manifest_rebuild "${SCROW_FLOW_COMPS[@]}"
}

_scrow_flow_services() {
    scrow_services_apply "$SCROW_APPLY_SECURITY"
    scrow_services_user_deploy
}

_scrow_flow_services_custom() {
    if [[ " ${SCROW_FLOW_COMPS[*]} " == *" hyprland "* ]]; then
        scrow_services_apply "$SCROW_APPLY_SECURITY"
        scrow_services_user_deploy
    elif [[ " ${SCROW_FLOW_COMPS[*]} " == *" security "* ]]; then
        scrow_services_apply "1"
    fi
}

_scrow_flow_finalize() {
    scrow_state_set INSTALLED 1
    scrow_state_set SCROW_VERSION "$SCROW_VERSION"
    scrow_state_set INSTALL_DATE "$(scrow_state_get_or INSTALL_DATE "$(date '+%Y-%m-%d %H:%M:%S')")"
}

# -----------------------------------------------------------------------------
# Full installation (recommended)
# -----------------------------------------------------------------------------
scrow_cmd_full() {
    local -a all_components=( $(scrow_component_names) )
    local rc

    if [[ "$(scrow_state_get_or INSTALLED 0)" == "1" ]]; then
        ui_warn "SCROW is already installed (v$(scrow_state_get_or SCROW_VERSION 0.0.0))."
        ui_confirm "Run a Full Installation again anyway?" "n" || return 0
    fi

    ui_clear
    scrow_preflight || { ui_pause; return 1; }
    scrow_plan_for_components "${all_components[@]}"

    _scrow_plan_summary "SCROW — Full Installation" "${all_components[@]}"
    [[ "$SCROW_DRY_RUN" == "1" ]] || ui_confirm "Proceed with the Full Installation?" || { ui_text "  Cancelled."; return 0; }

    SCROW_APPLY_SECURITY=0
    SCROW_SET_SHELL=0
    if ui_confirm "Apply SCROW security hardening? (firewall, sysctl, fail2ban)" "y"; then
        SCROW_APPLY_SECURITY=1
    fi
    if ui_confirm "Set zsh as your default shell?" "y"; then
        SCROW_SET_SHELL=1
    fi
    export SCROW_APPLY_SECURITY SCROW_SET_SHELL

    SCROW_FLOW_COMPS=( "${all_components[@]}" )
    scrow_backup_include_paths $(for n in "${all_components[@]}"; do scrow_component_paths "$n"; done)

    scrow_install_flow "Installing SCROW" \
        "Create safety backup|_scrow_flow_backup" \
        "Install packages|_scrow_flow_packages" \
        "Deploy configuration|_scrow_flow_deploy" \
        "Configure components|_scrow_flow_post" \
        "Configure services|_scrow_flow_services" \
        "Install scrow command|scrow_install_launcher" \
        "Verify installation|scrow_cmd_verify"
    rc=$?

    if [[ "$SCROW_DRY_RUN" == "1" ]]; then
        return 0
    fi
    if (( rc == 0 )); then
        scrow_state_add_components "${all_components[@]}"
        _scrow_flow_finalize
        _scrow_success_panel "Installation Complete"
    else
        _scrow_failure_panel scrow_cmd_full \
            "A safety backup was created at: ${SCROW_BACKUP_PATH}"
    fi
    return $rc
}

# -----------------------------------------------------------------------------
# Custom installation
# -----------------------------------------------------------------------------
scrow_cmd_custom() {
    local rc
    ui_clear
    scrow_components_checklist_init
    if ! ui_checklist "SCROW Custom Installation" "Choose components — Space toggles, Enter continues"; then
        return 0
    fi
    echo
    scrow_components_resolve_deps

    local -a selected=( $(scrow_components_selected) )
    if [[ ${#selected[@]} -eq 0 ]]; then
        ui_warn "No components selected."
        ui_pause
        return 0
    fi

    scrow_preflight || { ui_pause; return 1; }
    scrow_plan_for_components "${selected[@]}"

    _scrow_plan_summary "SCROW — Custom Installation" "${selected[@]}"
    [[ "$SCROW_DRY_RUN" == "1" ]] || ui_confirm "Proceed with the Custom Installation?" || { ui_text "  Cancelled."; return 0; }

    SCROW_APPLY_SECURITY=0
    SCROW_SET_SHELL=0
    if [[ " ${selected[*]} " == *" security "* ]]; then
        ui_confirm "Apply SCROW security hardening? (firewall, sysctl, fail2ban)" "y" && SCROW_APPLY_SECURITY=1
    fi
    if [[ " ${selected[*]} " == *" shell "* ]]; then
        ui_confirm "Set zsh as your default shell?" "y" && SCROW_SET_SHELL=1
    fi
    export SCROW_APPLY_SECURITY SCROW_SET_SHELL

    SCROW_FLOW_COMPS=( "${selected[@]}" )
    scrow_backup_include_paths $(for n in "${selected[@]}"; do scrow_component_paths "$n"; done)

    scrow_install_flow "Installing SCROW (Custom)" \
        "Create safety backup|_scrow_flow_backup_custom" \
        "Install packages|_scrow_flow_packages" \
        "Deploy configuration|_scrow_flow_deploy" \
        "Configure components|_scrow_flow_post" \
        "Configure services|_scrow_flow_services_custom" \
        "Install scrow command|scrow_install_launcher" \
        "Verify installation|scrow_cmd_verify"
    rc=$?

    if [[ "$SCROW_DRY_RUN" == "1" ]]; then
        return 0
    fi
    if (( rc == 0 )); then
        scrow_state_add_components "${selected[@]}"
        _scrow_flow_finalize
        _scrow_success_panel "Custom Installation Complete"
    else
        _scrow_failure_panel scrow_cmd_custom \
            "A safety backup was created at: ${SCROW_BACKUP_PATH}"
    fi
    return $rc
}

# -----------------------------------------------------------------------------
# Update SCROW
# -----------------------------------------------------------------------------
_scrow_flow_refresh() {
    scrow_repo_refresh || return 1
    SCROW_REPO="$SCROW_REPO_DIR"
}

_scrow_flow_update_deploy() {
    scrow_deploy_update
    scrow_manifest_rebuild "${SCROW_FLOW_COMPS[@]}"
}

scrow_cmd_update() {
    local current remote rc
    if [[ "$(scrow_state_get_or INSTALLED 0)" != "1" ]]; then
        ui_warn "SCROW is not installed yet. Run a Full or Custom Installation first."
        ui_pause
        return 0
    fi

    ui_clear
    scrow_repo_ensure_mirror || { ui_pause; return 1; }
    current="$(scrow_state_get_or SCROW_VERSION "$(scrow_repo_local_version)")"
    remote="$(scrow_repo_remote_version)"
    if [[ -z "$remote" ]]; then
        ui_warn "Could not reach the repository to check for updates (network?)."
        ui_pause
        return 1
    fi

    if [[ "$current" == "$remote" ]]; then
        ui_ok "SCROW is up to date (v$current)."
        ui_pause
        return 0
    fi

    ui_text "SCROW Update"
    ui_hr
    ui_text "  Current version:  ${C_DIM}v$current${C_RESET}"
    ui_text "  Latest version:   ${C_OK}v$remote${C_RESET}"
    local -a mods=( $(scrow_manifest_out_of_sync | cut -f1) )
    if [[ ${#mods[@]} -gt 0 ]]; then
        ui_text ""
        ui_warn "${#mods[@]} locally modified file(s) found — they will be preserved."
    fi
    ui_hr
    [[ "$SCROW_DRY_RUN" == "1" ]] || ui_confirm "Update SCROW to v$remote?" || { ui_text "  Cancelled."; return 0; }

    SCROW_FLOW_COMPS=( $(scrow_state_components) )
    scrow_backup_include_paths $(for n in "${SCROW_FLOW_COMPS[@]}"; do scrow_component_paths "$n"; done)

    scrow_install_flow "Updating SCROW" \
        "Create safety backup|_scrow_flow_backup_update" \
        "Fetch new version|_scrow_flow_refresh" \
        "Update managed files|_scrow_flow_update_deploy" \
        "Reconfigure components|_scrow_flow_post" \
        "Verify installation|scrow_cmd_verify"
    rc=$?

    if [[ "$SCROW_DRY_RUN" == "1" ]]; then
        return 0
    fi
    if (( rc == 0 )); then
        scrow_state_set SCROW_VERSION "$remote"
        _scrow_success_panel "SCROW Updated"
    else
        _scrow_failure_panel scrow_cmd_update \
            "Your previous configuration is safe in: ${SCROW_BACKUP_PATH}"
    fi
    return $rc
}

# Update managed files from the new repository state, preserving any file the
# user has locally modified.
scrow_deploy_update() {
    local line rel scope type meta official current comp src src_sha dest
    local -a conflicts=() removed=()
    while IFS=$'\t' read -r rel scope type meta official current comp; do
        [[ -z "$rel" ]] && continue
        dest="$(scrow_target "$rel")"
        if [[ "$type" == "l" ]]; then
            mkdir -p "$(dirname "$dest")"
            rm -f "$dest"
            ln -sfn "$meta" "$dest"
            scrow_log "update: relink $rel"
            continue
        fi
        if [[ "$meta" == @* ]]; then
            src="$SCROW_REPO/${meta#@}"
        else
            src="$SCROW_REPO/$rel"
        fi
        src_sha="$(scrow_sha "$src" 2>/dev/null)"
        if [[ -z "$src_sha" ]]; then
            removed+=("$rel")
            scrow_log "update: $rel removed from repo (user file kept, now untracked)"
            continue
        fi
        if [[ "$current" == "$official" ]]; then
            mkdir -p "$(dirname "$dest")"
            if [[ "$scope" == "system" ]]; then
                scrow_need_root
                scrow_log_tee "update deploy $rel" sudo cp -a "$src" "$dest" || true
            else
                scrow_log_tee "update deploy $rel" cp -a "$src" "$dest" || true
            fi
            scrow_log "update: deployed $rel"
        else
            if [[ "$official" != "$src_sha" ]]; then
                conflicts+=("$rel")
            fi
            scrow_log "update: preserved local modification $rel"
        fi
    done < <(scrow_manifest_lines)

    if [[ ${#conflicts[@]} -gt 0 ]]; then
        ui_warn "Preserved ${#conflicts[@]} locally modified file(s) that also changed upstream:"
        for rel in "${conflicts[@]}"; do
            ui_dim "  ~/$rel"
        done
    fi
    if [[ ${#removed[@]} -gt 0 ]]; then
        ui_dim "  Untracked ${#removed[@]} file(s) no longer shipped by SCROW (kept on disk)."
    fi
}

# -----------------------------------------------------------------------------
# Reset SCROW
# -----------------------------------------------------------------------------
scrow_cmd_reset() {
    local rc
    if [[ "$(scrow_state_get_or INSTALLED 0)" != "1" ]] || [[ ! -s "$SCROW_MANIFEST" ]]; then
        ui_warn "SCROW is not installed yet — nothing to reset."
        ui_pause
        return 0
    fi

    ui_clear
    local -a oos=( $(scrow_manifest_out_of_sync) )
    if [[ ${#oos[@]} -eq 0 ]]; then
        ui_ok "All SCROW-managed files already match the official repository state."
        ui_pause
        return 0
    fi

    local -a changed=() removed=() line_rel line_status
    local entry rel status
    for entry in "${oos[@]}"; do
        rel="${entry%%$'\t'*}"
        status="${entry##*$'\t'}"
        if [[ "$status" == "MODIFIED" ]]; then
            changed+=("$rel")
        else
            removed+=("$rel")
        fi
    done

    ui_text "SCROW Reset"
    ui_hr
    ui_text "The following SCROW-managed files have local modifications:"
    for rel in "${changed[@]}"; do
        ui_text "  ${C_WARN}!${C_RESET}  ~/$rel"
    done
    for rel in "${removed[@]}"; do
        ui_text "  ${C_DIM}·${C_RESET}  ~/$rel  (no longer in the repository — will be untracked)"
    done
    ui_text ""
    ui_text "Reset replaces ONLY SCROW-owned files with the official repository"
    ui_text "versions. Nothing else is touched. A safety backup is created first."
    ui_hr
    [[ "$SCROW_DRY_RUN" == "1" ]] || ui_confirm "Reset SCROW to the official state?" "n" || { ui_text "  Cancelled."; return 0; }

    SCROW_FLOW_COMPS=( $(scrow_state_components) )
    scrow_backup_include_paths $(for n in "${SCROW_FLOW_COMPS[@]}"; do scrow_component_paths "$n"; done)

    scrow_install_flow "Resetting SCROW" \
        "Create safety backup|_scrow_flow_backup_reset" \
        "Fetch official state|_scrow_flow_refresh" \
        "Restore managed files|_scrow_flow_deploy" \
        "Reconfigure components|_scrow_flow_post" \
        "Verify installation|scrow_cmd_verify"
    rc=$?

    if [[ "$SCROW_DRY_RUN" == "1" ]]; then
        return 0
    fi
    if (( rc == 0 )); then
        _scrow_success_panel "SCROW Reset Complete"
    else
        _scrow_failure_panel scrow_cmd_reset \
            "The previous state is safe in: ${SCROW_BACKUP_PATH}"
    fi
    return $rc
}

# -----------------------------------------------------------------------------
# Restore
# -----------------------------------------------------------------------------
_scrow_flow_restore() {
    scrow_backup_restore "$SCROW_RESTORE_TARGET"
}

scrow_cmd_restore() {
    local rc
    if ! scrow_backup_list; then
        ui_info "No automatic backups found yet in:"
        ui_dim "  $SCROW_BACKUP_DIR"
        ui_text ""
        ui_dim "  Backups are created automatically before any operation that"
        ui_dim "  can change SCROW-managed files (install, update, reset, ...)."
        ui_pause
        return 0
    fi

    ui_clear
    local -a items=()
    local entry dir rest date reason
    for entry in "${SCROW_BACKUPS[@]}"; do
        dir="${entry%%|*}"
        rest="${entry#*|}"
        date="${rest%%|*}"
        reason="$(_scrow_backup_reason_label "${rest#*|}")"
        items+=("$date::$reason")
    done
    UI_MENU_ITEMS=( "${items[@]}" )
    ui_menu "SCROW Restore" "Select the backup to restore" "Back"
    local idx="$UI_MENU_SELECTED"
    if (( idx < 0 )); then
        return 0
    fi

    local target="${SCROW_BACKUPS[$idx]%%|*}"
    if ! scrow_backup_verify "$target"; then
        ui_err "That backup is incomplete or missing."
        ui_pause
        return 1
    fi

    ui_clear
    ui_text "SCROW Restore"
    ui_hr
    ui_text "  Backup:  ${target}"
    scrow_backup_summary "$target" | while IFS= read -r line; do
        ui_text "  $line"
    done
    ui_text ""
    ui_text "  This restores SCROW-managed files, symlinks and state."
    ui_text "  A backup of the CURRENT state is created first, so this"
    ui_text "  restore is itself reversible."
    ui_hr
    [[ "$SCROW_DRY_RUN" == "1" ]] || ui_confirm "Restore from this backup?" "n" || { ui_text "  Cancelled."; return 0; }

    SCROW_RESTORE_TARGET="$target"
    SCROW_FLOW_COMPS=( $(scrow_state_components) )

    scrow_install_flow "Restoring SCROW" \
        "Create safety backup|_scrow_flow_backup_restore" \
        "Restore selected backup|_scrow_flow_restore" \
        "Verify installation|scrow_cmd_verify"
    rc=$?

    if [[ "$SCROW_DRY_RUN" == "1" ]]; then
        return 0
    fi
    if (( rc == 0 )); then
        _scrow_success_panel "Restore Complete"
    else
        _scrow_failure_panel scrow_cmd_restore \
            "The state before this restore is safe in: ${SCROW_BACKUP_PATH}"
    fi
    return $rc
}

# -----------------------------------------------------------------------------
# Uninstall
# -----------------------------------------------------------------------------
_scrow_flow_services_disable() {
    scrow_services_user_disable
    if [[ "$SCROW_DISABLE_SERVICES" == "1" ]]; then
        local svc
        for svc in $(scrow_services_owned); do
            scrow_service_disable "$svc"
        done
    fi
}

_scrow_flow_remove() {
    local line rel scope type meta
    local -a entries=()
    while IFS=$'\t' read -r rel scope type meta _official _current _comp; do
        [[ -z "$rel" ]] && continue
        entries+=("$rel|$scope|$type")
    done < <(scrow_manifest_lines)

    local entry target
    for entry in "${entries[@]}"; do
        rel="${entry%%|*}"
        scope="${entry#*|}"; scope="${scope%%|*}"
        type="${entry##*|}"
        target="$(scrow_target "$rel")"
        if [[ "$type" == "l" ]]; then
            rm -f "$target"
            scrow_log "uninstall: removed symlink $rel"
        elif [[ "$scope" == "system" ]]; then
            scrow_run_sudo "remove $rel" rm -f "$target"
            scrow_log "uninstall: removed system file $rel"
        else
            rm -f "$target"
            scrow_log "uninstall: removed $rel"
        fi
    done
    rm -f "$SCROW_MANIFEST"
    ui_ok "Managed files removed"
}

_scrow_flow_launcher_remove() {
    rm -f "$HOME/.local/bin/scrow"
    ui_ok "scrow command removed"
}

_scrow_flow_state_remove() {
    rm -f "$SCROW_STATE_FILE"
    rm -rf "$SCROW_INSTALLER_DIR" "$SCROW_REPO_DIR" "$SCROW_VERSIONS_DIR"
    mkdir -p "$SCROW_BACKUP_DIR"
    ui_ok "SCROW state removed (automatic backups kept)"
}

scrow_cmd_uninstall() {
    local rc
    if [[ "$(scrow_state_get_or INSTALLED 0)" != "1" ]]; then
        ui_warn "SCROW is not installed."
        ui_pause
        return 0
    fi

    ui_clear
    ui_text "SCROW Uninstall"
    ui_hr
    ui_text "  SCROW will remove:"
    ui_text "    • SCROW-managed configuration files"
    ui_text "    • SCROW-created symlinks"
    ui_text "    • SCROW-enabled user services"
    ui_text "    • the scrow command (~/.local/bin/scrow)"
    ui_text "    • SCROW state (manifest, installer, repository, logs)"
    ui_text ""
    ui_text "  SCROW will NOT touch:"
    ui_text "    • files SCROW does not own"
    ui_text "    • installed packages (other software may use them)"
    ui_text "    • automatic backups (kept in $SCROW_BACKUP_DIR)"
    ui_text ""
    ui_text "  A final safety backup is created automatically first."
    ui_hr
    ui_confirm "Uninstall SCROW?" "n" || { ui_text "  Cancelled."; return 0; }
    ui_confirm "This is permanent. Really uninstall SCROW?" "n" || { ui_text "  Cancelled."; return 0; }

    SCROW_DISABLE_SERVICES=0
    ui_confirm "Also disable SCROW-enabled system services (NetworkManager, bluetooth, nftables, fail2ban)?" "n" \
        && SCROW_DISABLE_SERVICES=1

    scrow_install_flow "Uninstalling SCROW" \
        "Create final backup|_scrow_flow_backup_uninstall" \
        "Disable SCROW services|_scrow_flow_services_disable" \
        "Remove managed files|_scrow_flow_remove" \
        "Remove scrow command|_scrow_flow_launcher_remove" \
        "Clean SCROW state|_scrow_flow_state_remove"
    rc=$?

    if [[ "$SCROW_DRY_RUN" == "1" ]]; then
        return 0
    fi
    ui_clear
    if (( rc == 0 )); then
        ui_alert ok "SCROW Removed" "SCROW has been uninstalled.

Your automatic backups were kept at:
  ${SCROW_BACKUP_DIR}

To restore a previous SCROW state, clone the repository and run:
  ./install.sh    →  Restore"
    else
        _scrow_failure_panel scrow_cmd_uninstall \
            "Your previous state is safe in: ${SCROW_BACKUP_PATH}"
    fi
    ui_pause
    return $rc
}

# -----------------------------------------------------------------------------
# Verification
# -----------------------------------------------------------------------------
scrow_cmd_verify() {
    ui_step "Verifying installation…"
    if [[ "$SCROW_DRY_RUN" == "1" ]]; then
        ui_dim "  [dry-run] would verify packages, files, symlinks, services and state"
        return 0
    fi
    local problems=0 missing broken m

    if [[ ! -s "$SCROW_MANIFEST" ]]; then
        ui_warn "SCROW manifest is missing."
        problems=$(( problems + 1 ))
    else
        missing="$(scrow_manifest_missing)"
        if [[ -n "$missing" ]]; then
            ui_warn "Missing managed files:"
            while IFS= read -r m; do
                ui_dim "  ~/$m"
            done <<< "$missing"
            problems=$(( problems + 1 ))
        fi
        broken="$(scrow_manifest_broken_symlinks)"
        if [[ -n "$broken" ]]; then
            ui_warn "Broken symlinks:"
            while IFS= read -r m; do
                ui_dim "  ~/$m"
            done <<< "$broken"
            problems=$(( problems + 1 ))
        fi
    fi

    if [[ ! -x "$HOME/.local/bin/scrow" ]]; then
        ui_warn "scrow command is missing (~/.local/bin/scrow)."
        problems=$(( problems + 1 ))
    fi

    if (( problems == 0 )); then
        ui_ok "Installation verified"
        return 0
    fi
    return 1
}

# -----------------------------------------------------------------------------
# The `scrow` launcher
# -----------------------------------------------------------------------------
scrow_install_launcher() {
    ui_step "Installing the scrow command…"
    if [[ "$SCROW_DRY_RUN" == "1" ]]; then
        ui_dim "  [dry-run] ~/.local/bin/scrow → SCROW Manager"
        ui_dim "  [dry-run] installer copy → $SCROW_INSTALLER_DIR"
        ui_dim "  [dry-run] repository mirror → $SCROW_REPO_DIR"
        return 0
    fi

    mkdir -p "$HOME/.local/bin" "$SCROW_STATE_DIR"

    # Self-contained copy of the installer so `scrow` works anywhere.
    cp -a "$SCROW_INSTALLER_SRC/." "$SCROW_INSTALLER_DIR/"
    if [[ -f "$SCROW_INSTALLER_SRC/install.sh" ]]; then
        cp -a "$SCROW_INSTALLER_SRC/install.sh" "$SCROW_INSTALLER_DIR/install.sh"
    elif [[ -f "$SCROW_REPO/install.sh" ]]; then
        cp -a "$SCROW_REPO/install.sh" "$SCROW_INSTALLER_DIR/install.sh"
    fi

    scrow_repo_ensure_mirror

    cat > "$HOME/.local/bin/scrow" << 'SCROW_LAUNCHER'
#!/usr/bin/env bash
# SCROW Manager launcher — opens the manager from any directory.
SCROW_STATE="$HOME/.local/share/scrow"
if [[ ! -f "$SCROW_STATE/installer/install.sh" ]]; then
    printf '%s\n' "SCROW is not installed yet."
    printf '%s\n' "Install with:"
    printf '%s\n' "  curl -fsSL https://raw.githubusercontent.com/midn8crow/scrow/main/bootstrap.sh | bash"
    exit 1
fi
if [[ ! -f "$SCROW_STATE/repo/VERSION" ]]; then
    printf '%s\n' "SCROW source is missing. Re-run the bootstrap:"
    printf '%s\n' "  curl -fsSL https://raw.githubusercontent.com/midn8crow/scrow/main/bootstrap.sh | bash"
    exit 1
fi
exec bash "$SCROW_STATE/installer/install.sh" --source "$SCROW_STATE/repo" "$@"
SCROW_LAUNCHER
    chmod +x "$HOME/.local/bin/scrow"

    ui_ok "scrow command installed — run 'scrow' from anywhere"
}
