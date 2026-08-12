#!/usr/bin/env bash
# =============================================================================
# SCROW - state + services
# =============================================================================
# SCROW tracks its own state in ~/.local/share/scrow/state and only ever
# enables/disables services that SCROW itself owns.
# =============================================================================

# -----------------------------------------------------------------------------
# State helpers
# -----------------------------------------------------------------------------
scrow_state_init() {
    mkdir -p "$SCROW_STATE_DIR"
    [[ -f "$SCROW_STATE_FILE" ]] || {
        echo "SCROW_VERSION=$SCROW_VERSION" > "$SCROW_STATE_FILE"
        echo "INSTALLED=0" >> "$SCROW_STATE_FILE"
        echo "COMPONENTS=" >> "$SCROW_STATE_FILE"
        echo "SERVICES=" >> "$SCROW_STATE_FILE"
        echo "INSTALL_DATE=$(date '+%Y-%m-%d %H:%M:%S')" >> "$SCROW_STATE_FILE"
    }
}

scrow_state_set() {
    local key="$1" value="$2"
    scrow_state_init
    if grep -q "^$key=" "$SCROW_STATE_FILE" 2>/dev/null; then
        sed -i "s|^$key=.*|$key=$value|" "$SCROW_STATE_FILE"
    else
        echo "$key=$value" >> "$SCROW_STATE_FILE"
    fi
    scrow_log "state: $key=$value"
}

scrow_state_get() {
    local key="$1"
    sed -n "s|^$key=||p" "$SCROW_STATE_FILE" 2>/dev/null
}

scrow_state_get_or() {
    local key="$1" default="$2" v
    v="$(scrow_state_get "$key")"
    printf '%s' "${v:-$default}"
}

# -----------------------------------------------------------------------------
# User services (SCROW-owned, from .config/systemd/user)
# -----------------------------------------------------------------------------
scrow_services_user_deploy() {
    local units=()
    local f
    for f in "$HOME"/.config/systemd/user/*.service "$HOME"/.config/systemd/user/*.socket; do
        [[ -f "$f" || -L "$f" ]] && units+=("$(basename "$f")")
    done
    if [[ ${#units[@]} -gt 0 ]]; then
        ui_step "Enabling SCROW user services…"
        scrow_log "user services: ${units[*]}"
        if [[ "$SCROW_DRY_RUN" == "1" ]]; then
            ui_dim "  [dry-run] systemctl --user enable ${units[*]}"
            return 0
        fi
        if systemctl --user enable "${units[@]}" >> "$SCROW_CURRENT_LOG" 2>&1; then
            ui_ok "User services enabled"
        else
            ui_warn "User services will start at next login"
            scrow_log "user service enable deferred to login (no active user session)"
        fi
    fi
}

# -----------------------------------------------------------------------------
# System services (SCROW-owned)
# -----------------------------------------------------------------------------
scrow_service_enable() {
    local svc="$1"
    ui_step "Enabling service: $svc"
    if [[ "$SCROW_DRY_RUN" == "1" ]]; then
        ui_dim "  [dry-run] sudo systemctl enable --now $svc"
        return 0
    fi
    scrow_need_root
    scrow_log_tee "enable service $svc" sudo systemctl enable --now "$svc" || true
    # Track it in state so Doctor / Uninstall can verify ownership.
    local current
    current="$(scrow_state_get SERVICES)"
    [[ "$current" == *"$svc"* ]] || scrow_state_set SERVICES "$current $svc"
}

scrow_service_disable() {
    local svc="$1"
    ui_step "Disabling service: $svc"
    if [[ "$SCROW_DRY_RUN" == "1" ]]; then
        ui_dim "  [dry-run] sudo systemctl disable --now $svc"
        return 0
    fi
    scrow_need_root
    scrow_log_tee "disable service $svc" sudo systemctl disable --now "$svc" || true
}

scrow_service_status() {
    local svc="$1"
    if systemctl is-enabled "$svc" >/dev/null 2>&1; then
        if systemctl is-active "$svc" >/dev/null 2>&1; then
            echo "enabled-running"
        else
            echo "enabled-stopped"
        fi
    else
        if systemctl is-active "$svc" >/dev/null 2>&1; then
            echo "active-not-enabled"
        else
            echo "absent"
        fi
    fi
}

# Apply the standard SCROW system services based on detected hardware.
scrow_services_apply() {
    local include_security="${1:-1}"
    scrow_service_enable NetworkManager

    if [[ "$SCROW_LAPTOP" == "1" ]] || ls /sys/class/bluetooth/ >/dev/null 2>&1; then
        scrow_service_enable bluetooth
    fi
    if [[ "$SCROW_LAPTOP" == "1" ]]; then
        scrow_service_enable power-profiles-daemon
    fi

    # PipeWire audio (user-level)
    ui_step "Enabling audio services (PipeWire)…"
    if [[ "$SCROW_DRY_RUN" != "1" ]]; then
        systemctl --user enable --now pipewire pipewire-pulse wireplumber \
            >> "$SCROW_CURRENT_LOG" 2>&1 || true
        scrow_log "pipewire user services enabled"
    fi

    if [[ "$include_security" == "1" ]]; then
        scrow_service_enable nftables
        scrow_service_enable fail2ban
        if [[ -d /etc/ssh ]] && command -v sshd >/dev/null 2>&1; then
            scrow_service_enable sshd
        fi
    fi
}
