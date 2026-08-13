#!/usr/bin/env bash
# =============================================================================
# SCROW - component definitions
# =============================================================================
# Every component is derived from what the SCROW repository actually ships.
# Format (pipe separated):
#   name|title|desc|needs|packages|aur|paths
#
#   needs    : component names that must be selected first (dependency order)
#   packages : official repo packages (pacman)
#   aur      : AUR packages (paru). Unknown packages are auto-routed to AUR.
#   paths    : repo-relative paths this component owns (deployed to $HOME,
#              except etc/ and boot/ which are deployed to the filesystem root).
# =============================================================================

SCROW_COMPONENTS=(
    "hyprland|Hyprland|Wayland compositor, lockscreen, idle & session stack||hyprland hyprlock hypridle hyprutils uwsm xdg-desktop-portal-hyprland xdg-desktop-portal-gtk xdg-utils wl-clipboard cliphist grim slurp swappy satty hyprshot swww gnome-keyring network-manager-applet blueman nm-connection-editor kdeconnect fcitx5 fcitx5-configtool fcitx5-gtk fcitx5-qt pipewire pipewire-pulse wireplumber pipewire-alsa pipewire-jack pavucontrol polkit-kde-agent|hyprpolkitagent openbangla-keyboard-fcitx-git hypr-kdeconnect-fix-git|.config/hypr"

    "waybar|Waybar|Status bar with multiple switchable themes|theming utilities|waybar cava playerctl jq|waybar-cava-git|.config/waybar"

    "rofi|Rofi|Application launcher, menus & control center|theming utilities|rofi rofi-emoji||.config/rofi .config/scrowmenu"

    "terminal|Terminal|Kitty terminal emulator||kitty||.config/kitty"

    "mako|Mako|Notification daemon|theming|mako||.config/mako"

    "shell|Zsh Shell|Zsh with Starship prompt, fzf & zoxide||zsh zsh-autosuggestions zsh-syntax-highlighting starship fzf zoxide eza bat fd ripgrep||.zshrc .starship-init.zsh .fzf-init.zsh .zoxide-init.zsh .config/starship.toml"

    "theming|Theming|GTK/Qt themes, cursors, icons, fonts & default wallpaper||adw-gtk-theme qt6ct kvantum nwg-look papirus-icon-theme ttf-jetbrains-mono-nerd noto-fonts noto-fonts-emoji ttf-font-awesome ttf-cascadia-code|matugen|.config/gtk-3.0 .config/gtk-4.0 .config/qt6ct .config/matugen .config/dconf .icons .local/share/icons .local/share/fonts Pictures/Wallpapers"

    "utilities|Utilities|SCROW scripts, tools, user scripts & app configs||fastfetch btop htop mpv cava yazi yt-dlp brightnessctl playerctl ffmpeg imagemagick jq tree p7zip wget curl git unzip xdg-user-dirs wtype pacman-contrib|awww mpvpaper gpu-screen-recorder hyprlauncher wlr-randr ytdlp-gui|.local/bin user_scripts .config/scrow .config/systemd .config/fastfetch .config/mpv .config/btop .config/cava .config/yazi .config/yt-dlp .config/ytdlp-gui .config/moviebox-tui .config/pacseek .config/songrec .config/scrow-keysound .config/wayclick .config/qalculate .config/velo .config/viewnior .config/geeqie .config/Thunar .config/nemo .config/Mousepad .config/xdg-desktop-portal .config/user-dirs.conf .config/user-dirs.dirs .config/user-dirs.disable .config/user-dirs.locale .config/mimeapps.list .config/pavucontrol.ini .mozilla"

    "security|Security Hardening|Firewall, AUR scanner & system hardening||nftables fail2ban clamav rkhunter pacman-contrib bubblewrap lynis||security-hardening"

    "system|System Integration|SDDM theme, GRUB theme & pacman hooks||sddm grub efibootmgr||etc/sddm etc/default/grub etc/pacman.d/hooks boot/grub/themes/minegrub"
)

SCROW_COMPONENT_ALL="hyprland waybar rofi terminal mako shell theming utilities security system"

# -----------------------------------------------------------------------------
# Accessors
# -----------------------------------------------------------------------------
scrow_component_field() {
    # scrow_component_field <name> <index>  (1-based across pipe fields)
    local name="$1" idx="$2" comp
    for comp in "${SCROW_COMPONENTS[@]}"; do
        if [[ "${comp%%|*}" == "$name" ]]; then
            IFS='|' read -r -a _f <<< "$comp"
            printf '%s\n' "${_f[$idx]}"
            return 0
        fi
    done
    return 1
}

scrow_component_title()      { scrow_component_field "$1" 1; }
scrow_component_desc()       { scrow_component_field "$1" 2; }
scrow_component_needs()      { scrow_component_field "$1" 3; }
scrow_component_packages()   { scrow_component_field "$1" 4; }
scrow_component_aur()        { scrow_component_field "$1" 5; }
scrow_component_paths()      { scrow_component_field "$1" 6; }

scrow_component_exists() {
    local name="$1" comp
    for comp in "${SCROW_COMPONENTS[@]}"; do
        [[ "${comp%%|*}" == "$name" ]] && return 0
    done
    return 1
}

scrow_component_names() {
    local comp
    for comp in "${SCROW_COMPONENTS[@]}"; do
        printf '%s\n' "${comp%%|*}"
    done
}
