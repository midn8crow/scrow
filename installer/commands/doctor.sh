#!/usr/bin/env bash
# =============================================================================
# SCROW - Doctor / Repair
# =============================================================================
# Detects problems with the SCROW installation (system, packages, files,
# symlinks, services, manifest, state) and offers safe, confirmed repairs.
# Nothing is ever repaired without explicit confirmation, and any re-deploy
# is preceded by an automatic backup.
# =============================================================================

SCROW_DOCTOR_ERRORS=0
SCROW_DOCTOR_WARNINGS=0
SCROW_DOCTOR_REPAIR_PACKAGES=()
SCROW_DOCTOR_REPAIR_SERVICES=()
SCROW_DOCTOR_REPAIR_FILES=0
SCROW_DOCTOR_REPAIR_LAUNCHER=0

scrow_doctor_reset() {
    SCROW_DOCTOR_ERRORS=0
    SCROW_DOCTOR_WARNINGS=0
    SCROW_DOCTOR_REPAIR_PACKAGES=()
    SCROW_DOCTOR_REPAIR_SERVICES=()
    SCROW_DOCTOR_REPAIR_FILES=0
    SCROW_DOCTOR_REPAIR_LAUNCHER=0
}

scrow_doctor_section() { ui_text ""; ui_text "${C_BOLD}  ${1}${C_RESET}"; }
scrow_doctor_ok()      { ui_ok "  $1"; }
scrow_doctor_warn()    { ui_warn "  $1"; SCROW_DOCTOR_WARNINGS=$(( SCROW_DOCTOR_WARNINGS + 1 )); }
scrow_doctor_err()     { ui_err "  $1"; SCROW_DOCTOR_ERRORS=$(( SCROW_DOCTOR_ERRORS + 1 )); }

# -----------------------------------------------------------------------------
# Checks
# -----------------------------------------------------------------------------
scrow_doctor_check_system() {
    scrow_doctor_section "System"
    if [[ -f /etc/arch-release ]]; then
        scrow_doctor_ok "Arch Linux"
    else
        scrow_doctor_err "Not running Arch Linux"
    fi

    local net=0
    if ping -c 1 -W 3 archlinux.org >/dev/null 2>&1 || ping -c 1 -W 3 1.1.1.1 >/dev/null 2>&1; then
        net=1
    fi
    if (( net )); then
        scrow_doctor_ok "Network reachable"
    else
        scrow_doctor_warn "Network unreachable (install / update / reset need the network)"
    fi

    local tool
    for tool in bash git curl sudo pacman; do
        command -v "$tool" >/dev/null 2>&1 || scrow_doctor_err "Missing required tool: $tool"
    done

    local -a comps=( $(scrow_state_components) ) has_aur=0 c
    for c in "${comps[@]}"; do
        [[ -n "$(scrow_component_aur "$c")" ]] && has_aur=1
    done
    if (( has_aur )); then
        command -v paru >/dev/null 2>&1 || scrow_doctor_err "paru missing (required for installed AUR packages)"
    elif command -v paru >/dev/null 2>&1; then
        scrow_doctor_ok "paru available"
    fi
}

