#!/usr/bin/env bash
# =============================================================================
# SCROW — file deployment
# =============================================================================
# Copies dotfiles from the repository to the user's home directory.
# Backs up existing files before overwriting.

printf "${C_BOLD}  [3/3] Deploying configuration files…${C_RST}\n"
printf "\n"

# ── Files/directories to deploy to $HOME ──────────────────────────────────────
# Each entry: source (relative to REPO_ROOT) → destination (relative to $HOME)
# This covers all dotfiles in the repository.
HOME_ITEMS=(
    .config/hypr
    .config/fcitx5
    .config/kdeconnect
    .config/waybar
    .config/rofi
    .config/scrowmenu
    .config/kitty
    .config/mako
    .config/starship.toml
    .config/gtk-3.0
    .config/gtk-4.0
    .config/qt6ct
    .config/matugen
    .config/dconf
    .config/fastfetch
    .config/mpv
    .config/btop
    .config/cava
    .config/yazi
    .config/yt-dlp
    .config/ytdlp-gui
    .config/moviebox-tui
    .config/pacseek
    .config/songrec
    .config/scrow-keysound
    .config/wayclick
    .config/qalculate
    .config/velo
    .config/viewnior
    .config/geeqie
    .config/Thunar
    .config/nemo
    .config/Mousepad
    .config/xdg-desktop-portal
    .config/user-dirs.conf
    .config/user-dirs.dirs
    .config/user-dirs.disable
    .config/user-dirs.locale
    .config/mimeapps.list
    .config/pavucontrol.ini
    .config/ibus
    .config/ambervideoeditor.org
    .config/chess-tui
    .config/gpu-recorder.conf
    .config/gpu-screen-recorder
    .config/Kitware
    .config/Meltytech
    .config/omarchy
    .config/QtProject.conf
    .config/xfce4
    .config/systemd
    .config/scrow
    .icons
    .local/bin
    .local/share/icons
    .local/share/fonts
    .mozilla
    .zshrc
    .starship-init.zsh
    .fzf-init.zsh
    .zoxide-init.zsh
    Pictures/Wallpapers
    user_scripts
    security-hardening
)

# ── Deploy ────────────────────────────────────────────────────────────────────
deploy_count=0
skip_count=0

for item in "${HOME_ITEMS[@]}"; do
    src="$REPO_ROOT/$item"
    dest="$HOME/$item"

    if [[ ! -e "$src" ]]; then
        printf "${C_DIM}  [SKIP]${C_RST} %s (not in repo)\n" "$item"
        ((skip_count++))
        continue
    fi

    # Backup if destination already exists
    backup_file "$dest"

    # Deploy (backup was already made above, so overwrite is safe)
    if [[ -d "$src" ]]; then
        mkdir -p "$dest"
        if command -v rsync >/dev/null 2>&1; then
            rsync -a "$src/" "$dest/" 2>/dev/null || true
        else
            cp -a "$src/"* "$dest/" 2>/dev/null || true
        fi
    elif [[ -f "$src" ]]; then
        mkdir -p "$(dirname "$dest")"
        cp -a "$src" "$dest" 2>/dev/null || true
    fi

    printf "${C_OK}  [ OK ]${C_RST} %s\n" "$item"
    ((deploy_count++))
done

# ── Deploy /etc files (requires sudo) ────────────────────────────────────────
printf "\n"
printf "  ${C_BOLD}System files (sudo required):${C_RST}\n"
make_sudo_keepalive

# SDDM theme
if [[ -d "$REPO_ROOT/etc/sddm" ]]; then
    backup_file /etc/sddm
    x "deploy SDDM config" sudo cp -a "$REPO_ROOT/etc/sddm/"* /etc/sddm/
fi

