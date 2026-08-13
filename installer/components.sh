#!/usr/bin/env bash
# =============================================================================
# SCROW — component definitions
# =============================================================================
# What SCROW ships. Each component is derived from what the repository
# actually contains. Format (pipe separated):
#   name|title|desc|needs|packages|aur|paths
#
#   needs    : component names that must be present first (dependency order)
#   packages : official repo packages (pacman)
#   aur      : AUR packages (paru). Unknown packages are auto-routed to AUR.
#   paths    : repo-relative paths this component owns (deployed to $HOME,
#              except etc/ and boot/ which deploy to the filesystem root).
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

# -----------------------------------------------------------------------------
# Accessors
# -----------------------------------------------------------------------------
scrow_component_field() {
    # scrow_component_field <name> <index>  (1-based across pipe fields)
    local name="$1" idx="$2" comp
    for comp in "${SCROW_COMPONENTS[@]}"; do
        if [[ "${comp%%|*}" == "$name" ]]; then
            IFS='|' read -r -a _scrow_fields <<< "$comp"
            printf '%s\n' "${_scrow_fields[$idx]}"
            return 0
        fi
    done
    return 1
}

scrow_component_title()    { scrow_component_field "$1" 1; }
scrow_component_desc()     { scrow_component_field "$1" 2; }
scrow_component_needs()    { scrow_component_field "$1" 3; }
scrow_component_packages() { scrow_component_field "$1" 4; }
scrow_component_aur()      { scrow_component_field "$1" 5; }
scrow_component_paths()    { scrow_component_field "$1" 6; }

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

# -----------------------------------------------------------------------------
# Dependency handling
# -----------------------------------------------------------------------------
# Return 0 if a component (by name) is currently installed per state.
scrow_component_installed() {
    local name="$1"
    printf '%s\n' $(scrow_state_components) | grep -qx "$name"
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
        echo "  ${C_DIM}Setting up hyprpm ScrollOverview plugin…${C_RESET}"
        [[ "$SCROW_DRY_RUN" == "1" ]] && { echo "  [dry-run] hyprpm add/enable scroll-overview"; return 0; }
        scrow_run "hyprpm add" hyprpm add https://github.com/yayuuu/hyprland-scroll-overview.git || true
        scrow_run "hyprpm update" hyprpm update || true
        scrow_run "hyprpm enable" hyprpm enable scrolloverview || true
    fi
}

scrow_post_waybar()    { :; }
scrow_post_rofi()      { :; }
scrow_post_terminal()  { :; }
scrow_post_mako()      { :; }

scrow_post_shell() {
    if command -v zsh >/dev/null 2>&1 && [[ "$(basename "${SHELL:-}")" != "zsh" ]]; then
        if [[ "${SCROW_SET_SHELL:-0}" == "1" ]]; then
            if [[ "$SCROW_DRY_RUN" == "1" ]]; then
                echo "  [dry-run] chsh -s $(command -v zsh)"
            elif chsh -s "$(command -v zsh)"; then
                echo "  ${C_OK}Default shell set to zsh${C_RESET}"
            else
                echo "  ${C_WARN}Could not change shell — run: chsh -s \$(which zsh)${C_RESET}"
            fi
        fi
    fi
}

scrow_post_theming() {
    [[ "$SCROW_DRY_RUN" == "1" ]] && { echo "  [dry-run] gsettings dark scheme + fc-cache"; return 0; }
    gsettings set org.gnome.desktop.interface color-scheme prefer-dark 2>/dev/null || true
    fc-cache -f >/dev/null 2>&1 || true
}

