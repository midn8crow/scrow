#!/usr/bin/env bash
# =============================================================================
# SCROW — deployment
# =============================================================================
# Recursively deploys the repository filesystem tree to $HOME and system paths.
# No hardcoded per-file lists — the repository structure IS the manifest.

# ── Exclusion lists ───────────────────────────────────────────────────────────

# Top-level names that are NEVER deployed to $HOME
TOPLEVEL_NEVER=(
    .git .github .gitignore .git_list
    bootstrap.sh setup
    installer packages tests
    README.md CHANGELOG.md LICENSE VERSION
)

# rsync excludes applied to every deploy (junk, runtime artifacts)
RSYNC_EXCLUDES=(
    '*.bak'
    '__pycache__/'
    '*.pyc'
    'crash.log'
    '.DS_Store'
    '*.swp'
    '*.tmp'
    '*.pid'
    '.config/ibus/bus/'
    '.config/hypr/backup/'
    '.config/fcitx/dbus/'
    '.config/mimeinfo.cache'
)

# ── Discover deployable top-level entries ──────────────────────────────────────
discover_sources() {
    local e b skip never
    for e in "$REPO_ROOT"/* "$REPO_ROOT"/.[!.]*; do
        [[ -e "$e" ]] || continue
        b="$(basename "$e")"
        skip=0
        for never in "${TOPLEVEL_NEVER[@]}"; do
            if [[ "$b" == "$never" ]]; then
                skip=1
                break
            fi
        done
        (( skip == 0 )) && printf '%s\n' "$b"
    done | sort
}

# ── Deploy home directory files ───────────────────────────────────────────────
deploy_home() {
    local src changed=0 deployed=0 skipped=0
    mkdir -p "$XDG_DATA_HOME/scrow"

    while IFS= read -r src; do
        if [[ ! -e "$REPO_ROOT/$src" ]]; then
            printf "${C_DIM}  [SKIP]${C_RST} %s (not in repo)\n" "$src"
            ((skipped++))
            continue
        fi

        backup_file "$HOME/$src"

        # Build rsync exclude args
        local exclude_args=()
        local exc
        for exc in "${RSYNC_EXCLUDES[@]}"; do
            exclude_args+=(--exclude="$exc")
        done

        if [[ -d "$REPO_ROOT/$src" ]]; then
            mkdir -p "$HOME/$src"
            if command -v rsync >/dev/null 2>&1; then
                rsync -a "${exclude_args[@]}" "$REPO_ROOT/$src/" "$HOME/$src/" 2>/dev/null || true
            else
                # cp fallback with manual excludes matching RSYNC_EXCLUDES
                local f rel
                while IFS= read -r f; do
                    rel="${f#$REPO_ROOT/$src/}"
                    mkdir -p "$(dirname "$HOME/$src/$rel")"
                    cp -a "$f" "$HOME/$src/$rel" 2>/dev/null || true
                done < <(find "$REPO_ROOT/$src" -type f \
                    -not -name '*.bak' -not -name '*.pyc' \
                    -not -path '*__pycache__*' \
                    -not -path '*.swp' -not -path '*.tmp' \
                    -not -path '*.pid' \
                    -not -name 'crash.log' -not -name '.DS_Store' \
                    -not -name 'mimeinfo.cache' \
                    -not -path '*/.config/ibus/bus/*' \
                    -not -path '*/.config/hypr/backup/*' \
                    -not -path '*/.config/fcitx/dbus/*' 2>/dev/null)
            fi
        elif [[ -f "$REPO_ROOT/$src" ]]; then
            # Check if file matches any rsync exclude pattern (name-level)
            local _skip_file=0 _exc_pat
            for _exc_pat in "${RSYNC_EXCLUDES[@]}"; do
                # Only test simple name patterns (not path-based)
                [[ "$_exc_pat" == */* ]] && continue
                case "$src" in
                    $_exc_pat) _skip_file=1; break ;;
                esac
            done
            if [[ "$_skip_file" -eq 0 ]]; then
                mkdir -p "$(dirname "$HOME/$src")"
                cp -a "$REPO_ROOT/$src" "$HOME/$src" 2>/dev/null || true
            else
                printf "${C_DIM}  [SKIP]${C_RST} %s (excluded)\n" "$src"
                ((skipped++))
                continue
            fi
        fi

        printf "${C_OK}  [ OK ]${C_RST} %s\n" "$src"
        record_deployed "$src"
        ((deployed++))
    done < <(discover_sources)

    printf "\n"
    printf "  Deployed %d items (${C_WARN}%d skipped${C_OK}).${C_RST}\n" "$deployed" "$skipped"
}

