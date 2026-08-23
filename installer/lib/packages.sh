#!/usr/bin/env bash
# =============================================================================
# SCROW — package management
# =============================================================================
# Read manifests, ensure paru, install official + AUR packages.

SCROW_PARU_READY=0
SCROW_AUR_HELPER=""  # Set to "paru" or "yay" by ensure_paru()

# ── Read a manifest file into an array ────────────────────────────────────────
read_manifest() {
    local -n out=$2
    mapfile -t out < <(grep -Ev '^[[:space:]]*(#|$)' "$1" 2>/dev/null | sort -u)
}

# ── Ensure paru is installed and functional (ONCE per invocation) ──────────────
# Build dir under $HOME to avoid /tmp disk quota on VMs
_SCROW_BUILD_ROOT="${XDG_CACHE_HOME:-$HOME/.cache}/scrow-build"

_ensure_build_root() {
    mkdir -p "$_SCROW_BUILD_ROOT" 2>/dev/null || true
    register_tmp "$_SCROW_BUILD_ROOT"
}

# Build a Rust-based AUR helper (paru) from source
_build_paru() {
    local build_dir="$1"
    sudo pacman -S --needed --noconfirm base-devel rust

    _log "Cloning paru..."
    git clone https://aur.archlinux.org/paru.git "$build_dir/paru" 2>/dev/null
    _log "Building paru..."
    (cd "$build_dir/paru" && makepkg --noconfirm -cf --nocheck) 2>/dev/null

    local pkg
    pkg=$(find "$build_dir/paru" -name '*.pkg.tar.*' -print -quit 2>/dev/null)
    if [[ -n "$pkg" ]]; then
        sudo pacman -U --noconfirm "$pkg" 2>/dev/null
        return 0
    fi
    return 1
}

# Build yay (Go-based AUR helper) from source — fallback
_build_yay() {
    local build_dir="$1"
    sudo pacman -S --needed --noconfirm base-devel go

    _log "Cloning yay..."
    git clone https://aur.archlinux.org/yay.git "$build_dir/yay" 2>/dev/null
    _log "Building yay..."
    (cd "$build_dir/yay" && makepkg --noconfirm -cf --nocheck) 2>/dev/null

    local pkg
    pkg=$(find "$build_dir/yay" -name '*.pkg.tar.*' -print -quit 2>/dev/null)
    if [[ -n "$pkg" ]]; then
        sudo pacman -U --noconfirm "$pkg" 2>/dev/null
        return 0
    fi
    return 1
}

# Verify an AUR helper actually runs (handles ghost/broken installs)
_is_helper_usable() {
    local helper="$1"
    command -v "$helper" >/dev/null 2>&1 && "$helper" --version >/dev/null 2>&1
}