scrow_doctor_check_packages() {
    local -a comps=( $(scrow_state_components) )
    scrow_doctor_section "Packages"
    if [[ ${#comps[@]} -eq 0 ]]; then
        ui_dim "  (no components installed — run a Full or Custom Installation first)"
        return
    fi

    local -a all=()
    local c pkgs
    for c in "${comps[@]}"; do
        pkgs="$(scrow_component_packages "$c")"
        all+=( $pkgs )
    done
    [[ "$SCROW_GPU" != "none" ]] && all+=( $(scrow_gpu_packages) )

    local -a missing=( $(scrow_pkg_missing "${all[@]}") )
    if [[ ${#missing[@]} -eq 0 ]]; then
        scrow_doctor_ok "All SCROW packages present (${#all[@]})"
    else
        scrow_doctor_err "Missing packages: ${missing[*]}"
        SCROW_DOCTOR_REPAIR_PACKAGES+=( "${missing[@]}" )
    fi
}

scrow_doctor_check_config() {
    scrow_doctor_section "Configuration"
    if [[ ! -s "$SCROW_MANIFEST" ]]; then
        scrow_doctor_err "SCROW manifest missing or empty"
        return
    fi
    scrow_doctor_ok "Manifest present ($(scrow_manifest_count) entries)"

    local missing
    missing="$(scrow_manifest_missing)"
    if [[ -n "$missing" ]]; then
        scrow_doctor_err "Missing managed files:"
        while IFS= read -r m; do ui_dim "      ~/$m"; done <<< "$missing"
        SCROW_DOCTOR_REPAIR_FILES=1
    else
        scrow_doctor_ok "All managed files present"
    fi

    local broken
    broken="$(scrow_manifest_broken_symlinks)"
    if [[ -n "$broken" ]]; then
        scrow_doctor_err "Broken symlinks:"
        while IFS= read -r m; do ui_dim "      ~/$m"; done <<< "$broken"
        SCROW_DOCTOR_REPAIR_FILES=1
    else
        scrow_doctor_ok "Symlinks healthy"
    fi

    local modified
    modified="$(scrow_manifest_modified)"
    if [[ -n "$modified" ]]; then
        scrow_doctor_warn "$(printf '%s\n' "$modified" | wc -l) locally modified file(s) — Reset restores the official versions"
    fi

    local oos
    oos="$(scrow_manifest_out_of_sync | wc -l)"
    [[ "$oos" -gt 0 ]] && scrow_doctor_warn "$oos file(s) differ from the official repository state"
}

scrow_doctor_check_services() {
    scrow_doctor_section "Services"
    local svc st
    for svc in $(scrow_services_owned); do
        st="$(scrow_service_status "$svc")"
        case "$st" in
            enabled-running) scrow_doctor_ok "$svc (enabled, running)" ;;
            enabled-stopped) scrow_doctor_warn "$svc (enabled, stopped)" ;;
            active-not-enabled) scrow_doctor_warn "$svc (active but not enabled)" ;;
            *) scrow_doctor_err "$svc (not enabled)"; SCROW_DOCTOR_REPAIR_SERVICES+=( "$svc" ) ;;
        esac
    done

    local f
    for f in "$HOME"/.config/systemd/user/*.service; do
        [[ -f "$f" ]] || continue
        if systemctl --user is-enabled "$(basename "$f")" >/dev/null 2>&1; then
            scrow_doctor_ok "user service $(basename "$f")"
        else
            scrow_doctor_warn "user service $(basename "$f") not enabled (enables at next install)"
        fi
    done
}

scrow_doctor_check_state() {
    scrow_doctor_section "SCROW state"
    if [[ "$(scrow_state_get_or INSTALLED 0)" == "1" ]]; then
        scrow_doctor_ok "SCROW installed (v$(scrow_state_get_or SCROW_VERSION 0.0.0))"
    else
        scrow_doctor_warn "SCROW not marked as installed"
    fi

    local -a comps=( $(scrow_state_components) )
    if [[ ${#comps[@]} -gt 0 ]]; then
        scrow_doctor_ok "Components: ${comps[*]}"
    fi

    if [[ -d "$SCROW_REPO_DIR/.git" ]]; then
        scrow_doctor_ok "Repository mirror present"
    else
        scrow_doctor_warn "Repository mirror missing (Update / Reset will re-fetch it)"
    fi

    if [[ -x "$HOME/.local/bin/scrow" ]]; then
        scrow_doctor_ok "scrow command present"
    else
        scrow_doctor_err "scrow command missing (~/.local/bin/scrow)"
        SCROW_DOCTOR_REPAIR_LAUNCHER=1
    fi
}

# -----------------------------------------------------------------------------
# Repair
# -----------------------------------------------------------------------------
_scrow_doctor_repair() {
    ui_clear
    ui_text "${C_BOLD}SCROW Repair${C_RESET}"
    ui_hr

    if [[ ${#SCROW_DOCTOR_REPAIR_PACKAGES[@]} -gt 0 ]]; then
        if ui_confirm "Install missing packages (${SCROW_DOCTOR_REPAIR_PACKAGES[*]})?" "y"; then
            scrow_pkg_install "Doctor repair" "${SCROW_DOCTOR_REPAIR_PACKAGES[@]}"
        fi
    fi

    if [[ "$SCROW_DOCTOR_REPAIR_FILES" == "1" ]]; then
        local -a comps=( $(scrow_state_components) )
        if [[ ${#comps[@]} -gt 0 ]]; then
            if ui_confirm "Re-deploy SCROW-managed files for ${#comps[@]} component(s)? (automatic backup first)" "y"; then
                scrow_components_repair "${comps[@]}"
            fi
        fi
    fi

    local svc
    for svc in "${SCROW_DOCTOR_REPAIR_SERVICES[@]}"; do
        ui_confirm "Enable service $svc?" "y" && scrow_service_enable "$svc"
    done

    if [[ "$SCROW_DOCTOR_REPAIR_LAUNCHER" == "1" ]]; then
        ui_confirm "Reinstall the scrow command (~/.local/bin/scrow)?" "y" && scrow_install_launcher
    fi

    ui_text ""
    ui_ok "Repair finished — run Doctor again to re-check."
    ui_pause
}

# -----------------------------------------------------------------------------
# Entry point
# -----------------------------------------------------------------------------
scrow_cmd_doctor() {
    scrow_doctor_reset
    scrow_detect_gpu

    ui_clear
    ui_text "${C_BOLD}SCROW Doctor${C_RESET}"
    ui_hr

    scrow_doctor_check_system
    scrow_doctor_check_packages
    scrow_doctor_check_config
    scrow_doctor_check_services
    scrow_doctor_check_state

    ui_hr
    local total=$(( SCROW_DOCTOR_ERRORS + SCROW_DOCTOR_WARNINGS ))
    if (( total == 0 )); then
        ui_ok "All checks passed — SCROW is healthy"
    else
        ui_text "  ${C_ERR}${SCROW_DOCTOR_ERRORS} error(s)${C_RESET}, ${C_WARN}${SCROW_DOCTOR_WARNINGS} warning(s)${C_RESET}"
    fi

    if (( SCROW_DOCTOR_ERRORS > 0 || SCROW_DOCTOR_WARNINGS > 0 )); then
        printf '\n  %s[R]%s Repair safe issues    %s[L]%s View log    %s[B]%s Back\n' \
            "$C_BOLD" "$C_RESET" "$C_BOLD" "$C_RESET" "$C_BOLD" "$C_RESET"
        ui_readkey
        case "$UI_KEY" in
            r|R) _scrow_doctor_repair ;;
            l|L) _scrow_view_log ;;
        esac
    else
        ui_pause
    fi
}
