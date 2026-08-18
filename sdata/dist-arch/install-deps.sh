#!/usr/bin/env bash
# =============================================================================
# SCROW — Arch Linux dependency installation
# =============================================================================
# Installs all packages needed for SCROW on Arch Linux.
# Uses pacman for official repos, paru for AUR.

# Ensure makepkg doesn't reset sudo credentials
if [[ -z "${PACMAN_AUTH:-}" ]]; then
    export PACMAN_AUTH="sudo"
fi

# Paru bootstrap — only if not already installed
install_paru_if_needed() {
    if command -v paru >/dev/null 2>&1; then
        printf "${C_OK}  [ OK ]${C_RST} paru already installed\n"
        return 0
    fi

    printf "${C_WARN}  paru not found — installing paru from AUR…${C_RST}\n"

    # Install build dependencies
    x "install base-devel" sudo pacman -S --needed --noconfirm base-devel

    local builddir
    builddir="$(mktemp -d)"

    # Clone paru-bin (binary package, faster than building from source)
    x "clone paru" git clone https://aur.archlinux.org/paru-bin.git "$builddir/paru-bin"
    x "build paru" bash -c "cd '$builddir/paru-bin' && makepkg -si --noconfirm"

    rm -rf "$builddir"
}

# ── Pacman packages (official repos) ─────────────────────────────────────────
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

# ── AUR packages ──────────────────────────────────────────────────────────────
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

# ── Execute installation ──────────────────────────────────────────────────────
printf "  ${C_BOLD}Installing paru…${C_RST}\n"
showfun install_paru_if_needed
v install_paru_if_needed

printf "\n"
printf "  ${C_BOLD}Updating system…${C_RST}\n"
x "pacman -Syu" sudo pacman -Syu --noconfirm

printf "\n"
printf "  ${C_BOLD}Installing official packages (${#PACMAN_PACKAGES[@]} packages)…${C_RST}\n"
install_pacman "${PACMAN_PACKAGES[@]}"

printf "\n"
printf "  ${C_BOLD}Installing AUR packages (${#AUR_PACKAGES[@]} packages)…${C_RST}\n"
install_paru "${AUR_PACKAGES[@]}"
