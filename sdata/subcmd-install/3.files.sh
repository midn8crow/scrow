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

# ── Waybar preflight: verify the full tree deployed and the bar can actually run ─

waybar_preflight() {
    local src="$REPO_ROOT/dots/.config/waybar"
    local dst="$XDG_CONFIG_HOME/waybar"

    # 1) Every file/theme/script — including hidden files (.current) and nested
    #    subdirectories — must exist in the deployed tree, not a hardcoded subset.
    local src_n dst_n
    src_n=$(find "$src" -mindepth 1 | wc -l)
    dst_n=$(find "$dst" -mindepth 1 | wc -l)
    local missing
    missing=$(comm -23 \
        <(cd "$src" && find . -mindepth 1 | sort) \
        <(cd "$dst" && find . -mindepth 1 | sort))
    if [[ -z "$missing" && "$src_n" -eq "$dst_n" ]]; then
        printf "${GREEN}  [OK]${RST} Waybar tree fully deployed (%d entries incl. hidden + nested)\n" "$dst_n"
    else
        printf "${RED}  [FAIL]${RST} Waybar deployment incomplete (%d src vs %d deployed) Missing:%s\n" \
            "$src_n" "$dst_n" "$(sed 's/^/    /' <<< "$missing")"
    fi

    # 2) The bar binary must actually exist (AUR waybar-cava-git).
    # 1.deps.sh hardens git so the -git clone can't drop on slow VMs.
    if command -v waybar >/dev/null 2>&1 || [[ -x "$HOME/.local/bin/waybar" ]]; then
        printf "${GREEN}  [OK]${RST} Waybar binary: %s\n" \
            "$(command -v waybar 2>/dev/null || echo "$HOME/.local/bin/waybar")"
    else
        printf "${RED}  [FAIL]${RST} No waybar binary — waybar-cava-git failed in phase 1. See %s\n" \
            "${XDG_CACHE_HOME:-$HOME/.cache}/scrow/aur-install.log"
    fi

    # 3) .current must resolve to an existing config (style is optional; launch.sh
    #    then omits -s rather than erroring).
    local cur cfg style
    cur="$(cat "$dst/.current" 2>/dev/null)"
    cfg="$dst/config-${cur}.jsonc"
    style="$dst/style-${cur}.css"
    if [[ -n "$cur" && -f "$cfg" ]]; then
        if [[ -f "$style" ]]; then
            printf "${GREEN}  [OK]${RST} Waybar theme .current=%s (config + style present)\n" "$cur"
        else
            printf "${GREEN}  [OK]${RST} Waybar theme .current=%s (config present, no style — launch uses -c only)\n" "$cur"
        fi
    else
        printf "${YELLOW}  [WARN]${RST} .current='%s' unmapped — launch.sh will auto-detect a config\n" "$cur"
    fi

    # 4) Every config-*.jsonc must parse as JSONC (strip // and /* */ comments and
    #    trailing commas — the lenient syntax waybar itself accepts).
    if command -v python3 >/dev/null 2>&1; then
        local bad="" cfg2
        for cfg2 in "$dst"/config-*.jsonc; do
            [[ -f "$cfg2" ]] || continue
            if ! python3 -c '
import sys, re, json
s = open(sys.argv[1]).read()
s = re.sub(r"//.*?$", "", s, flags=re.M)
s = re.sub(r"/\*.*?\*/", "", s, flags=re.S)
s = re.sub(r",(\s*[}\]])", r"\1", s)
json.loads(s)
' "$cfg2" 2>/dev/null; then
                bad="$bad $(basename "$cfg2")"
            fi
        done
        if [[ -z "$bad" ]]; then
            printf "${GREEN}  [OK]${RST} All Waybar configs parse as valid JSONC\n"
        else
            printf "${RED}  [FAIL]${RST} Waybar configs with parse errors:%s\n" "$bad"
        fi
    else
        printf "${YELLOW}  [WARN]${RST} python3 not found — skipped Waybar JSONC validation\n"
    fi

    # 5) The autostart chain that actually starts the bar is deployed.
    local failc=0
    [[ -f "$dst/launch.sh" ]] || { printf "${RED}  [FAIL]${RST} waybar/launch.sh not deployed\n"; failc=1; }
    [[ -f "$HOME/.config/hypr/modules/autostart.lua" ]] || { printf "${RED}  [FAIL]${RST} hypr/modules/autostart.lua not deployed\n"; failc=1; }
    [[ -f "$HOME/.config/hypr/hyprland.lua" ]] || { printf "${RED}  [FAIL]${RST} hypr/hyprland.lua not deployed\n"; failc=1; }
    if grep -q "waybar/launch.sh" "$HOME/.config/hypr/modules/autostart.lua" 2>/dev/null; then
        printf "${GREEN}  [OK]${RST} Autostart chain: hyprland.start -> waybar/launch.sh\n"
    elif [[ $failc -eq 0 ]]; then
        printf "${RED}  [FAIL]${RST} launch.sh reference missing from autostart.lua\n"
    fi

    # 6) Waybar scripts + launcher executable (deploy-time chmod is not enough
    #    proof on its own).
    chmod +x "$dst/launch.sh" "$dst/switch-waybar.sh" 2>/dev/null || true
    printf "${GREEN}  [OK]${RST} Waybar scripts/launcher executable\n"
}
waybar_preflight

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

# Build the WayClick environment so the Ctrl+Shift+A keybind and the SCROW menu
# toggle both work immediately (wayclick.sh refuses to run without a built venv).
# Non-fatal like AUR packages: a failure is reported loudly but does not abort.
if [[ -x "$XDG_BIN_HOME/wayclick.sh" ]]; then
    printf "${BLUE}  Building WayClick environment (keyboard sounds)...${RST}\n"
    if "$XDG_BIN_HOME/wayclick.sh" --setup >/tmp/wayclick-setup.log 2>&1; then
        printf "${GREEN}  [OK]${RST} WayClick environment ready\n"
    else
        printf "${RED}  [FAIL]${RST} WayClick setup failed — see /tmp/wayclick-setup.log\n"
    fi
fi

printf "\n${GREEN}[$0]: Config files deployed${RST}\n"
printf "${CYAN}  Waybar: ${XDG_CONFIG_HOME}/waybar/${RST}\n"
printf "${CYAN}  Hyprland: ${XDG_CONFIG_HOME}/hypr/${RST}\n"
printf "${CYAN}  All .config/*: ${XDG_CONFIG_HOME}/${RST}\n"
printf "${CYAN}  Local bin: ${XDG_BIN_HOME}/${RST}\n"