ensure_paru() {
    (( SCROW_PARU_READY )) && return 0

    # Already installed and working?
    if _is_helper_usable paru; then
        printf "${C_OK}  [ OK ]${C_RST} paru found: %s\n" "$(command -v paru)"
        _log "paru already installed: $(command -v paru)"
        SCROW_AUR_HELPER="paru"
        SCROW_PARU_READY=1
        return 0
    fi

    # Broken install? Clean it up (try both paru and paru-bin)
    if command -v paru >/dev/null 2>&1 || pacman -Qi paru-bin &>/dev/null; then
        printf "${C_WARN}  paru/paru-bin found but broken — cleaning up…${C_RST}\n"
        _log "Cleaning broken paru/paru-bin"
        sudo pacman -Rns --noconfirm paru paru-bin 2>/dev/null || true
    fi

    _ensure_build_root
    local build_dir
    build_dir="$(mktemp -d -p "$_SCROW_BUILD_ROOT")"

    printf "${C_WARN}  paru not found — building from AUR…${C_RST}\n"
    _log "Installing paru from AUR (build dir: $build_dir)"

    # Try paru first (Rust-based)
    if _build_paru "$build_dir"; then
        sudo ldconfig 2>/dev/null || true
        if _is_helper_usable paru; then
            printf "${C_OK}  [ OK ]${C_RST} paru installed: %s\n" "$(paru --version 2>/dev/null | head -1)"
            SCROW_AUR_HELPER="paru"
            SCROW_PARU_READY=1
            rm -rf "$build_dir"
            return 0
        fi
        printf "${C_WARN}  paru built but broken after ldconfig — trying yay fallback…${C_RST}\n"
    else
        printf "${C_WARN}  paru build failed — trying yay fallback…${C_RST}\n"
        _log "paru build failed, falling back to yay"
    fi

    # Fallback: yay (Go-based, faster build, no disk quota issues)
    if _build_yay "$build_dir"; then
        sudo ldconfig 2>/dev/null || true
        if _is_helper_usable yay; then
            printf "${C_OK}  [ OK ]${C_RST} yay installed (paru fallback): %s\n" "$(yay --version 2>/dev/null | head -1)"
            _log "yay installed as fallback: $(command -v yay)"
            SCROW_AUR_HELPER="yay"
            SCROW_PARU_READY=1
            rm -rf "$build_dir"
            return 0
        fi
    fi

    rm -rf "$build_dir"
    printf "${C_ERR}  Error: both paru and yay failed to build${C_RST}\n"
    _log "CRITICAL: both paru and yay failed to install"
    exit 1
}

# ── Install official packages ─────────────────────────────────────────────────
install_official() {
    local -a pkgs=("$@")
    (( ${#pkgs[@]} == 0 )) && return 0
    x "pacman: ${#pkgs[@]} packages" sudo pacman -S --needed --noconfirm "${pkgs[@]}"
}

# ── Install AUR packages ─────────────────────────────────────────────────────
install_aur() {
    local -a pkgs=("$@")
    (( ${#pkgs[@]} == 0 )) && return 0
    ensure_paru
    x "${SCROW_AUR_HELPER:-paru}: ${#pkgs[@]} packages" "${SCROW_AUR_HELPER:-paru}" -S --needed --noconfirm "${pkgs[@]}"
}

# ── Resolve known conflicts ───────────────────────────────────────────────────
resolve_conflicts() {
    if pacman -Qi jack2 &>/dev/null; then
        x "remove jack2 (conflicts with pipewire-jack)" sudo pacman -Rdd --noconfirm jack2
    fi
}

# ── Install hyprpm plugins required by config ─────────────────────────────────
install_hyprpm_plugins() {
    if ! command -v hyprpm >/dev/null 2>&1; then
        printf "${C_WARN}  hyprpm not found — skipping plugin install${C_RST}\n"
        _log "WARN: hyprpm not found, skipping plugin install"
        return 0
    fi

    # ScrollOverview plugin (required by .config/hypr/modules/workspace_overview.lua)
    if ! hyprpm list 2>/dev/null | grep -q scrolloverview; then
        printf "${C_WARN}  Installing ScrollOverview plugin…${C_RST}\n"
        _log "Installing hyprland-scroll-overview via hyprpm"
        local _hp_log
        _hp_log="$(mktemp)"
        if hyprpm add https://github.com/yayuuu/hyprland-scroll-overview.git >"$_hp_log" 2>&1; then
            printf "${C_OK}  [ OK ]${C_RST} ScrollOverview plugin added\n"
            _log "OK: ScrollOverview plugin added"
            hyprpm enable scrolloverview 2>/dev/null || true
        else
            printf "${C_WARN}  ScrollOverview plugin install failed — desktop will degrade gracefully${C_RST}\n"
            _log "WARN: ScrollOverview plugin install failed: $(cat "$_hp_log")"
            rm -f "$_hp_log"
            return 0
        fi
        rm -f "$_hp_log"
    fi

    hyprpm reload 2>/dev/null || true
}
