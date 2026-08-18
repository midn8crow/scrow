#!/usr/bin/env bash
# =============================================================================
# SCROW — package installers
# =============================================================================
# Functions for installing packages via pacman and paru.

# install-pacman — Install packages from official repos
install_pacman() {
    local -a pkgs=("$@")
    if (( ${#pkgs[@]} == 0 )); then return 0; fi
    x "pacman: ${pkgs[*]}" sudo pacman -S --needed --noconfirm "${pkgs[@]}"
}

# install-paru — Install packages from AUR via paru
install_paru() {
    local -a pkgs=("$@")
    if (( ${#pkgs[@]} == 0 )); then return 0; fi

    # Ensure paru is available
    if ! command -v paru >/dev/null 2>&1; then
        printf "${C_ERR}Error: paru is not installed.${C_RST}\n"
        printf "${C_ERR}Install paru first, then re-run the installer.${C_RST}\n"
        exit 1
    fi
    x "paru: ${pkgs[*]}" paru -S --needed --noconfirm "${pkgs[@]}"
}

# install-aur-auto — Auto-detect AUR packages and install them
# If a package is not found in official repos, route it to AUR.
install_aur_auto() {
    local -a official=() aur=()
    for pkg in "$@"; do
        if pacman -Si "$pkg" >/dev/null 2>&1; then
            official+=("$pkg")
        else
            aur+=("$pkg")
        fi
    done
    if (( ${#official[@]} > 0 )); then
        install_pacman "${official[@]}"
    fi
    if (( ${#aur[@]} > 0 )); then
        install_paru "${aur[@]}"
    fi
}
