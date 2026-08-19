#!/usr/bin/env bash
# =============================================================================
# SCROW — package installers
# =============================================================================
# Functions for installing packages via pacman and paru.

# install-pacman — Install packages from official repos
install_pacman() {
    local -a pkgs=("$@")
    if (( ${#pkgs[@]} == 0 )); then return 0; fi
    x "pacman: ${#pkgs[@]} packages" sudo pacman -S --needed --noconfirm "${pkgs[@]}"
}

# install-paru — Install packages from AUR via paru
install_paru() {
    local -a pkgs=("$@")
    if (( ${#pkgs[@]} == 0 )); then return 0; fi

    # Ensure paru is available
    if ! command -v paru >/dev/null 2>&1; then
        printf "${C_ERR}Error: paru is not installed.${C_RST}\n"
        printf "${C_ERR}The paru bootstrap should have run earlier. Re-run the installer.${C_RST}\n"
        exit 1
    fi
    x "paru: ${#pkgs[@]} packages" paru -S --needed --noconfirm "${pkgs[@]}"
}
