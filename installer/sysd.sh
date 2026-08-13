#!/usr/bin/env bash
# =============================================================================
# SCROW — systemd services
# =============================================================================
# SCROW enables/restarts a small, fixed set of user services that support the
# desktop session. Which services are owned is recorded in the state file so
# the manager can disable exactly what SCROW enabled.
# =============================================================================

SCROW_SERVICES_SUPPORT=(
    pipewire.service
    pipewire-pulse.service
    wireplumber.service
    xdg-desktop-portal-hyprland.service
)

scrow_service_enable() {
    local svc="$1" user
    if systemctl --user list-unit-files --type=service "$svc" >/dev/null 2>&1; then
        user="--user"
    elif systemctl list-unit-files --type=service "$svc" >/dev/null 2>&1; then
        user=""
    else
        scrow_log "service: $svc not found"
        return 0
    fi
    echo "  ${C_DIM}Enabling service: $svc${C_RESET}"
    if [[ "$SCROW_DRY_RUN" == "1" ]]; then
        echo "  [dry-run] systemctl $user enable --now $svc"
        return 0
    fi
    if [[ -z "$user" ]]; then
        scrow_run_sudo "enable $svc" systemctl enable --now "$svc" || return 1
    else
        scrow_run "enable $svc" systemctl --user enable --now "$svc" || return 1
    fi
    if [[ "$user" == "--user" ]]; then
        scrow_state_add_service "$svc"
    fi
}

scrow_service_disable() {
    local svc="$1"
    echo "  ${C_DIM}Disabling service: $svc${C_RESET}"
    [[ "$SCROW_DRY_RUN" == "1" ]] && { echo "  [dry-run] sudo systemctl disable --now $svc"; return 0; }
    scrow_run_sudo "disable $svc" systemctl disable --now "$svc" || return 1
}

scrow_service_restart() {
    local svc="$1"
    [[ "$SCROW_DRY_RUN" == "1" ]] && { echo "  [dry-run] systemctl --user restart $svc"; return 0; }
    systemctl --user restart "$svc" 2>/dev/null || true
}

# Enable the standard user service support stack.
scrow_services_apply() {
    local svc
    for svc in "${SCROW_SERVICES_SUPPORT[@]}"; do
        scrow_service_enable "$svc"
    done
    scrow_service_restart pipewire
    scrow_service_restart wireplumber
}

# Disable only the services SCROW owns.
scrow_services_disable_owned() {
    local svc
    for svc in $(scrow_state_services); do
        [[ -n "$svc" ]] || continue
        echo "  ${C_DIM}Disabling SCROW service: $svc${C_RESET}"
        [[ "$SCROW_DRY_RUN" == "1" ]] && { echo "  [dry-run] systemctl --user disable --now $svc"; continue; }
        systemctl --user disable --now "$svc" 2>/dev/null || true
    done
}
