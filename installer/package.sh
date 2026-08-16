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

# Record a package that was just installed so queries reflect reality
# immediately — the one-hour cache would otherwise hide it until it expires.
scrow_pm_cache_install() {
    [[ "$SCROW_DRY_RUN" == "1" ]] && return 0
    mkdir -p "$SCROW_PM_CACHE_DIR"
    grep -qx "$1" "$SCROW_PM_QUERY_CACHE" 2>/dev/null || echo "$1" >> "$SCROW_PM_QUERY_CACHE" 2>/dev/null
}

# Install a single package, deciding official vs AUR automatically.
scrow_pm_install() {
    local pkg="$1"
    if scrow_pm_installed "$pkg"; then
        scrow_log "pkg: $pkg (already installed)"
        return 0
    fi

    if scrow_pm_is_aur "$pkg"; then
        # paru is initialized ONCE up front by scrow_ensure_paru. This guard is
        # defensive only — components never build paru themselves.
        if ! (( SCROW_PARU_AVAILABLE == 1 )) && ! scrow_paru_available; then
            echo "  ${C_ERR}      AUR package $pkg needs paru, but paru is not installed.${C_RESET}"
            return 1
        fi
        echo "  ${C_DIM}AUR: $pkg${C_RESET}"
        [[ "$SCROW_DRY_RUN" == "1" ]] && { echo "  [dry-run] paru -S --needed $pkg"; return 0; }
        scrow_run "install $pkg" paru -S --needed --noconfirm "$pkg" || return 1
    else
        echo "  ${C_DIM}Official: $pkg${C_RESET}"
        [[ "$SCROW_DRY_RUN" == "1" ]] && { echo "  [dry-run] pacman -S --needed $pkg"; return 0; }
        scrow_run_sudo "install $pkg" pacman -S --needed --noconfirm "$pkg" || return 1
    fi
    scrow_pm_cache
    scrow_pm_cache_install "$pkg"
}

scrow_pm_is_aur() {
    local pkg="$1"
    case "$pkg" in
        paru) return 1 ;; # always official
    esac
    pacman -Si "$pkg" >/dev/null 2>&1 && return 1
    return 0
}

# -----------------------------------------------------------------------------
# paru (AUR helper)
# -----------------------------------------------------------------------------
# paru is a GLOBAL installation prerequisite, NOT a per-component dependency.
# It is initialized at most ONCE per invocation, before any component installs
# AUR packages. Components NEVER clone/build paru — they call the already
# initialized `paru` binary. See scrow_ensure_paru.
SCROW_PARU_AVAILABLE=0
SCROW_PARU_INITIALIZED=0

# Re-check whether `paru` exists and set SCROW_PARU_AVAILABLE. Returns 0 when
# available. This is the ONLY place that decides paru availability.
scrow_paru_available() {
    if command -v paru >/dev/null 2>&1; then
        SCROW_PARU_AVAILABLE=1
        return 0
    fi
    SCROW_PARU_AVAILABLE=0
    return 1
}

# Install the Arch build toolchain required to build AUR packages with makepkg:
# git (to fetch PKGBUILDs) plus the base-devel group (make, gcc, binutils,
# pkgconf, fakeroot, debugedit, …). Installs only what is missing, then
# VERIFIES the critical members actually exist — a missing fakeroot/debugedit
# must never reach the paru build.
scrow_ensure_build_dependencies() {
    scrow_stage 2 "Build toolchain"
    if ! command -v git >/dev/null 2>&1; then
        echo "  ${C_DIM}Installing git…${C_RESET}"
        scrow_run_sudo "install git" pacman -S --needed --noconfirm git || return 1
    fi

    local -a missing=() member
    while IFS= read -r member; do
        [[ -n "$member" ]] || continue
        pacman -Q "$member" >/dev/null 2>&1 || missing+=("$member")
    done < <(pacman -Sg base-devel 2>/dev/null)
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "  ${C_DIM}Installing base-devel (missing: ${missing[*]})…${C_RESET}"
        scrow_run_sudo "install base-devel" pacman -S --needed --noconfirm base-devel || return 1
    fi

    # Verify the explicit toolchain members makepkg needs. Do not assume the
    # group install covered them (e.g. an older system without debugedit).
    local dep
    for dep in fakeroot debugedit make gcc binutils pkgconf; do
        if ! pacman -Q "$dep" >/dev/null 2>&1; then
            echo "  ${C_ERR}      required build dependency missing: $dep${C_RESET}"
            return 1
        fi
    done
    return 0
}

# Initialize paru ONCE for this invocation. Fail-fast: if paru cannot be
# installed the whole installation stops — AUR packages are unavailable, and
# building paru per-component (as previous versions did) is wrong.
scrow_ensure_paru() {
    # At most once per invocation — even if a caller forgets the guard, the
    # build path can never run twice.
    if (( SCROW_PARU_INITIALIZED == 1 )); then
        scrow_paru_available || return 1
        return 0
    fi
    SCROW_PARU_INITIALIZED=1

    # Already installed? Zero builds, zero clones.
    scrow_paru_available && {
        scrow_log "pkg: paru (already available)"
        return 0
    }

    [[ "$SCROW_DRY_RUN" == "1" ]] && {
        scrow_stage 2 "Build toolchain"
        scrow_stage 3 "Initialize paru"
        echo "  [dry-run] build prerequisites, then clone paru + makepkg -si"
        SCROW_PARU_AVAILABLE=1
        return 0
    }

    # makepkg refuses to run as root — AUR packages must be built by a normal
    # user. Report this clearly instead of letting makepkg fail silently.
    if [[ "$(id -u)" == "0" ]]; then
        echo "  ${C_ERR}      paru cannot be built as root — run SCROW as a normal user (makepkg refuses to run as root)${C_RESET}"
        return 1
    fi
    scrow_need_root

    # Prerequisites FIRST (fakeroot, debugedit, make, gcc, …), then paru.
    scrow_ensure_build_dependencies || {
        echo "  ${C_ERR}      Failed to install the build prerequisites.${C_RESET}"
        return 1
    }

    scrow_stage 3 "Initialize paru"
    echo "  ${C_DIM}Installing paru (AUR helper)…${C_RESET}"

    local tmp
    tmp="$(mktemp -d)"
    scrow_run "clone paru" git clone --depth 1 https://aur.archlinux.org/paru.git "$tmp/paru" || {
        rm -rf "$tmp"
        echo "  ${C_ERR}      could not fetch paru from the AUR — check network, then retry${C_RESET}"
        return 1
    }
    scrow_run "build paru" makepkg -si --noconfirm -D "$tmp/paru" || {
        rm -rf "$tmp"
        echo "  ${C_ERR}      Failed to install paru.${C_RESET}"
        echo "  ${C_DIM}      Required for AUR packages.${C_RESET}"
        return 1
    }
    rm -rf "$tmp"

    # Re-verify immediately — never assume the build succeeded.
    scrow_paru_available || {
        echo "  ${C_ERR}      paru build finished but \`paru\` is not on PATH.${C_RESET}"
        return 1
    }
    echo "  ${C_OK}    ✓ paru available${C_RESET}"
    scrow_log "pkg: paru initialized"
    return 0
}
