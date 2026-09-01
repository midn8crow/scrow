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

    if command -v yay >/dev/null 2>&1 || command -v paru >/dev/null 2>&1; then
        printf "${YELLOW}  Broken AUR helper found — cleaning up...${RST}\n"
        sudo pacman -Rns --noconfirm yay paru paru-bin 2>/dev/null || true
    fi

    printf "${YELLOW}  Installing yay from AUR...${RST}\n"
    sudo pacman -S --needed --noconfirm base-devel git go

    local build_dir
    build_dir="$(mktemp -d -p "${XDG_CACHE_HOME:-$HOME/.cache}")"

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

# ── Read manifest into array ──────────────────────────────────────────────────

read_manifest() {
    local manifest="$1"
    local -n out=$2
    out=()
    while IFS= read -r line; do
        line="${line%%#*}"
        line="${line// /}"
        [[ -n "$line" ]] && out+=("$line")
    done < "$manifest"
}

# ── Install official packages in batches of 15 ───────────────────────────────

install_official_packages() {
    local manifest="$REPO_ROOT/packages/official.txt"
    [[ ! -f "$manifest" ]] && { printf "${YELLOW}  No official.txt found, skipping${RST}\n"; return 0; }

    local -a pkgs=()
    read_manifest "$manifest" pkgs
    (( ${#pkgs[@]} == 0 )) && return 0

    printf "${BLUE}  Installing %d official packages...${RST}\n" "${#pkgs[@]}"
    sudo pacman -S --needed --noconfirm "${pkgs[@]}"
}

# ── Install AUR packages one by one ───────────────────────────────────────────

install_aur_packages() {
    local manifest="$REPO_ROOT/packages/aur.txt"
    [[ ! -f "$manifest" ]] && { printf "${YELLOW}  No aur.txt found, skipping${RST}\n"; return 0; }

    ensure_yay || { printf "${RED}  Cannot install AUR packages without an AUR helper${RST}\n"; return 1; }

    local -a pkgs=()
    read_manifest "$manifest" pkgs
    (( ${#pkgs[@]} == 0 )) && return 0

    local total=${#pkgs[@]}
    local failed=0

    printf "${BLUE}  Installing %d AUR packages (one at a time to avoid OOM)...${RST}\n" "$total"

    local i=0
    while (( i < total )); do
        local pkg="${pkgs[$i]}"
        local num=$(( i + 1 ))
        printf "${BLUE}  [%d/%d] %s${RST}\n" "$num" "$total" "$pkg"
        "$SCROW_AUR_HELPER" -S --needed --noconfirm "$pkg" 2>&1 || {
            printf "${YELLOW}  Failed: %s — skipping${RST}\n" "$pkg"
            failed=$(( failed + 1 ))
        }
        i=$(( i + 1 ))
        sleep 2
    done

    if (( failed > 0 )); then
        printf "${YELLOW}  %d AUR packages failed (non-fatal)${RST}\n" "$failed"
    fi
}

# ── Install hyprpm plugins ────────────────────────────────────────────────────

install_hyprpm_plugins() {
    if ! command -v hyprpm >/dev/null 2>&1; then
        printf "${YELLOW}  hyprpm not found — skipping plugin install${RST}\n"
        return 0
    fi

    # hyprpm add fails with "Headers outdated" unless hyprpm is first synced to
    # the ABI of the currently running/installed Hyprland. Plain `update` skips
    # ABI-only header bumps; -f forces a real header sync/build.
    printf "${YELLOW}  Syncing hyprpm headers/builds...${RST}\n"
    hyprpm update -f 2>/dev/null || hyprpm update 2>/dev/null || true

    if ! hyprpm list 2>/dev/null | grep -q scrolloverview; then
        printf "${YELLOW}  Installing ScrollOverview plugin...${RST}\n"
        local hp_log; hp_log="$(mktemp)"
        if hyprpm add https://github.com/yayuuu/hyprland-scroll-overview.git >"$hp_log" 2>&1; then
            printf "${GREEN}  [OK]${RST} ScrollOverview plugin added\n"
        else
            printf "${RED}  ScrollOverview plugin add FAILED:${RST}\n"
            sed 's/^/    /' "$hp_log"
            rm -f "$hp_log"
            return 1
        fi
        rm -f "$hp_log"
    fi

    # Enable (persists state) then reload to actually load it. If headers are
    # still stale this reports "Outdated headers" — surface it instead of hiding.
    hyprpm enable scrolloverview 2>/dev/null || true
    if hyprpm reload 2>&1 | grep -qi "outdated"; then
        printf "${YELLOW}  Plugin headers outdated — forcing sync and reload${RST}\n"
        hyprpm update -f 2>/dev/null || true
        hyprpm enable scrolloverview 2>/dev/null || true
    fi
    hyprpm reload 2>/dev/null || true
}

# ── Run all dependency steps ──────────────────────────────────────────────────

ensure_yay
install_official_packages
install_aur_packages
install_hyprpm_plugins

printf "${GREEN}[$0]: Dependencies installed${RST}\n"
