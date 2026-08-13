#!/usr/bin/env bash
# =============================================================================
# SCROW — package manager access
# =============================================================================
# Thin, deterministic wrapper around pacman/paru. Every package the installer
# touches goes through here so queries, dry-run and caching behave the same.
# =============================================================================

SCROW_PM_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/scrow"
SCROW_PM_QUERY_CACHE="$SCROW_PM_CACHE_DIR/installed.pkgs"

# Cache the list of explicitly installed packages (fast offline queries).
scrow_pm_cache() {
    if [[ -f "$SCROW_PM_QUERY_CACHE" ]]; then
        local age
        age="$(( $(date +%s) - $(stat -c %Y "$SCROW_PM_QUERY_CACHE" 2>/dev/null || echo 0) ))"
        [[ "$age" -lt 3600 ]] && return 0
    fi
    mkdir -p "$SCROW_PM_CACHE_DIR"
    pacman -Qeq > "$SCROW_PM_QUERY_CACHE" 2>/dev/null || touch "$SCROW_PM_QUERY_CACHE"
}

scrow_pm_installed() {
    scrow_pm_cache
    grep -qx "$1" "$SCROW_PM_QUERY_CACHE" 2>/dev/null
}

# Install a single package, deciding official vs AUR automatically.
scrow_pm_install() {
    local pkg="$1"
    if scrow_pm_installed "$pkg"; then
        scrow_log "pkg: $pkg (already installed)"
        return 0
    fi

    if scrow_pm_is_aur "$pkg"; then
        echo "  ${C_DIM}AUR: $pkg${C_RESET}"
        [[ "$SCROW_DRY_RUN" == "1" ]] && { echo "  [dry-run] paru -S --needed $pkg"; return 0; }
        scrow_run "install $pkg" paru -S --needed --noconfirm "$pkg" || return 1
    else
        echo "  ${C_DIM}Official: $pkg${C_RESET}"
        [[ "$SCROW_DRY_RUN" == "1" ]] && { echo "  [dry-run] pacman -S --needed $pkg"; return 0; }
        scrow_run_sudo "install $pkg" pacman -S --needed --noconfirm "$pkg" || return 1
    fi
    scrow_pm_cache
}

scrow_pm_is_aur() {
    local pkg="$1"
    case "$pkg" in
        paru) return 1 ;; # always official
    esac
    pacman -Si "$pkg" >/dev/null 2>&1 && return 1
    return 0
}

# Install paru (AUR helper) if missing — uses a dedicated temporary directory.
scrow_pm_install_paru() {
    if command -v paru >/dev/null 2>&1; then
        scrow_log "pkg: paru (already installed)"
        return 0
    fi
    echo "  ${C_DIM}Installing paru (AUR helper)…${C_RESET}"
    [[ "$SCROW_DRY_RUN" == "1" ]] && { echo "  [dry-run] git clone paru + makepkg -si"; return 0; }
    scrow_need_root
    local tmp
    tmp="$(mktemp -d)"
    scrow_run "clone paru" git clone --depth 1 https://aur.archlinux.org/paru.git "$tmp/paru" || return 1
    scrow_run "build paru" makepkg -si --noconfirm -D "$tmp/paru" || return 1
    rm -rf "$tmp"
}
