#!/usr/bin/env bash
# =============================================================================
# SCROW — Arch Linux dependency installation
# =============================================================================
# Installs all packages needed for SCROW on Arch Linux.
# Uses pacman for official repos, paru for AUR.
#
# Order of operations:
#   1. Prompt for sudo (once)
#   2. System update (pacman -Syu) with diagnostics
#   3. Paru bootstrap (if not already installed)
#   4. Install official packages
#   5. Install AUR packages

# Ensure makepkg doesn't reset sudo credentials
if [[ -z "${PACMAN_AUTH:-}" ]]; then
    export PACMAN_AUTH="sudo"
fi

# ── Step 1: Prompt for sudo password once, keep alive ────────────────────────
printf "\n"
printf "  ${C_BOLD}Authenticating…${C_RST}\n"
make_sudo_keepalive
printf "${C_OK}  [ OK ]${C_RST} sudo authenticated\n"

# ── Step 2: System update (BEFORE paru) ───────────────────────────────────────
printf "\n"
printf "  ${C_BOLD}System prerequisite update…${C_RST}\n"
pacman_update

# ── Step 3: Paru bootstrap ────────────────────────────────────────────────────
# Only runs if paru is not already installed. Never rebuilds.
printf "\n"
printf "  ${C_BOLD}Paru initialization…${C_RST}\n"

install_paru_if_needed() {
    if command -v paru >/dev/null 2>&1; then
        printf "${C_OK}  [ OK ]${C_RST} paru already installed: $(paru --version 2>/dev/null | head -1)\n"
        _log "paru already installed: $(command -v paru)"
        return 0
    fi

    printf "${C_WARN}  paru not found — installing from AUR…${C_RST}\n"
    _log "Installing paru from AUR"

    # Install build prerequisites (system is already updated)
    x "install base-devel" sudo pacman -S --needed --noconfirm base-devel

    local builddir
    builddir="$(mktemp -d)"
    _log "Building paru in $builddir"

    # Clone paru-bin (binary package, faster than building from source)
    x "clone paru-bin" git clone https://aur.archlinux.org/paru-bin.git "$builddir/paru-bin"
    x "build & install paru" bash -c "cd '$builddir/paru-bin' && makepkg -si --noconfirm"

    rm -rf "$builddir"

    # Verify paru is available
    if command -v paru >/dev/null 2>&1; then
        printf "${C_OK}  [ OK ]${C_RST} paru installed: $(paru --version 2>/dev/null | head -1)\n"
        _log "paru installed successfully"
    else
        printf "${C_ERR}  Error: paru installation completed but paru is not in PATH.${C_RST}\n"
        printf "${C_ERR}  Try opening a new terminal or running: source ~/.bashrc${C_RST}\n"
        exit 1
    fi
}

showfun install_paru_if_needed
v install_paru_if_needed

# ── Package lists ─────────────────────────────────────────────────────────────
# Deduplicated list from SCROW component definitions.
PACMAN_PACKAGES=(
    # Core Hyprland
    hyprland hyprlock hypridle hyprutils uwsm
    xdg-desktop-portal-hyprland xdg-desktop-portal-gtk
    xdg-utils wl-clipboard cliphist grim slurp swappy satty hyprshot swww
    gnome-keyring network-manager-applet blueman nm-connection-editor
    kdeconnect
    fcitx5 fcitx5-configtool fcitx5-gtk fcitx5-qt
    pipewire pipewire-pulse wireplumber pipewire-alsa pipewire-jack pavucontrol
    polkit-kde-agent

    # Waybar
    waybar cava playerctl jq

    # Rofi
    rofi rofi-emoji

    # Terminal
    kitty

    # Mako
    mako

    # Shell
    zsh zsh-autosuggestions zsh-syntax-highlighting starship fzf zoxide eza bat fd ripgrep

    # Theming
    adw-gtk-theme qt6ct kvantum nwg-look papirus-icon-theme
    ttf-jetbrains-mono-nerd noto-fonts noto-fonts-emoji ttf-font-awesome ttf-cascadia-code

    # Utilities
    fastfetch btop htop mpv yazi brightnessctl
    ffmpeg imagemagick tree p7zip wget curl git unzip
    xdg-user-dirs wtype pacman-contrib

    # System
    sddm grub efibootmgr

    # Security (optional, but install binaries)
    nftables fail2ban clamav rkhunter bubblewrap lynis
)

AUR_PACKAGES=(
    hyprpolkitagent
    openbangla-keyboard-fcitx-git
    hypr-kdeconnect-fix-git
    waybar-cava-git
    matugen
    awww
    mpvpaper
    gpu-screen-recorder
    hyprlauncher
    wlr-randr
    ytdlp-gui
)

# ── Step 4: Install official packages ─────────────────────────────────────────
printf "\n"
printf "  ${C_BOLD}Installing official packages (%d packages)…${C_RST}\n" "${#PACMAN_PACKAGES[@]}"
install_pacman "${PACMAN_PACKAGES[@]}"

# ── Step 5: Install AUR packages ──────────────────────────────────────────────
printf "\n"
printf "  ${C_BOLD}Installing AUR packages (%d packages)…${C_RST}\n" "${#AUR_PACKAGES[@]}"
install_paru "${AUR_PACKAGES[@]}"