# ── Deploy system-level files ─────────────────────────────────────────────────
deploy_system() {
    make_sudo_keepalive

    # SDDM theme
    if [[ -d "$REPO_ROOT/etc/sddm" ]]; then
        backup_file /etc/sddm
        x "deploy SDDM theme" sudo rsync -a "$REPO_ROOT/etc/sddm/" /etc/sddm/
    fi

    # Pacman hooks
    if [[ -d "$REPO_ROOT/etc/pacman.d/hooks" ]]; then
        x "deploy pacman hooks" sudo rsync -a "$REPO_ROOT/etc/pacman.d/hooks/" /etc/pacman.d/hooks/
    fi

    # GRUB theme
    if [[ -d "$REPO_ROOT/boot/grub/themes/minegrub" ]]; then
        x "deploy GRUB theme" sudo rsync -a "$REPO_ROOT/boot/grub/themes/minegrub/" /boot/grub/themes/minegrub/
        if [[ -f /etc/default/grub ]]; then
            if grep -q '^GRUB_THEME=' /etc/default/grub 2>/dev/null; then
                x "set GRUB theme" sudo sed -i 's|^GRUB_THEME=.*|GRUB_THEME=/boot/grub/themes/minegrub/theme.txt|' /etc/default/grub
            else
                echo 'GRUB_THEME=/boot/grub/themes/minegrub/theme.txt' | sudo tee -a /etc/default/grub >/dev/null
            fi
        fi
        if command -v grub-mkconfig >/dev/null 2>&1; then
            x "regenerate GRUB config" sudo grub-mkconfig -o /boot/grub/grub.cfg
        fi
    fi

    stop_sudo_keepalive
}

# ── Deploy security hardening (opt-in) ────────────────────────────────────────
deploy_security() {
    [[ ! -d "$REPO_ROOT/security-hardening" ]] && return 0

    printf "\n"
    printf "  ${C_BOLD}Security hardening (optional):${C_RST}\n"
    printf "${C_WARN}  Deploy security configs to /etc? [y/N]${C_RST} "
    read -r -p "  => " sec_choice
    case "${sec_choice,,}" in
        y|yes)
            make_sudo_keepalive
            local sec="$REPO_ROOT/security-hardening"
            [[ -f "$sec/sshd_hardened.conf" ]] && x "deploy sshd" sudo install -Dm644 "$sec/sshd_hardened.conf" /etc/ssh/sshd_config.d/99-hardened.conf
            [[ -f "$sec/nftables_hardened.conf" ]] && x "deploy nftables" sudo install -Dm644 "$sec/nftables_hardened.conf" /etc/nftables.conf
            [[ -f "$sec/sysctl_security.conf" ]] && x "deploy sysctl" sudo install -Dm644 "$sec/sysctl_security.conf" /etc/sysctl.d/99-security.conf
            [[ -f "$sec/fail2ban_jail.local" ]] && x "deploy fail2ban" sudo install -Dm644 "$sec/fail2ban_jail.local" /etc/fail2ban/jail.local
            [[ -f "$sec/usb-scan.sh" ]] && x "deploy usb-scan" sudo install -Dm755 "$sec/usb-scan.sh" /usr/local/bin/usb-scan.sh
            [[ -f "$sec/usb-scan.rules" ]] && x "deploy udev rules" sudo install -Dm644 "$sec/usb-scan.rules" /etc/udev/rules.d/99-usb-scan.rules
            x "apply sysctl" sudo sysctl --system >/dev/null 2>&1 || true
            sudo systemctl enable nftables.service 2>/dev/null || true
            sudo systemctl enable fail2ban.service 2>/dev/null || true
            stop_sudo_keepalive
            ;;
        *)
            printf "${C_DIM}  Skipping security hardening.${C_RST}\n"
            ;;
    esac
}

# ── Set executable permissions ────────────────────────────────────────────────
set_permissions() {
    printf "\n  ${C_BOLD}Setting permissions:${C_RST}\n"
    [[ -d "$HOME/.local/bin" ]] && find "$HOME/.local/bin" -maxdepth 1 -type f -exec chmod +x {} + 2>/dev/null || true
    [[ -d "$HOME/user_scripts" ]] && find "$HOME/user_scripts" -type f -name '*.sh' -exec chmod +x {} + 2>/dev/null || true
    [[ -d "$HOME/.config/waybar" ]] && find "$HOME/.config/waybar" -type f -name '*.sh' -exec chmod +x {} + 2>/dev/null || true
    printf "${C_OK}  [ OK ]${C_RST} scripts made executable\n"
}

# ── Record deployed path to manifest ──────────────────────────────────────────
record_deployed() {
    local src="$1"
    printf '%s\n' "$src" >> "$SCROW_MANIFEST" 2>/dev/null
}

# ── Write full deployment manifest ────────────────────────────────────────────
write_deploy_manifest() {
    mkdir -p "$(dirname "$SCROW_MANIFEST")"
    : > "$SCROW_MANIFEST"
    local src
    while IFS= read -r src; do
        [[ -e "$REPO_ROOT/$src" ]] && record_deployed "$src"
    done < <(discover_sources)
    _log "Deployment manifest written: $SCROW_MANIFEST"
}