# GRUB theme
if [[ -d "$REPO_ROOT/boot/grub/themes/minegrub" ]]; then
    x "deploy GRUB theme" sudo cp -a "$REPO_ROOT/boot/grub/themes/minegrub" /boot/grub/themes/
    if [[ -f /etc/default/grub ]] && grep -q '^GRUB_THEME=' /etc/default/grub 2>/dev/null; then
        x "set GRUB theme" sudo sed -i 's|^GRUB_THEME=.*|GRUB_THEME=/boot/grub/themes/minegrub/theme.txt|' /etc/default/grub
    elif [[ -f /etc/default/grub ]]; then
        echo 'GRUB_THEME=/boot/grub/themes/minegrub/theme.txt' | sudo tee -a /etc/default/grub >/dev/null
    fi
    if command -v grub-mkconfig >/dev/null 2>&1; then
        x "regenerate GRUB config" sudo grub-mkconfig -o /boot/grub/grub.cfg
    fi
fi

# Pacman hooks
if [[ -d "$REPO_ROOT/etc/pacman.d/hooks" ]]; then
    x "deploy pacman hooks" sudo cp -a "$REPO_ROOT/etc/pacman.d/hooks/"* /etc/pacman.d/hooks/
fi

# Security hardening (optional)
if [[ -d "$REPO_ROOT/security-hardening" ]]; then
    printf "\n"
    printf "  ${C_BOLD}Security hardening (optional):${C_RST}\n"
    printf "${C_WARN}  Deploy security configs to /etc? [y/N]${C_RST} "
    read -r -p "  => " sec_choice
    case "${sec_choice,,}" in
        y|yes)
            sec="$REPO_ROOT/security-hardening"
            [[ -f "$sec/sshd_hardened.conf" ]] && x "deploy sshd hardening" sudo install -Dm644 "$sec/sshd_hardened.conf" /etc/ssh/sshd_config.d/99-hardened.conf
            [[ -f "$sec/nftables_hardened.conf" ]] && x "deploy nftables" sudo install -Dm644 "$sec/nftables_hardened.conf" /etc/nftables.conf
            [[ -f "$sec/sysctl_security.conf" ]] && x "deploy sysctl" sudo install -Dm644 "$sec/sysctl_security.conf" /etc/sysctl.d/99-security.conf
            [[ -f "$sec/fail2ban_jail.local" ]] && x "deploy fail2ban" sudo install -Dm644 "$sec/fail2ban_jail.local" /etc/fail2ban/jail.local
            [[ -f "$sec/usb-scan.sh" ]] && x "deploy usb-scan" sudo install -Dm755 "$sec/usb-scan.sh" /usr/local/bin/usb-scan.sh
            [[ -f "$sec/usb-scan.rules" ]] && x "deploy udev rules" sudo install -Dm644 "$sec/usb-scan.rules" /etc/udev/rules.d/99-usb-scan.rules
            x "apply sysctl" sudo sysctl --system >/dev/null 2>&1 || true
            sudo systemctl enable nftables.service 2>/dev/null || true
            sudo systemctl enable fail2ban.service 2>/dev/null || true
            ;;
        *)
            printf "${C_DIM}  Skipping security hardening.${C_RST}\n"
            ;;
    esac
fi

stop_sudo_keepalive

# ── Make scripts executable ───────────────────────────────────────────────────
printf "\n"
printf "  ${C_BOLD}Setting permissions:${C_RST}\n"
[[ -d "$HOME/.local/bin" ]] && find "$HOME/.local/bin" -maxdepth 1 -type f -exec chmod +x {} + 2>/dev/null || true
[[ -d "$HOME/user_scripts" ]] && find "$HOME/user_scripts" -type f -name '*.sh' -exec chmod +x {} + 2>/dev/null || true
[[ -d "$HOME/.config/waybar" ]] && find "$HOME/.config/waybar" -type f -name '*.sh' -exec chmod +x {} + 2>/dev/null || true
printf "${C_OK}  [ OK ]${C_RST} scripts made executable\n"

# ── Font cache ────────────────────────────────────────────────────────────────
printf "\n"
x "refresh font cache" fc-cache -f

printf "\n"
printf "${C_OK}  Deployed %d items (${C_WARN}%d skipped${C_OK}).${C_RST}\n" "$deploy_count" "$skip_count"
printf "\n"
