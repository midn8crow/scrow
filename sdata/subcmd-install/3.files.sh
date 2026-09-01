# shellcheck shell=bash
# SCROW - 3. Deploy config files (sourced by setup, not executed directly)

printf "${CYAN}[$0]: 3. Deploying config files${RST}\n"

# Ensure XDG directories exist
ensure_xdg_dirs() {
    for d in "$XDG_BIN_HOME" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME"; do
        [[ -e "$d" ]] || mkdir -p "$d"
    done
}

# cp-based fallbacks when rsync is unavailable
_cp_dir() {
    local src="$1" dst="$2"
    mkdir -p "$dst"
    cp -a "$src"/. "$dst"/
    mkdir -p "$(dirname "$INSTALLED_LISTFILE")"
    find "$src" -type f -o -type l | while read -r f; do
        local rel="${f#"$src"/}"
        echo "$dst/$rel" >> "$INSTALLED_LISTFILE"
    done
}

_cp_dir_sync() {
    local src="$1" dst="$2"
    mkdir -p "$dst"
    rm -rf "$dst"/*
    cp -a "$src"/. "$dst"/
    mkdir -p "$(dirname "$INSTALLED_LISTFILE")"
    find "$src" -type f -o -type l | while read -r f; do
        local rel="${f#"$src"/}"
        echo "$dst/$rel" >> "$INSTALLED_LISTFILE"
    done
}

# Deployment primitives (rsync preferred, cp fallback)
if command -v rsync >/dev/null 2>&1; then
    rsync_dir() {
        mkdir -p "$2"
        local dest; dest="$(realpath -se "$2")"
        mkdir -p "$(dirname "$INSTALLED_LISTFILE")"
        rsync -a --out-format='%i %n' "$1"/ "$2"/ 2>/dev/null \
            | awk -v d="$dest" '$1 ~ /^>/{ sub(/^[^ ]+ /,""); printf d "/" $0 "\n" }' \
            >> "$INSTALLED_LISTFILE" || true
    }
    rsync_dir__sync() {
        mkdir -p "$2"
        local dest; dest="$(realpath -se "$2")"
        mkdir -p "$(dirname "$INSTALLED_LISTFILE")"
        rsync -a --delete --out-format='%i %n' "$1"/ "$2"/ 2>/dev/null \
            | awk -v d="$dest" '$1 ~ /^>/{ sub(/^[^ ]+ /,""); printf d "/" $0 "\n" }' \
            >> "$INSTALLED_LISTFILE" || true
    }
    rsync_dir__ignore_existing() {
        mkdir -p "$2"
        local dest; dest="$(realpath -se "$2")"
        mkdir -p "$(dirname "$INSTALLED_LISTFILE")"
        rsync -a --ignore-existing --out-format='%i %n' "$1"/ "$2"/ 2>/dev/null \
            | awk -v d="$dest" '$1 ~ /^>/{ sub(/^[^ ]+ /,""); printf d "/" $0 "\n" }' \
            >> "$INSTALLED_LISTFILE" || true
    }
else
    rsync_dir()       { _cp_dir "$@"; }
    rsync_dir__sync() { _cp_dir_sync "$@"; }
    rsync_dir__ignore_existing() {
        mkdir -p "$2"
        cp -an "$1"/. "$2"/ 2>/dev/null || true
    }
fi

cp_file() {
    mkdir -p "$(dirname "$2")"
    cp -f "$1" "$2"
    mkdir -p "$(dirname "$INSTALLED_LISTFILE")"
    realpath -se "$2" >> "$INSTALLED_LISTFILE"
}

# Firstrun detection
INSTALL_FIRSTRUN=true
[[ -f "${FIRSTRUN_FILE}" ]] && INSTALL_FIRSTRUN=false

# Backup step
if [[ ! "${SKIP_BACKUP}" == true ]]; then
    if [[ ! -d "$BACKUP_DIR" ]] || $INSTALL_FIRSTRUN; then
        printf "${YELLOW}  Backing up existing configs to: $BACKUP_DIR${RST}\n"
        backup_clashing_targets "$REPO_ROOT/dots/.config" "$XDG_CONFIG_HOME" "${BACKUP_DIR}/.config"
        backup_clashing_targets "$REPO_ROOT/dots/.local/share" "$XDG_DATA_HOME" "${BACKUP_DIR}/.local/share"
    fi
fi

# Deploy dotfiles: mirror dots/ tree into $HOME
printf "${BLUE}  Deploying .config/...${RST}\n"
rsync_dir__sync "$REPO_ROOT/dots/.config" "$XDG_CONFIG_HOME"

printf "${BLUE}  Deploying .local/...${RST}\n"
rsync_dir "$REPO_ROOT/dots/.local" "$HOME/.local"

printf "${BLUE}  Deploying shell files...${RST}\n"
for f in .zshrc .fzf-init.zsh .starship-init.zsh .zoxide-init.zsh; do
    [[ -f "$REPO_ROOT/dots/$f" ]] && cp_file "$REPO_ROOT/dots/$f" "$HOME/$f"
done

printf "${BLUE}  Deploying .icons/...${RST}\n"
[[ -d "$REPO_ROOT/dots/.icons" ]] && rsync_dir "$REPO_ROOT/dots/.icons" "$HOME/.icons"

printf "${BLUE}  Deploying .mozilla/...${RST}\n"
[[ -d "$REPO_ROOT/dots/.mozilla" ]] && rsync_dir__ignore_existing "$REPO_ROOT/dots/.mozilla" "$HOME/.mozilla"

printf "${BLUE}  Deploying Pictures/...${RST}\n"
[[ -d "$REPO_ROOT/dots/Pictures" ]] && rsync_dir "$REPO_ROOT/dots/Pictures" "$HOME/Pictures"

# Ensure scripts are executable
find "$XDG_BIN_HOME" -type f -exec chmod +x {} + 2>/dev/null || true
find "$XDG_CONFIG_HOME/waybar/scripts" -type f -exec chmod +x {} + 2>/dev/null || true
find "$XDG_CONFIG_HOME/hypr/scripts" -type f -exec chmod +x {} + 2>/dev/null || true
find "$XDG_CONFIG_HOME/hypr/hyprlock" -name "*.sh" -exec chmod +x {} + 2>/dev/null || true

# Generate firstrun marker
gen_firstrun() {
    mkdir -p "$(dirname "${FIRSTRUN_FILE}")"
    touch "${FIRSTRUN_FILE}"
    mkdir -p "$(dirname "${INSTALLED_LISTFILE}")"
    realpath -se "${FIRSTRUN_FILE}" >> "${INSTALLED_LISTFILE}"
}

gen_firstrun
dedup_and_sort_listfile "${INSTALLED_LISTFILE}" "${INSTALLED_LISTFILE}"

# Reload Hyprland if running
try hyprctl reload

# Deploy /etc files (SDDM theme, GRUB config)
deploy_etc() {
    printf "${BLUE}  Deploying /etc files...${RST}\n"

    # SDDM theme. SDDM reads local overrides only from /etc/sddm.conf.d/
    # (note the dot) — /etc/sddm/conf.d/ is NOT read by SDDM.
    if [[ -d "$REPO_ROOT/etc/sddm" ]]; then
        sudo mkdir -p /usr/share/sddm/themes
        if sudo cp -a "$REPO_ROOT/etc/sddm/themes/." /usr/share/sddm/themes/ 2>/dev/null; then
            printf "${GREEN}  [OK]${RST} SDDM pixie theme files deployed\n"
        else
            printf "${RED}  [FAIL]${RST} Could not deploy SDDM pixie theme\n"
        fi
        sudo mkdir -p /etc/sddm.conf.d
        if sudo cp -f "$REPO_ROOT/etc/sddm/conf.d/theme.conf" /etc/sddm.conf.d/theme.conf 2>/dev/null; then
            printf "${GREEN}  [OK]${RST} SDDM theme config set (Current=pixie)\n"
        else
            printf "${RED}  [FAIL]${RST} Could not write /etc/sddm.conf.d/theme.conf\n"
        fi
    fi

    # GRUB theme: deploy the minegrub theme tree into /boot and enable
    # GRUB_THEME, then regenerate grub.cfg so the menu picks it up.
    if [[ -d "$REPO_ROOT/boot/grub/themes/minegrub" ]]; then
        sudo mkdir -p /boot/grub/themes/minegrub
        if sudo cp -a "$REPO_ROOT/boot/grub/themes/minegrub/." /boot/grub/themes/minegrub/ 2>/dev/null; then
            printf "${GREEN}  [OK]${RST} minegrub GRUB theme deployed\n"
        else
            printf "${RED}  [FAIL]${RST} Could not deploy minegrub GRUB theme\n"
        fi
    fi

    # GRUB config
    if [[ -f "$REPO_ROOT/etc/default/grub" ]]; then
        sudo mkdir -p /etc/default
        if ! sudo cp -f "$REPO_ROOT/etc/default/grub" /etc/default/grub; then
            printf "${RED}  [FAIL]${RST} Could not write /etc/default/grub\n"
        fi
        # Enable GRUB_THEME if the repo ships a theme and it got deployed
        if [[ -f /boot/grub/themes/minegrub/theme.txt ]] \
           && ! grep -Eq '^GRUB_THEME=' /etc/default/grub 2>/dev/null; then
            sudo sed -i \
                's|^#\?GRUB_THEME=.*|GRUB_THEME="/boot/grub/themes/minegrub/theme.txt"|' \
                /etc/default/grub 2>/dev/null || true
        fi
        if command -v grub-mkconfig >/dev/null 2>&1; then
            printf "${BLUE}    Regenerating GRUB config...${RST}\n"
            sudo grub-mkconfig -o /boot/grub/grub.cfg 2>&1 | grep -Ev '^Found|searching for|^Generating' || true
            if [[ -f /boot/grub/grub.cfg ]]; then
                printf "${GREEN}  [OK]${RST} GRUB config regenerated\n"
            else
                printf "${RED}  [FAIL]${RST} grub-mkconfig produced no config\n"
            fi
        fi
    fi
}
deploy_etc

# Update hyprpm plugins
if command -v hyprpm >/dev/null 2>&1; then
    printf "${BLUE}  Updating hyprpm plugins...${RST}\n"
    hyprpm update 2>/dev/null || true
fi

printf "\n${GREEN}[$0]: Config files deployed${RST}\n"
printf "${CYAN}  Waybar: ${XDG_CONFIG_HOME}/waybar/${RST}\n"
printf "${CYAN}  Hyprland: ${XDG_CONFIG_HOME}/hypr/${RST}\n"
printf "${CYAN}  All .config/*: ${XDG_CONFIG_HOME}/${RST}\n"
printf "${CYAN}  Local bin: ${XDG_BIN_HOME}/${RST}\n"
