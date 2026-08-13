#!/usr/bin/env bash
# =============================================================================
# SCROW - main manager
# =============================================================================
# The SCROW Manager is the primary interface. It opens when `scrow` or
# ./install.sh is run and dispatches to the individual operations.
# =============================================================================

scrow_cmd_manager() {
    while :; do
        UI_MENU_ITEMS=(
            "Full Installation::recommended setup::Installation"
            "Custom Installation::select components::Installation"
            "Components::manage individual components::Installation"
            "Update SCROW::fetch the latest version::Management"
            "Restore::return to a previous backup::Management"
            "Reset SCROW::restore official files::Management"
            "Doctor / Repair::check and fix the environment::Management"
            "Uninstall SCROW::remove everything::Management"
        )
        ui_menu "SCROW Manager" "Arch Linux • Hyprland" "v$SCROW_VERSION"
        local idx="$UI_MENU_SELECTED"
        if (( idx < 0 )); then
            break
        fi
        case "$idx" in
            0) scrow_cmd_full ;;
            1) scrow_cmd_custom ;;
            2) scrow_cmd_components ;;
            3) scrow_cmd_update ;;
            4) scrow_cmd_restore ;;
            5) scrow_cmd_reset ;;
            6) scrow_cmd_doctor ;;
            7) scrow_cmd_uninstall ;;
        esac
    done
}

# -----------------------------------------------------------------------------
# Components submenu: pick a component, then an action. Only the selected
# component is touched — never the whole environment.
# -----------------------------------------------------------------------------
_scrow_component_actions() {
    local name="$1" installed=0
    printf '%s\n' "$(scrow_state_components)" | grep -qx "$name" && installed=1

    local -a items=( "Install::install packages and deploy files" )
    if (( installed )); then
        items+=(
            "Reinstall::re-deploy official files (backup first)"
            "Repair::fix missing packages and files (backup first)"
            "Update::refresh to the current official state"
        )
    else
        items+=(
            "Reinstall::not installed — install it first"
            "Repair::not installed — install it first"
            "Update::not installed — install it first"
        )
    fi

    UI_MENU_ITEMS=( "${items[@]}" )
    ui_menu "SCROW — $(scrow_component_title "$name")" "$(scrow_component_desc "$name")" "" "Back"
    local action="$UI_MENU_SELECTED"

    case "$action" in
        0)
            # Resolve declared dependencies and explain the additions.
            local -a deps=( $(scrow_components_with_deps "$name") )
            local extra=()
            local d
            for d in "${deps[@]}"; do
                [[ "$d" == "$name" ]] && continue
                printf '%s\n' "$(scrow_state_components)" | grep -qx "$d" || extra+=( "$d" )
            done
            if [[ ${#extra[@]} -gt 0 ]]; then
                ui_info "Also installing required component(s): ${extra[*]}"
                echo
            fi
            ui_confirm "Install $(scrow_component_title "$name")?" "y" \
                && scrow_components_install "${deps[@]}"
            ;;
        1)
            (( installed )) || ui_warn "Component is not installed — use Install first."
            (( installed )) && ui_confirm "Reinstall $(scrow_component_title "$name")?" "y" \
                && scrow_components_reinstall "$name"
            ;;
        2)
            (( installed )) || ui_warn "Component is not installed — use Install first."
            (( installed )) && ui_confirm "Repair $(scrow_component_title "$name")?" "y" \
                && scrow_components_repair "$name"
            ;;
        3)
            (( installed )) || ui_warn "Component is not installed — use Install first."
            (( installed )) && ui_confirm "Update $(scrow_component_title "$name")?" "y" \
                && scrow_components_update "$name"
            ;;
        *) return 0 ;;
    esac
    ui_pause
}

scrow_cmd_components() {
    scrow_components_load_names
    while :; do
        UI_MENU_ITEMS=()
        local i n hint
        for i in "${!SCROW_COMPONENT_NAMES_ARRAY[@]}"; do
            n="${SCROW_COMPONENT_NAMES_ARRAY[$i]}"
            if printf '%s\n' "$(scrow_state_components)" | grep -qx "$n"; then
                hint="installed"
            else
                hint="not installed"
            fi
            UI_MENU_ITEMS+=( "$(scrow_component_title "$n")::$hint" )
        done

        ui_menu "SCROW Components" "Select a component to manage" "" "Back"
        local idx="$UI_MENU_SELECTED"
        if (( idx < 0 )); then
            return 0
        fi
        _scrow_component_actions "${SCROW_COMPONENT_NAMES_ARRAY[$idx]}"
    done
}
