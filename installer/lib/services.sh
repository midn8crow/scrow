#!/usr/bin/env bash
# =============================================================================
# SCROW — services & system setup
# =============================================================================
# Groups, shell, systemd services, linger, required directories.

setup_groups() {
    printf "\n  ${C_BOLD}User groups:${C_RST}\n"
    for grp in video audio input optical storage; do
        if ! id -nG "$USER" 2>/dev/null | tr ' ' '\n' | grep -qx "$grp"; then
            x "add user to group $grp" sudo usermod -aG "$grp" "$USER"
        else
            printf "${C_OK}  [ OK ]${C_RST} already in group %s\n" "$grp"
        fi
    done
}

setup_shell() {
    printf "\n  ${C_BOLD}Login shell:${C_RST}\n"
    if command -v zsh >/dev/null 2>&1; then
        local current_shell
        current_shell="$(getent passwd "$USER" 2>/dev/null | cut -d: -f7)"
        if [[ "$current_shell" != "$(command -v zsh)" ]]; then
            x "set default shell to zsh" bash -c "chsh -s $(command -v zsh)"
        else
            printf "${C_OK}  [ OK ]${C_RST} shell is already zsh\n"
        fi
    else
        printf "${C_WARN}  [SKIP]${C_RST} zsh not installed yet — skipping shell change\n"
    fi
}

setup_user_services() {
    printf "\n  ${C_BOLD}Systemd user services:${C_RST}\n"
    local services=(
        pipewire.service
        wireplumber.service
        mako.service
        waybar.service
        hyprland-session.target
        xdg-desktop-portal-hyprland.service
    )
    for svc in "${services[@]}"; do
        if systemctl --user is-enabled "$svc" >/dev/null 2>&1; then
            printf "${C_OK}  [ OK ]${C_RST} %s already enabled\n" "$svc"
        else
            x "enable $svc" systemctl --user enable "$svc" 2>/dev/null || true
        fi
    done
}

setup_system_services() {
    printf "\n  ${C_BOLD}Systemd system services:${C_RST}\n"
    make_sudo_keepalive
    if command -v sddm >/dev/null 2>&1; then
        x "enable sddm" sudo systemctl enable sddm.service
    fi
    if command -v NetworkManager >/dev/null 2>&1; then
        x "enable NetworkManager" sudo systemctl enable NetworkManager.service
    fi
}

setup_linger() {
    printf "\n  ${C_BOLD}Loginctl linger:${C_RST}\n"
    if command -v loginctl >/dev/null 2>&1; then
        x "enable linger for $USER" sudo loginctl enable-linger "$USER" 2>/dev/null || true
    fi
}

setup_directories() {
    printf "\n  ${C_BOLD}Directories:${C_RST}\n"
    for dir in "$XDG_BIN_HOME" "$SCROW_BACKUP_DIR"; do
        if [[ ! -d "$dir" ]]; then
            x "create $(basename "$dir")" mkdir -p "$dir"
        else
            printf "${C_OK}  [ OK ]${C_RST} %s exists\n" "$(basename "$dir")"
        fi
    done
}

setup_all() {
    setup_groups
    setup_shell
    setup_user_services
    setup_system_services
    setup_linger
    setup_directories
    stop_sudo_keepalive
}
