#!/usr/bin/env bash
# =============================================================================
# SCROW — validation
# =============================================================================
# Compares the repository's deployable filesystem tree against $HOME.
# Reports OK / DIFFERS / MISSING for every expected file.

# ── Validate deployment ───────────────────────────────────────────────────────
validate_deployment() {
    local ok=0 differs=0 missing=0 total=0
    local problems=()

    # Walk deployable repo files
    local repo_file dest_file
    while IFS= read -r repo_file; do
        local rel="${repo_file#$REPO_ROOT/}"
        dest_file="$HOME/$rel"
        ((total++))

        if [[ ! -e "$dest_file" && ! -L "$dest_file" ]]; then
            ((missing++))
            problems+=("MISSING  $rel")
            continue
        fi

        if [[ -f "$repo_file" ]] && ! cmp -s "$repo_file" "$dest_file" 2>/dev/null; then
            ((differs++))
            problems+=("DIFFERS  $rel")
            continue
        fi

        ((ok++))
    done < <(find_deployable_files)

    # Report
    printf "\n"
    if (( total == 0 )); then
        printf "${C_WARN}  No deployable files found to validate.${C_RST}\n"
        return 1
    fi

    if (( missing == 0 && differs == 0 )); then
        printf "${C_OK}  Validation passed: %d files OK, 0 missing, 0 different.${C_RST}\n" "$ok"
        _log "Validation passed: $ok OK, 0 missing, 0 differs"
        return 0
    fi

    printf "${C_ERR}  Validation found problems:${C_RST}\n"
    local p
    for p in "${problems[@]}"; do
        case "${p:0:8}" in
            MISSING) printf "    ${C_ERR}%s${C_RST}\n" "$p" ;;
            DIFFERS) printf "    ${C_WARN}%s${C_RST}\n" "$p" ;;
        esac
    done
    printf "\n"
    printf "  Summary: ${C_OK}%d OK${C_RST}, ${C_WARN}%d different${C_RST}, ${C_ERR}%d missing${C_RST} (of %d total)\n" \
        "$ok" "$differs" "$missing" "$total"
    _log "Validation: $ok OK, $differs differs, $missing missing (of $total)"
    return 1
}

# ── Find all deployable files in the repo ─────────────────────────────────────
find_deployable_files() {
    local e b
    for e in "$REPO_ROOT"/* "$REPO_ROOT"/.[!.]*; do
        [[ -e "$e" ]] || continue
        b="$(basename "$e")"
        local skip=0
        local never
        for never in "${TOPLEVEL_NEVER[@]}"; do
            [[ "$b" == "$never" ]] && { skip=1; break; }
        done
        (( skip == 0 )) && find "$e" -type f \
            -not -name '*.bak' -not -name '*.pyc' \
            -not -path '*__pycache__*' \
            -not -path '*.swp' -not -path '*.tmp' \
            -not -path '*.pid' \
            -not -name 'crash.log' -not -name '.DS_Store' \
            -not -name 'mimeinfo.cache' \
            -not -path '*/.config/ibus/bus/*' \
            -not -path '*/.config/hypr/backup/*' \
            -not -path '*/.config/fcitx/dbus/*' 2>/dev/null
    done
}

# ── Doctor: environment checks ────────────────────────────────────────────────
doctor_checks() {
    local pass=0 fail=0

    check() {
        local label="$1" ok="$2" fix="$3"
        if [[ "$ok" == "true" ]]; then
            printf "  ${C_OK}[PASS]${C_RST} %s\n" "$label"
            ((pass++))
        else
            printf "  ${C_ERR}[FAIL]${C_RST} %s — %s\n" "$label" "$fix"
            ((fail++))
        fi
    }

    printf "\n  ${C_BOLD}Doctor checks:${C_RST}\n\n"

    check "Arch Linux" "$([[ -f /etc/arch-release ]] && echo true || echo false)" \
        "SCROW requires Arch Linux"
    check "Internet" "$(ping -c1 -W3 archlinux.org >/dev/null 2>&1 && echo true || echo false)" \
        "Check your network connection"
    check "git" "$(command -v git >/dev/null 2>&1 && echo true || echo false)" \
        "sudo pacman -S git"
    check "rsync" "$(command -v rsync >/dev/null 2>&1 && echo true || echo false)" \
        "sudo pacman -S rsync"
    check "paru" "$(command -v paru >/dev/null 2>&1 && echo true || echo false)" \
        "paru will be auto-installed on first run"

    # Disk space (need at least 2GB free on /)
    local free_kb
    free_kb="$(df / --output=avail 2>/dev/null | tail -1 | tr -d ' ')"
    check "Disk space (>=2GB free)" "$(( ${free_kb:-0} > 2097152 ))" \
        "Free up disk space (currently $(( ${free_kb:-0} / 1024 ))MB free)"

    # Key packages
    local key_pkgs=(hyprland waybar kitty zsh)
    local pkg
    for pkg in "${key_pkgs[@]}"; do
        check "Package: $pkg" "$(pacman -Qi "$pkg" &>/dev/null && echo true || echo false)" \
            "Will be installed by SCROW"
    done

    # Services
    check "pipewire active" "$(systemctl --user is-active pipewire.service 2>/dev/null | grep -q active && echo true || echo false)" \
        "Will be enabled by SCROW"
    check "sddm enabled" "$(sudo systemctl is-enabled sddm.service 2>/dev/null | grep -q enabled && echo true || echo false)" \
        "Will be enabled by SCROW"

    # Validate deployment if manifests exist
    if [[ -f "$SCROW_MANIFEST" ]]; then
        validate_deployment
    fi

    printf "\n"
    printf "  Doctor: ${C_OK}%d passed${C_RST}, ${C_ERR}%d failed${C_RST}\n" "$pass" "$fail"
    return "$fail"
}
