#!/usr/bin/env bash
# =============================================================================
# SCROW — update
# =============================================================================
# Pulls latest repo content and redeploys everything.

action_update() {
    prevent_sudo_or_root

    printf "\n${C_BOLD}${C_CYN}  SCROW — Update${C_RST}\n\n"

    # Update system packages
    printf "${C_BOLD}  Updating system packages…${C_RST}\n\n"
    make_sudo_keepalive
    pacman_update

    local -a official_pkgs aur_pkgs
    read_manifest "$REPO_ROOT/packages/official.txt" official_pkgs
    read_manifest "$REPO_ROOT/packages/aur.txt" aur_pkgs
    ensure_paru
    resolve_conflicts
    install_official "${official_pkgs[@]}"
    install_aur "${aur_pkgs[@]}"
    stop_sudo_keepalive

    # Redeploy configs
    printf "\n${C_BOLD}  Redeploying configuration…${C_RST}\n\n"
    deploy_home
    deploy_system
    setup_all
    set_permissions
    try fc-cache -f
    write_deploy_manifest

    validate_deployment || true

    printf "\n${C_OK}  Update complete.${C_RST}\n\n"
}
