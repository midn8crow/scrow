#!/usr/bin/env bash
# =============================================================================
# SCROW - package manager
# =============================================================================
# pacman for official Arch packages, paru for AUR. Packages that cannot be
# resolved in the official repos are automatically routed to AUR.
# =============================================================================

scrow_pkg_in_repo() {
    local pkg="$1"
    pacman -Si "$pkg" >/dev/null 2>&1
}

scrow_pkg_installed() {
    local pkg="$1"
    pacman -Q "$pkg" >/dev/null 2>&1
}

scrow_pkg_missing() {
    local pkg
    for pkg in "$@"; do
        scrow_pkg_installed "$pkg" || printf '%s\n' "$pkg"
    done
}

scrow_pkg_split() {
    # Split "$@" into SCROW_PKG_REPO / SCROW_PKG_AUR arrays.
    SCROW_PKG_REPO=()
    SCROW_PKG_AUR=()
    local pkg
    for pkg in "$@"; do
        if scrow_pkg_in_repo "$pkg"; then
            SCROW_PKG_REPO+=("$pkg")
        else
            SCROW_PKG_AUR+=("$pkg")
        fi
    done
}

scrow_ensure_paru() {
    if command -v paru >/dev/null 2>&1; then
        return 0
    fi
    ui_step "Installing AUR helper (paru)…"
    if [[ "$SCROW_DRY_RUN" == "1" ]]; then
        ui_dim "  [dry-run] would build & install paru-bin from the AUR"
        return 0
    fi
    scrow_need_root
    scrow_log_tee "install base-devel+git" sudo pacman -S --needed --noconfirm base-devel git
    local tmp
    tmp="$(mktemp -d)"
    scrow_log_tee "clone paru-bin" git clone --depth 1 https://aur.archlinux.org/paru-bin.git "$tmp/paru-bin"
    ( cd "$tmp/paru-bin" && makepkg -si --noconfirm ) >> "$SCROW_CURRENT_LOG" 2>&1 || true
    rm -rf "$tmp"
    command -v paru >/dev/null 2>&1 || { scrow_log "ERROR paru not installed"; return 1; }
    ui_ok "paru ready"
}

scrow_pkg_install() {
    # scrow_pkg_install <label> <package...>
    local label="$1"
    shift
    [[ $# -eq 0 ]] && return 0

    scrow_pkg_split "$@"
    local rc=0

    if [[ ${#SCROW_PKG_REPO[@]} -gt 0 ]]; then
        ui_step "Installing ${label} (pacman)…"
        scrow_log "packages: ${SCROW_PKG_REPO[*]}"
        if [[ "$SCROW_DRY_RUN" == "1" ]]; then
            ui_dim "  [dry-run] sudo pacman -S --needed --noconfirm ${SCROW_PKG_REPO[*]}"
        else
            scrow_need_root
            if ! scrow_log_tee "pacman install $label" \
                sudo pacman -S --needed --noconfirm "${SCROW_PKG_REPO[@]}"; then
                ui_warn "pacman failed for some packages ($label)"
                rc=1
            fi
        fi
    fi

    if [[ ${#SCROW_PKG_AUR[@]} -gt 0 ]]; then
        ui_step "Installing ${label} (AUR via paru)…"
        scrow_log "aur packages: ${SCROW_PKG_AUR[*]}"
        if [[ "$SCROW_DRY_RUN" == "1" ]]; then
            ui_dim "  [dry-run] paru -S --needed --noconfirm ${SCROW_PKG_AUR[*]}"
        else
            if ! scrow_ensure_paru; then
                ui_warn "paru unavailable — skipping AUR packages ($label)"
                scrow_log "ERROR paru unavailable for $label"
                return 1
            fi
            if ! scrow_log_tee "paru install $label" \
                paru -S --needed --noconfirm "${SCROW_PKG_AUR[@]}"; then
                ui_warn "Some AUR packages failed ($label) — see log"
                rc=1
            fi
        fi
    fi
    return $rc
}

scrow_pkg_summary() {
    # Print "pkg(version)" for a package list that exists, else "pkg(missing)".
    local pkg v
    for pkg in "$@"; do
        if scrow_pkg_installed "$pkg"; then
            v="$(pacman -Q "$pkg" 2>/dev/null | cut -d' ' -f2)"
            printf '%s' "${C_OK}${pkg} ${C_DIM}${v}${C_RESET}  "
        else
            printf '%s' "${C_ERR}${pkg} (missing)${C_RESET}  "
        fi
    done
    printf '\n'
}
