#!/usr/bin/env bash
# =============================================================================
# SCROW - component engine
# =============================================================================
# Installs, reinstalls, repairs and updates individual components. Every
# component is backed up before any destructive operation and only the
# requested component is touched.
# =============================================================================

SCROW_COMPONENT_NAMES_ARRAY=()

scrow_components_load_names() {
    SCROW_COMPONENT_NAMES_ARRAY=()
    local n
    while IFS= read -r n; do
        [[ -n "$n" ]] && SCROW_COMPONENT_NAMES_ARRAY+=("$n")
    done < <(scrow_component_names)
}

scrow_component_index_to_name() {
    printf '%s' "${SCROW_COMPONENT_NAMES_ARRAY[$1]}"
}

# -----------------------------------------------------------------------------
# Checklist (Custom Installation)
# -----------------------------------------------------------------------------
scrow_components_checklist_init() {
    scrow_components_load_names
    UI_CHECK_ITEMS=()
    UI_CHECK_STATE=()
    local i n
    for i in "${!SCROW_COMPONENT_NAMES_ARRAY[@]}"; do
        n="${SCROW_COMPONENT_NAMES_ARRAY[$i]}"
        UI_CHECK_ITEMS+=("$(scrow_component_title "$n") — $(scrow_component_desc "$n")")
        UI_CHECK_STATE+=(0)
    done
}

scrow_components_resolve_deps() {
    # Forces dependency components on and explains the additions.
    local i n needs need changed=0
    for i in "${!SCROW_COMPONENT_NAMES_ARRAY[@]}"; do
        [[ "${UI_CHECK_STATE[$i]}" == "1" ]] || continue
        n="${SCROW_COMPONENT_NAMES_ARRAY[$i]}"
        needs="$(scrow_component_needs "$n")"
        for need in $needs; do
            local idx=-1 j
            for j in "${!SCROW_COMPONENT_NAMES_ARRAY[@]}"; do
                [[ "${SCROW_COMPONENT_NAMES_ARRAY[$j]}" == "$need" ]] && idx=$j
            done
            if (( idx >= 0 )) && [[ "${UI_CHECK_STATE[$idx]}" != "1" ]]; then
                UI_CHECK_STATE[$idx]=1
                ui_info "  ${n}: requires $(scrow_component_title "$need") → included"
                changed=1
            fi
        done
    done
    [[ "$changed" == "1" ]] && echo
}

scrow_components_selected() {
    # Prints the names of currently checked components.
    local i
    for i in "${!SCROW_COMPONENT_NAMES_ARRAY[@]}"; do
        [[ "${UI_CHECK_STATE[$i]}" == "1" ]] && printf '%s\n' "${SCROW_COMPONENT_NAMES_ARRAY[$i]}"
    done
}

# -----------------------------------------------------------------------------
# Install / reinstall / repair / update of components
# -----------------------------------------------------------------------------
scrow_components_install() {
    # scrow_components_install <names...>
    local names=("$@") name
    if [[ -s "$SCROW_MANIFEST" ]]; then
        scrow_backup_include_paths $(for n in "${names[@]}"; do scrow_component_paths "$n"; done)
        scrow_backup_create "before-install"
    fi
    for name in "${names[@]}"; do
        ui_step "Component: ${C_BOLD}$(scrow_component_title "$name")${C_RESET}"
        local pkgs aur
        pkgs="$(scrow_component_packages "$name")"
        aur="$(scrow_component_aur "$name")"
        scrow_pkg_install "$(scrow_component_title "$name")" $pkgs $aur
        scrow_deploy_component "$name"
        scrow_component_post "$name"
    done
    scrow_state_add_components "${names[@]}"
    scrow_manifest_rebuild $(scrow_state_components)
}

scrow_components_reinstall() {
    # Re-deploy official files for the given components (backup first).
    local names=("$@") name
    scrow_backup_include_paths $(for n in "${names[@]}"; do scrow_component_paths "$n"; done)
    scrow_backup_create "before-reinstall"
    for name in "${names[@]}"; do
        ui_step "Reinstalling: ${C_BOLD}$(scrow_component_title "$name")${C_RESET}"
        scrow_deploy_component "$name"
        scrow_component_post "$name"
    done
    scrow_manifest_rebuild $(scrow_state_components)
}

