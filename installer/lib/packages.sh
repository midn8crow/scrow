#!/usr/bin/env bash
# =============================================================================
# SCROW — package management
# =============================================================================
# Read manifests, ensure paru, install official + AUR packages.

SCROW_PARU_READY=0

# ── Read a manifest file into an array ────────────────────────────────────────
read_manifest() {
    local -n out=$2
    mapfile -t out < <(grep -Ev '^[[:space:]]*(#|$)' "$1" 2>/dev/null | sort -u)
}

# ── Ensure paru is installed and functional (ONCE per invocation) ──────────────
ensure_paru() {
    (( SCROW_PARU_READY )) && return 0

    if command -v paru >/dev/null 2>&1; then
        # Verify paru actually works (handles broken libalpm after pacman update)
        if paru --version >/dev/null 2>&1; then
            printf "${C_OK}  [ OK ]${C_RST} paru found: %s\n" "$(command -v paru)"
            _log "paru already installed: $(command -v paru)"
            SCROW_PARU_READY=1
            return 0
        else
            printf "${C_WARN}  paru found but broken — rebuilding…${C_RST}\n"
            _log "paru found but broken, rebuilding"
        fi
    fi

    printf "${C_WARN}  paru not found — building from AUR…${C_RST}\n"
    _log "Installing paru from AUR"

    x "install base-devel rust" sudo pacman -S --needed --noconfirm base-devel rust

    local builddir
    builddir="$(mktemp -d)"
    register_tmp "$builddir"
    _log "Building paru in $builddir"

    # Build from source (NOT paru-bin) so the binary links against
    # the system's actual libalpm.so.N — pre-built binaries break
    # when pacman upgrades libalpm.
    x "clone paru" git clone https://aur.archlinux.org/paru.git "$builddir/paru"
    x "build & install paru" bash -c "cd '$builddir/paru' && makepkg -si --noconfirm"

    # Refresh dynamic linker cache so the new binary finds libalpm.so.N
    sudo ldconfig 2>/dev/null || true

    if command -v paru >/dev/null 2>&1 && paru --version >/dev/null 2>&1; then
        printf "${C_OK}  [ OK ]${C_RST} paru installed: %s\n" "$(paru --version 2>/dev/null | head -1)"
        SCROW_PARU_READY=1
    else
        printf "${C_ERR}  Error: paru built but still broken — try: sudo ldconfig${C_RST}\n"
        exit 1
    fi
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
    x "paru: ${#pkgs[@]} packages" paru -S --needed --noconfirm "${pkgs[@]}"
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