scrow_post_utilities() {
    echo "  ${C_DIM}Making SCROW scripts executable…${C_RESET}"
    if [[ "$SCROW_DRY_RUN" == "1" ]]; then
        echo "  [dry-run] chmod +x ~/.local/bin, ~/user_scripts, waybar scripts"
        return 0
    fi
    chmod +x "$HOME/.local/bin/"* 2>/dev/null || true
    chmod +x "$HOME"/user_scripts/*/*.sh 2>/dev/null || true
    chmod +x "$HOME/.config/waybar/"*.sh 2>/dev/null || true
    chmod +x "$HOME/security-hardening/"*.sh 2>/dev/null || true
}

scrow_post_security() {
    if [[ "${SCROW_APPLY_SECURITY:-0}" != "1" ]]; then
        echo "  ${C_DIM}Security hardening skipped${C_RESET}"
        return 0
    fi
    [[ "$SCROW_DRY_RUN" == "1" ]] && { echo "  [dry-run] would deploy security configs to /etc"; return 0; }
    scrow_need_root
    local sec="$SCROW_REPO/security-hardening"

    scrow_run_sudo "deploy sshd hardening" install -Dm644 "$sec/sshd_hardened.conf" /etc/ssh/sshd_config.d/99-hardened.conf || true
    scrow_manifest_deployed "etc/ssh/sshd_config.d/99-hardened.conf" "security-hardening/sshd_hardened.conf" "security"
    scrow_run_sudo "deploy nftables" install -Dm644 "$sec/nftables_hardened.conf" /etc/nftables.conf || true
    scrow_manifest_deployed "etc/nftables.conf" "security-hardening/nftables_hardened.conf" "security"
    scrow_run_sudo "deploy sysctl" install -Dm644 "$sec/sysctl_security.conf" /etc/sysctl.d/99-security.conf || true
    scrow_manifest_deployed "etc/sysctl.d/99-security.conf" "security-hardening/sysctl_security.conf" "security"
    scrow_run_sudo "deploy fail2ban jail" install -Dm644 "$sec/fail2ban_jail.local" /etc/fail2ban/jail.local || true
    scrow_manifest_deployed "etc/fail2ban/jail.local" "security-hardening/fail2ban_jail.local" "security"
    scrow_run_sudo "deploy usb-scan script" install -Dm755 "$sec/usb-scan.sh" /usr/local/bin/usb-scan.sh || true
    scrow_manifest_deployed "usr/local/bin/usb-scan.sh" "security-hardening/usb-scan.sh" "security"
    scrow_run_sudo "deploy usb-scan rules" install -Dm644 "$sec/usb-scan.rules" /etc/udev/rules.d/99-usb-scan.rules || true
    scrow_manifest_deployed "etc/udev/rules.d/99-usb-scan.rules" "security-hardening/usb-scan.rules" "security"

    scrow_run_sudo "apply sysctl" sysctl --system >/dev/null 2>&1 || true
    scrow_service_enable nftables
    scrow_service_enable fail2ban
    if [[ -d /etc/ssh ]] && command -v sshd >/dev/null 2>&1; then
        scrow_service_enable sshd
    fi
    scrow_service_disable avahi-daemon
    scrow_service_disable cups
}

scrow_post_system() {
    [[ "$SCROW_DRY_RUN" == "1" ]] && { echo "  [dry-run] SDDM theme, GRUB theme, pacman hooks"; return 0; }
    scrow_need_root
    scrow_run_sudo "chmod pacman hook" chmod +x /etc/pacman.d/hooks/hyprpm-post-update.sh || true
    if [[ -d /boot/grub/themes/minegrub ]] && command -v grub-mkconfig >/dev/null 2>&1; then
        if grep -q '^GRUB_THEME=' /etc/default/grub 2>/dev/null; then
            scrow_run_sudo "set grub theme" sed -i 's|^GRUB_THEME=.*|GRUB_THEME=/boot/grub/themes/minegrub/theme.txt|' /etc/default/grub || true
        else
            echo 'GRUB_THEME=/boot/grub/themes/minegrub/theme.txt' | sudo tee -a /etc/default/grub >/dev/null 2>&1
        fi
        scrow_state_set GRUB_THEME 1
        echo "  ${C_DIM}Regenerating GRUB configuration…${C_RESET}"
        scrow_run_sudo "grub-mkconfig" grub-mkconfig -o /boot/grub/grub.cfg || echo "  ${C_WARN}Could not regenerate GRUB config${C_RESET}"
    fi
}
