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

    x "install base-devel" sudo pacman -S --needed --noconfirm base-devel

    local builddir
    builddir="$(mktemp -d)"
    register_tmp "$builddir"
    _log "Building paru in $builddir"

    x "clone paru-bin" git clone https://aur.archlinux.org/paru-bin.git "$builddir/paru-bin"
    x "build & install paru" bash -c "cd '$builddir/paru-bin' && makepkg -si --noconfirm"

    if command -v paru >/dev/null 2>&1; then
        printf "${C_OK}  [ OK ]${C_RST} paru installed: %s\n" "$(paru --version 2>/dev/null | head -1)"
        SCROW_PARU_READY=1
    else
        printf "${C_ERR}  Error: paru built but not in PATH.${C_RST}\n"
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