scrow_components_repair() {
    # Re-deploy + ensure packages are present.
    local names=("$@") name missing
    scrow_backup_include_paths $(for n in "${names[@]}"; do scrow_component_paths "$n"; done)
    scrow_backup_create "before-repair"
    for name in "${names[@]}"; do
        ui_step "Repairing: ${C_BOLD}$(scrow_component_title "$name")${C_RESET}"
        local pkgs aur
        pkgs="$(scrow_component_packages "$name")"
        aur="$(scrow_component_aur "$name")"
        missing="$(scrow_pkg_missing $pkgs $aur)"
        if [[ -n "$missing" ]]; then
            ui_info "  missing packages: $missing"
            scrow_pkg_install "$(scrow_component_title "$name")" $missing
        else
            ui_ok "  packages present"
        fi
        scrow_deploy_component "$name"
        scrow_component_post "$name"
    done
    scrow_manifest_rebuild $(scrow_state_components)
}

scrow_components_update() {
    # Refresh component files to the current official state.
    local names=("$@") name
    scrow_backup_include_paths $(for n in "${names[@]}"; do scrow_component_paths "$n"; done)
    scrow_backup_create "before-update"
    for name in "${names[@]}"; do
        ui_step "Updating: ${C_BOLD}$(scrow_component_title "$name")${C_RESET}"
        scrow_deploy_component "$name"
        scrow_component_post "$name"
    done
    scrow_manifest_rebuild $(scrow_state_components)
}

# Resolve + expand a component list to include declared dependencies.
scrow_components_with_deps() {
    # scrow_components_with_deps <names...> -> prints resolved names, one per line
    local -a result=() expanded=("$@")
    local changed=1 name needs need j
    while (( changed )); do
        changed=0
        for name in "${expanded[@]}"; do
            needs="$(scrow_component_needs "$name")"
            for need in $needs; do
                if ! printf '%s\n' "${expanded[@]}" | grep -qx "$need"; then
                    expanded+=("$need")
                    changed=1
                fi
            done
        done
    done
    for name in "${expanded[@]}"; do
        printf '%s\n' "$name"
    done
}

# -----------------------------------------------------------------------------
# Per-component post-deploy hooks
# -----------------------------------------------------------------------------
scrow_component_post() {
    local name="$1"
    case "$name" in
        hyprland)  scrow_post_hyprland ;;
        waybar)    scrow_post_waybar ;;
        rofi)      scrow_post_rofi ;;
        terminal)  scrow_post_terminal ;;
        mako)      scrow_post_mako ;;
        shell)     scrow_post_shell ;;
        theming)   scrow_post_theming ;;
        utilities) scrow_post_utilities ;;
        security)  scrow_post_security ;;
        system)    scrow_post_system ;;
    esac
}

scrow_post_hyprland() {
    if command -v hyprpm >/dev/null 2>&1; then
        ui_step "Setting up hyprpm ScrollOverview plugin…"
        if [[ "$SCROW_DRY_RUN" == "1" ]]; then
            ui_dim "  [dry-run] hyprpm add/enable scroll-overview plugin"
            return 0
        fi
        scrow_log_tee "hyprpm add" hyprpm add https://github.com/yayuuu/hyprland-scroll-overview.git || true
        scrow_log_tee "hyprpm update" hyprpm update || true
        scrow_log_tee "hyprpm enable scrolloverview" hyprpm enable scrolloverview || true
    fi
}

scrow_post_waybar() {
    # launch.sh auto-detects the config; nothing else required.
    :
}

scrow_post_rofi() {
    :
}

scrow_post_terminal() {
    :
}

scrow_post_mako() {
    :
}

