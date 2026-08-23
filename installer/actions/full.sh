#!/usr/bin/env bash
# =============================================================================
# SCROW — full installation
# =============================================================================
# Installs all packages, deploys all configs, configures services, validates.

action_full() {
    prevent_sudo_or_root

    printf "\n${C_BOLD}${C_CYN}  SCROW — Full Installation${C_RST}\n"
    printf "  Version: %s | Distro: %s\n\n" "$SCROW_VERSION" "$SCROW_DISTRO_ID"

    _log "=== SCROW installation started ==="
    _log "REPO_ROOT=$REPO_ROOT DISTRO=$SCROW_DISTRO_ID VERSION=$SCROW_VERSION"

    # ── Step 1: Packages ──────────────────────────────────────────────────────
    printf "${C_BOLD}  [1/5] Installing packages…${C_RST}\n\n"

    local -a official_pkgs aur_pkgs
    read_manifest "$REPO_ROOT/packages/official.txt" official_pkgs
    read_manifest "$REPO_ROOT/packages/aur.txt" aur_pkgs

    printf "  Official: %d packages | AUR: %d packages\n\n" "${#official_pkgs[@]}" "${#aur_pkgs[@]}"

    # System update + keyring refresh
    make_sudo_keepalive
    pacman_update

    # Paru bootstrap (once)
    ensure_paru

    # Resolve conflicts
    resolve_conflicts

    # Install
    printf "\n  ${C_BOLD}Installing official packages…${C_RST}\n"
    install_official "${official_pkgs[@]}"

    printf "\n  ${C_BOLD}Installing AUR packages…${C_RST}\n"
    install_aur "${aur_pkgs[@]}"

    # Install hyprpm plugins (ScrollOverview etc.)
    printf "\n  ${C_BOLD}Installing Hyprland plugins…${C_RST}\n"
    install_hyprpm_plugins

    stop_sudo_keepalive

    # ── Step 2: Deploy configuration files ────────────────────────────────────
    printf "\n${C_BOLD}  [2/5] Deploying configuration files…${C_RST}\n\n"
    deploy_home

    # ── Step 3: Deploy system files ───────────────────────────────────────────
    printf "\n${C_BOLD}  [3/5] Deploying system files…${C_RST}\n\n"
    deploy_system

    # ── Step 4: Configure services ────────────────────────────────────────────
    printf "\n${C_BOLD}  [4/5] Configuring services…${C_RST}\n"
    setup_all

    # ── Step 5: Post-install ──────────────────────────────────────────────────
    printf "\n${C_BOLD}  [5/5] Post-install…${C_RST}\n\n"
    set_permissions
    try fc-cache -f

    write_deploy_manifest

    # ── Validate ──────────────────────────────────────────────────────────────
    validate_deployment || true

    _log "=== SCROW installation completed successfully ==="

    printf "\n"
    printf "${C_BOLD}${C_CYN}  ╔══════════════════════════════════════════════════╗${C_RST}\n"
    printf "${C_BOLD}${C_CYN}  ║            Installation complete!               ║${C_RST}\n"
    printf "${C_BOLD}${C_CYN}  ╚══════════════════════════════════════════════════╝${C_RST}\n"
    printf "\n"
    printf "  ${C_BOLD}Next steps:${C_RST}\n"
    printf "  1. Log out and select Hyprland from your display manager\n"
    printf "  2. Or reboot to ensure all services start correctly\n"
    printf "\n"
    printf "  ${C_DIM}Log saved to: %s${C_RST}\n" "$SCROW_LOG_FILE"
    printf "\n"
}
