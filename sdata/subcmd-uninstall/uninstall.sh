# shellcheck shell=bash
# SCROW — Uninstall (sourced by setup, not executed directly)

printf "\n${RED}${BOLD}=== SCROW Uninstall ===${RST}\n"
printf "${RED}This will remove all SCROW-managed files and packages.${RST}\n\n"

# Confirm
printf "${YELLOW}Are you sure? (y/N): ${RST}"
read -r answer
[[ "$answer" =~ ^[Yy]$ ]] || { printf "Aborted.\n"; exit 0; }

# ── Remove deployed files ─────────────────────────────────────────────────────

remove_files() {
    printf "${CYAN}Removing deployed files...${RST}\n"

    # Config dirs
    local -a config_dirs=(
        hypr waybar rofi mako kitty cava wlogout matugen swaylock
        Kvantum qt5ct qt6ct electron25
    )
    for d in "${config_dirs[@]}"; do
        [[ -d "$HOME/.config/$d" ]] && rm -rf "$HOME/.config/$d"
    done

    # Local files
    rm -rf "$HOME/.local/bin/wallpaper-"*.sh
    rm -rf "$HOME/.local/bin/scrow-menu-tui"
    rm -rf "$HOME/.local/bin/keybinds"
    rm -rf "$HOME/.local/bin/force-kill.sh"
    rm -rf "$HOME/.local/share/fonts"
    rm -rf "$HOME/.local/share/icons"

    # Shell files
    rm -f "$HOME/.zshrc" "$HOME/.fzf-init.zsh" "$HOME/.starship-init.zsh" "$HOME/.zoxide-init.zsh"

    # Pictures
    rm -rf "$HOME/Pictures/Wallpapers"

    # Icons
    rm -rf "$HOME/.icons"

    printf "${GREEN}  [OK]${RST} Files removed\n"
}

# ── Remove packages ───────────────────────────────────────────────────────────

remove_packages() {
    printf "${CYAN}Removing installed packages...${RST}\n"

    local manifest="$REPO_ROOT/packages/official.txt"
    if [[ -f "$manifest" ]]; then
        local -a pkgs=()
        while IFS= read -r line; do
            line="${line%%#*}"
            line="${line// /}"
            [[ -n "$line" ]] && pkgs+=("$line")
        done < "$manifest"

        if (( ${#pkgs[@]} > 0 )); then
            sudo pacman -Rns --noconfirm "${pkgs[@]}" 2>/dev/null || true
        fi
    fi

    # Remove AUR packages if helper available
    if command -v yay >/dev/null 2>&1; then
        local aur_manifest="$REPO_ROOT/packages/aur.txt"
        if [[ -f "$aur_manifest" ]]; then
            local -a aur_pkgs=()
            while IFS= read -r line; do
                line="${line%%#*}"
                line="${line// /}"
                [[ -n "$line" ]] && aur_pkgs+=("$line")
            done < "$aur_manifest"

            if (( ${#aur_pkgs[@]} > 0 )); then
                yay -Rns --noconfirm "${aur_pkgs[@]}" 2>/dev/null || true
            fi
        fi
    fi

    printf "${GREEN}  [OK]${RST} Packages removed\n"
}

# ── Remove hyprpm plugins ─────────────────────────────────────────────────────

remove_hyprpm_plugins() {
    if command -v hyprpm >/dev/null 2>&1; then
        printf "${CYAN}Removing hyprpm plugins...${RST}\n"
        hyprpm remove scrolloverview 2>/dev/null || true
        hyprpm reload 2>/dev/null || true
        printf "${GREEN}  [OK]${RST} Plugins removed\n"
    fi
}

# ── Remove system setup ───────────────────────────────────────────────────────

remove_system_setup() {
    printf "${CYAN}Removing system setup...${RST}\n"

    # Remove kernel modules
    sudo rm -f /etc/modules-load.d/i2c-dev.conf /etc/modules-load.d/uinput.conf 2>/dev/null || true

    # Remove SDDM theme
    sudo rm -rf /usr/share/sddm/themes/pixie 2>/dev/null || true
    sudo rm -f /etc/sddm/conf.d/theme.conf 2>/dev/null || true

    # Disable services
    sudo systemctl disable sddm 2>/dev/null || true
    sudo systemctl disable bluetooth 2>/dev/null || true

    printf "${GREEN}  [OK]${RST} System setup removed\n"
}

# ── Run uninstall ─────────────────────────────────────────────────────────────

remove_files
remove_packages
remove_hyprpm_plugins
remove_system_setup

printf "\n${GREEN}${BOLD}=== SCROW Uninstalled ===${RST}\n"
printf "${CYAN}Backups kept in: ~/scrow-original-dots-backup/${RST}\n"
printf "${CYAN}Reboot recommended.${RST}\n\n"