scrow_post_shell() {
    if command -v zsh >/dev/null 2>&1 && [[ "$(basename "$SHELL")" != "zsh" ]]; then
        local do_shell=0
        if [[ -n "${SCROW_SET_SHELL:-}" ]]; then
            do_shell="$SCROW_SET_SHELL"
        elif ui_confirm "Set zsh as your default shell?" "n"; then
            do_shell=1
        fi
        if [[ "$do_shell" == "1" ]]; then
            if [[ "$SCROW_DRY_RUN" != "1" ]]; then
                chsh -s "$(command -v zsh)" && ui_ok "Default shell set to zsh" \
                    || ui_warn "Could not change shell — run: chsh -s \$(which zsh)"
            else
                ui_dim "  [dry-run] chsh -s $(command -v zsh)"
            fi
        else
            ui_dim "  default shell left unchanged"
        fi
    fi
}

scrow_post_theming() {
    if [[ "$SCROW_DRY_RUN" == "1" ]]; then
        ui_dim "  [dry-run] gsettings dark scheme + fc-cache"
        return 0
    fi
    gsettings set org.gnome.desktop.interface color-scheme prefer-dark 2>/dev/null || true
    fc-cache -f >/dev/null 2>&1 || true
}

scrow_post_utilities() {
    ui_step "Setting executable permissions on SCROW scripts…"
    if [[ "$SCROW_DRY_RUN" == "1" ]]; then
        ui_dim "  [dry-run] chmod +x on ~/.local/bin and ~/user_scripts"
        return 0
    fi
    chmod +x "$HOME/.local/bin/"* 2>/dev/null || true
    chmod +x "$HOME"/user_scripts/*/*.sh 2>/dev/null || true
    chmod +x "$HOME/.config/waybar/"*.sh 2>/dev/null || true
    chmod +x "$HOME/security-hardening/"*.sh 2>/dev/null || true
}

scrow_post_security() {
    # Applies SCROW security hardening. Uses SCROW_APPLY_SECURITY when set
    # (pre-asked during an install flow), otherwise asks. Failure here must
    # never abort the rest of an installation.
    if [[ -n "${SCROW_APPLY_SECURITY:-}" ]]; then
        if [[ "$SCROW_APPLY_SECURITY" != "1" ]]; then
            ui_dim "  security hardening skipped"
            return 0
        fi
    else
        ui_step "Applying security hardening…"
        if ! ui_confirm "Apply SCROW security hardening? (firewall, sysctl, fail2ban)" "n"; then
            ui_dim "  skipped (can be applied later via Components → Security)"
            return 0
        fi
    fi
    if [[ "$SCROW_DRY_RUN" == "1" ]]; then
        ui_dim "  [dry-run] would deploy security configs to /etc"
        return 0
    fi
    scrow_need_root
    local sec="$SCROW_REPO/security-hardening"

    # --- System config files (recorded in the manifest as SCROW-owned) ---
    scrow_log_tee "deploy sshd hardening" sudo install -Dm644 "$sec/sshd_hardened.conf" /etc/ssh/sshd_config.d/99-hardened.conf || true
    scrow_manifest_write_deployed "etc/ssh/sshd_config.d/99-hardened.conf" "security-hardening/sshd_hardened.conf" "security"

    scrow_log_tee "deploy nftables" sudo install -Dm644 "$sec/nftables_hardened.conf" /etc/nftables.conf || true
    scrow_manifest_write_deployed "etc/nftables.conf" "security-hardening/nftables_hardened.conf" "security"

    scrow_log_tee "deploy sysctl" sudo install -Dm644 "$sec/sysctl_security.conf" /etc/sysctl.d/99-security.conf || true
    scrow_manifest_write_deployed "etc/sysctl.d/99-security.conf" "security-hardening/sysctl_security.conf" "security"

    scrow_log_tee "deploy fail2ban jail" sudo install -Dm644 "$sec/fail2ban_jail.local" /etc/fail2ban/jail.local || true
    scrow_manifest_write_deployed "etc/fail2ban/jail.local" "security-hardening/fail2ban_jail.local" "security"

    scrow_log_tee "deploy usb-scan script" sudo install -Dm755 "$sec/usb-scan.sh" /usr/local/bin/usb-scan.sh || true
    scrow_manifest_write_deployed "usr/local/bin/usb-scan.sh" "security-hardening/usb-scan.sh" "security"

    scrow_log_tee "deploy usb-scan rules" sudo install -Dm644 "$sec/usb-scan.rules" /etc/udev/rules.d/99-usb-scan.rules || true
    scrow_manifest_write_deployed "etc/udev/rules.d/99-usb-scan.rules" "security-hardening/usb-scan.rules" "security"

    scrow_log_tee "deploy nm firewall hook" sudo install -Dm755 /dev/stdin /etc/NetworkManager/dispatcher.d/99-reapply-firewall << 'HOOK' || true
#!/bin/bash
INTERFACE=$1
ACTION=$2
if [ "$ACTION" = "up" ]; then
    /usr/bin/nft -f /etc/nftables.conf 2>/dev/null
fi
HOOK
    scrow_manifest_write_deployed "etc/NetworkManager/dispatcher.d/99-reapply-firewall" "security-hardening/nftables_hardened.conf" "security"

    # --- Apply & enable ---
    scrow_log_tee "apply sysctl" sudo sysctl --system >/dev/null 2>&1 || true
    scrow_service_enable nftables
    scrow_service_enable fail2ban
    if [[ -d /etc/ssh ]] && command -v sshd >/dev/null 2>&1; then
        scrow_service_enable sshd
    fi
    scrow_service_disable avahi-daemon
    scrow_service_disable cups

    # LLMNR off
    if [[ -f /etc/systemd/resolved.conf ]]; then
        sudo sed -i 's/^#LLMNR=.*/LLMNR=no/' /etc/systemd/resolved.conf 2>/dev/null || true
        grep -q '^LLMNR=' /etc/systemd/resolved.conf 2>/dev/null \
            || echo 'LLMNR=no' | sudo tee -a /etc/systemd/resolved.conf >/dev/null
        scrow_log_tee "restart resolved" sudo systemctl restart systemd-resolved || true
    fi

    # SSH dir permissions
    chmod 700 ~/.ssh 2>/dev/null || true
    chmod 600 ~/.ssh/id_* ~/.ssh/*_key 2>/dev/null || true
    chmod 644 ~/.ssh/*.pub 2>/dev/null || true
    chmod 600 ~/.bash_history ~/.zsh_history 2>/dev/null || true

    # Fresh ClamAV definitions (may take a while; failures are non-fatal)
    ui_step "Updating ClamAV definitions…"
    scrow_log_tee "freshclam" sudo freshclam || true

    ui_ok "Security hardening applied"
}

scrow_post_system() {
    if [[ "$SCROW_DRY_RUN" == "1" ]]; then
        ui_dim "  [dry-run] SDDM theme, GRUB theme, pacman hooks"
        return 0
    fi
    scrow_need_root

    # Pacman hook scripts must be executable
    sudo chmod +x /etc/pacman.d/hooks/hyprpm-post-update.sh 2>/dev/null || true

    # GRUB theme — set GRUB_THEME without clobbering the user's grub config
    if [[ -d /boot/grub/themes/minegrub ]] && command -v grub-mkconfig >/dev/null 2>&1; then
        if grep -q '^GRUB_THEME=' /etc/default/grub 2>/dev/null; then
            sudo sed -i 's|^GRUB_THEME=.*|GRUB_THEME=/boot/grub/themes/minegrub/theme.txt|' /etc/default/grub 2>/dev/null || true
        else
            echo 'GRUB_THEME=/boot/grub/themes/minegrub/theme.txt' | sudo tee -a /etc/default/grub >/dev/null
        fi
        scrow_state_set GRUB_THEME 1
        ui_step "Regenerating GRUB configuration…"
        scrow_log_tee "grub-mkconfig" sudo grub-mkconfig -o /boot/grub/grub.cfg || ui_warn "Could not regenerate GRUB config"
    fi
}
