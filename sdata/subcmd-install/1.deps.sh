# shellcheck shell=bash
# SCROW — 1. Install dependencies (sourced by setup, not executed directly)

printf "${CYAN}[$0]: 1. Installing dependencies${RST}\n"

# ── Ensure yay (AUR helper) ───────────────────────────────────────────────────

SCROW_AUR_HELPER=""

ensure_yay() {
    if command -v yay >/dev/null 2>&1 && yay --version >/dev/null 2>&1; then
        SCROW_AUR_HELPER="yay"
        printf "${GREEN}  [OK]${RST} yay found: %s\n" "$(command -v yay)"
        return 0
    fi

    # Clean broken installs
    if command -v yay >/dev/null 2>&1 || command -v paru >/dev/null 2>&1; then
        printf "${YELLOW}  Broken AUR helper found — cleaning up...${RST}\n"
        sudo pacman -Rns --noconfirm yay paru paru-bin 2>/dev/null || true
    fi

    printf "${YELLOW}  Installing yay from AUR...${RST}\n"
    sudo pacman -S --needed --noconfirm base-devel git go

    local build_dir
    build_dir="$(mktemp -d -p "${XDG_CACHE_HOME:-$HOME/.cache}")"
    register_temp_file "$build_dir"

    git clone https://aur.archlinux.org/yay-bin.git "$build_dir/yay-bin" 2>/dev/null
    (cd "$build_dir/yay-bin" && makepkg --noconfirm -si --nocheck) || {
        printf "${RED}  yay build failed${RST}\n"
        rm -rf "$build_dir"
        return 1
    }
    rm -rf "$build_dir"

    if command -v yay >/dev/null 2>&1 && yay --version >/dev/null 2>&1; then
        SCROW_AUR_HELPER="yay"
        printf "${GREEN}  [OK]${RST} yay installed\n"
    else
        printf "${RED}  yay installed but broken${RST}\n"
        return 1
    fi
}

# ── Install official packages ─────────────────────────────────────────────────

install_official_packages() {
    local manifest="$REPO_ROOT/packages/official.txt"
    [[ ! -f "$manifest" ]] && { printf "${YELLOW}  No official.txt found, skipping${RST}\n"; return 0; }

    local -a pkgs=()
    while IFS= read -r line; do
        line="${line%%#*}"       # strip comments
        line="${line// /}"       # strip spaces
        [[ -n "$line" ]] && pkgs+=("$line")
    done < "$manifest"

    (( ${#pkgs[@]} == 0 )) && return 0
    printf "${BLUE}  Installing %d official packages...${RST}\n" "${#pkgs[@]}"
    sudo pacman -S --needed --noconfirm "${pkgs[@]}"
}

# ── Install AUR packages ─────────────────────────────────────────────────────

install_aur_packages() {
    local manifest="$REPO_ROOT/packages/aur.txt"
    [[ ! -f "$manifest" ]] && { printf "${YELLOW}  No aur.txt found, skipping${RST}\n"; return 0; }

    ensure_yay || { printf "${RED}  Cannot install AUR packages without an AUR helper${RST}\n"; return 1; }

    local -a pkgs=()
    while IFS= read -r line; do
        line="${line%%#*}"
        line="${line// /}"
        [[ -n "$line" ]] && pkgs+=("$line")
    done < "$manifest"

    (( ${#pkgs[@]} == 0 )) && return 0
    printf "${BLUE}  Installing %d AUR packages...${RST}\n" "${#pkgs[@]}"
    "$SCROW_AUR_HELPER" -S --needed --noconfirm "${pkgs[@]}"
}

# ── Install hyprpm plugins ────────────────────────────────────────────────────

install_hyprpm_plugins() {
    if ! command -v hyprpm >/dev/null 2>&1; then
        printf "${YELLOW}  hyprpm not found — skipping plugin install${RST}\n"
        return 0
    fi

    # ScrollOverview plugin (required by hypr/modules/workspace_overview.lua)
    if ! hyprpm list 2>/dev/null | grep -q scrolloverview; then
        printf "${YELLOW}  Installing ScrollOverview plugin...${RST}\n"
        local hp_log; hp_log="$(mktemp)"
        if hyprpm add https://github.com/yayuuu/hyprland-scroll-overview.git >"$hp_log" 2>&1; then
            printf "${GREEN}  [OK]${RST} ScrollOverview plugin added\n"
            hyprpm enable scrolloverview 2>/dev/null || true
        else
            printf "${YELLOW}  ScrollOverview install failed — desktop degrades gracefully${RST}\n"
        fi
        rm -f "$hp_log"
    fi

    hyprpm reload 2>/dev/null || true
}

# ── Run all dependency steps ──────────────────────────────────────────────────

ensure_yay
install_official_packages
install_aur_packages
install_hyprpm_plugins

printf "${GREEN}[$0]: Dependencies installed${RST}\n"
