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

# ── Run one AUR install quietly (into the log) with an animated spinner ───────

# yay's build output goes to BOTH the log and the screen would flood the
# terminal, so it is kept in the log while a braille spinner + elapsed time
# shows the install is alive. Honors the 1800s ceiling and returns yay's exit
# status without ever tripping set -e (the wait-and-rc guard pattern is
    # identical to the old `wait ... && rc=0 || rc=$?`).
aur_install_run() {
    local log_file="$1"; shift
    local msg="$1"; shift

    timeout 1800 "$SCROW_AUR_HELPER" -S --needed "${yay_flags[@]}" "$@" \
        >>"$log_file" 2>&1 &
    local ypid=$!

    if [[ -t 1 ]]; then
        local sp='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏' i=0
        while kill -0 "$ypid" 2>/dev/null; do
            printf "\r\033[K  %s  %s" "${sp:i++ % ${#sp}}" "$msg"
            sleep 0.2
        done
        printf "\r\033[K"
    fi

    local rc=0
    wait "$ypid" && rc=0 || rc=$?
    return "$rc"
}

# Ensure a working waybar even when the AUR build fails. waybar-cava-git cannot
# be installed on Arch (its PKGBUILD makedepends on `glib2-devel`, which does
# not exist in Arch repos or AUR — deterministic failure), but the scrowland
# cava visualizer is script-based (custom/cava -> waybar-cava.py + cava +
# python-pillow), so stock waybar renders identically. Prefer the AUR build,
# fall back to a version of waybar from the official repos when it failed.
ensure_waybar_fallback() {
    command -v waybar >/dev/null 2>&1 && return 0
    grep -qx 'waybar-cava-git' "$REPO_ROOT/packages/aur.txt" 2>/dev/null || return 0
    printf "${YELLOW}  waybar-cava-git build not installable on Arch (broken PKGBUILD," \
        " missing glib2-devel dep) — installing stock waybar (same cava visualizer).${RST}\n"
    sudo pacman -S --needed --noconfirm waybar
}

# ── Install AUR packages one by one ───────────────────────────────────────────

install_aur_packages() {
    local manifest="$REPO_ROOT/packages/aur.txt"
    [[ ! -f "$manifest" ]] && { printf "${YELLOW}  No aur.txt found, skipping${RST}\n"; return 0; }

    ensure_yay || { printf "${RED}  Cannot install AUR packages without an AUR helper${RST}\n"; return 1; }

    # Slow/fragile network hardening for -git clones (fixes waybar-cava-git &
    # other -git packages dropping mid-download on QEMU user-net / throttled
    # links): git aborts "slow but alive" transfers by default and HTTP/2
    # multiplexing stalls on SLIRP. Use HTTP/1.1, no low-speed abort, bigger
    # request buffer so the full Waybar history clone has time to complete.
    git config --global http.version HTTP/1.1 2>/dev/null || true
    git config --global http.lowSpeedLimit 0 2>/dev/null || true
    git config --global http.lowSpeedTime 999 2>/dev/null || true
    git config --global http.postBuffer 524288000 2>/dev/null || true

    local -a pkgs=()
    read_manifest "$manifest" pkgs
    (( ${#pkgs[@]} == 0 )) && return 0

    local total=${#pkgs[@]}
    local -a failed_pkgs=()
    local log_dir="${XDG_CACHE_HOME:-$HOME/.cache}/scrow"
    local log_file="$log_dir/aur-install.log"
    mkdir -p "$log_dir"
    : > "$log_file"

    # yay CLONE/BUILD prompts (--answer*) are NOT covered by --noconfirm and they
    # hang/abort on a non-tty install (bash <(curl ...)). Force every answer so
    # the install is deterministic.
    local yay_flags=(--noconfirm --answerdiff None --answerclean None --answeredit None --answerupgrade None)

    # OOM-safe mode is OPTIONAL. One prompt with a 30s answer window:
    #   y -> one package at a time (safest on a 4GB VM)
    #   n / nothing typed within 30s / non-tty install -> single fast pass
    local oom_safe=0 ans
    if [[ -t 0 ]]; then
        printf "${YELLOW}  AUR packages — install one at a time to avoid OOM? [y/N] (30s to answer, else n) ${RST}"
        if IFS= read -r -t 30 ans; then
            case "${ans,,}" in
                y|yes) oom_safe=1 ;;
            esac
        else
            printf "\n"
        fi
    fi

    if (( oom_safe )); then
        printf "${BLUE}  Installing %d AUR packages one at a time (OOM-safe)...${RST}\n" "$total"
    else
        printf "${BLUE}  Installing %d AUR packages in one pass...${RST}\n" "$total"
    fi

    # Single-pass mode: one yay invocation for everything (quiet), under the
    # 1800s ceiling so one hung package can't stall. Output is captured to the
    # log; an animated spinner keeps the terminal alive. If yay reports any
    # failure we fall through and re-run the individual loop to isolate them.
    if (( oom_safe == 0 )); then
        if aur_install_run "$log_file" "Installing all $total AUR packages..." "${pkgs[@]}"; then
            printf "${GREEN}  [OK]${RST} All AUR packages installed\n"
            printf '%s\n' "${failed_pkgs[@]}" > "${log_file%.log}-failed.txt"
            return 0
        fi
        printf "${YELLOW}  One-pass install had failures — retrying individually to isolate them...${RST}\n"
    fi

    local i=0
    while (( i < total )); do
        local pkg="${pkgs[$i]}"
        local num=$(( i + 1 ))
        printf "${BLUE}  [%d/%d] %s${RST}\n" "$num" "$total" "$pkg"

        local attempt=1 ok=0
        while (( attempt <= 2 )); do
            printf -- "--- %s (attempt %d) ---\n" "$pkg" "$attempt" >> "$log_file"
            # 1800s per-package ceiling so one hung package can't stall setup
            # forever (spinner shows it's alive); failures print "Failed: ... -
            # skipping" and we continue.
            if aur_install_run "$log_file" "Installing $pkg (attempt $attempt of 2)..." "$pkg"; then
                ok=1
                break
            fi
            attempt=$(( attempt + 1 ))
        done

        if (( ok == 1 )); then
            printf "${GREEN}  [OK]${RST} $pkg\n"
        else
            printf "${YELLOW}  Failed: %s — skipping${RST}\n" "$pkg"
            failed_pkgs+=("$pkg")
        fi
        i=$(( i + 1 ))
        sleep 2
    done

    if (( ${#failed_pkgs[@]} > 0 )); then
        printf "${YELLOW}  %d AUR packages failed (non-fatal):${RST}\n" "${#failed_pkgs[@]}"
        for fp in "${failed_pkgs[@]}"; do
            printf "${YELLOW}    - ${fp}${RST}\n"
            printf "${FAINT}       details in: ${log_file}${RST}\n"
        done
        printf "${FAINT}  Full log: ${log_file}${RST}\n"
    else
        printf "${GREEN}  All %d AUR packages installed${RST}\n" "$total"
    fi

    # write the failure list so tools/VM can report them precisely
    printf '%s\n' "${failed_pkgs[@]}" > "${log_file%.log}-failed.txt"
}

# ── Install hyprpm plugins ────────────────────────────────────────────────────

# True when `hyprpm list` shows the scrolloverview plugin enabled (state, not
# whether a running compositor has it loaded). ANSI is stripped for parsing.
hyprpm_plugin_enabled() {
    hyprpm list 2>/dev/null | sed -r 's/\x1b\[[0-9;]*m//g' \
        | grep -A1 -iE 'plugin[[:space:]]+scrolloverview' \
        | grep -qi 'enabled.*true'
}

install_hyprpm_plugins() {
    if ! command -v hyprpm >/dev/null 2>&1; then
        printf "${RED}  hyprpm not found — hyprland did not install hyprpm. Cannot install plugins.${RST}\n"
        return 1
    fi

    local plugin_so="/var/cache/hyprpm/${USER:-$(id -un)}/hyprland-scroll-overview/scrolloverview.so"
    local hp_log; hp_log="$(mktemp)"

    # hyprpm add/load fails with "Headers outdated" unless hyprpm is synced to
    # the ABI of the installed Hyprland. Plain `update` can skip ABI-only header
    # bumps, so -f is used first. Output is captured (never swallowed) so a real
    # failure is visible; we only continue when headers are actually in sync.
    printf "${YELLOW}  Syncing hyprpm headers/builds (may take a while)...${RST}\n"
    if ! hyprpm update -f >"$hp_log" 2>&1 && ! hyprpm update >"$hp_log" 2>&1; then
        printf "${RED}  hyprpm header sync FAILED — plugins cannot build:${RST}\n"
        sed 's/^/    /' "$hp_log"
        rm -f "$hp_log"
        return 1
    fi

    if ! hyprpm list 2>/dev/null | grep -qi scrolloverview; then
        printf "${YELLOW}  Installing ScrollOverview plugin...${RST}\n"
        # hyprpm has no --yes flag; its "Are you sure? [Y/n]" reads one line from
        # stdin. Feed the confirmation so a non-tty install can't stall/abort.
        if ! printf 'y\n' | hyprpm add https://github.com/yayuuu/hyprland-scroll-overview.git >"$hp_log" 2>&1; then
            if grep -qi "already installed" "$hp_log"; then
                printf "${YELLOW}  ScrollOverview repository already installed${RST}\n"
            else
                printf "${RED}  ScrollOverview plugin add FAILED:${RST}\n"
                sed 's/^/    /' "$hp_log"
                rm -f "$hp_log"
                return 1
            fi
        fi
    fi

    # hyprpm add reports success even when the plugin BUILD failed (it records
    # failed=true and still registers the repo). Verify the compiled shared
    # object actually exists before claiming anything.
    if ! sudo test -f "$plugin_so" 2>/dev/null; then
        printf "${RED}  ScrollOverview build FAILED — no plugin binary at:%s${RST}\n" " $plugin_so"
        sed 's/^/    /' "$hp_log" 2>/dev/null || true
        rm -f "$hp_log"
        return 1
    fi
    printf "${GREEN}  [OK]${RST} ScrollOverview compiled: %s\n" "$plugin_so"

    # Persist the enabled state. On a fresh install Hyprland is not running, so
    # `hyprpm enable` cannot load it into a session and exits nonzero — that is
    # EXPECTED; the important part is the persisted state, verified below.
    hyprpm enable scrolloverview >"$hp_log" 2>&1 || true
    rm -f "$hp_log"

    if hyprpm_plugin_enabled; then
        printf "${GREEN}  [OK]${RST} ScrollOverview enabled in hyprpm\n"
    else
        printf "${YELLOW}  ScrollOverview not enabled — retrying hyprpm enable...${RST}\n"
        hyprpm enable scrolloverview >/dev/null 2>&1 || true
        if ! hyprpm_plugin_enabled; then
            printf "${RED}  ScrollOverview could NOT be enabled — run: hyprpm list${RST}\n"
            return 1
        fi
        printf "${GREEN}  [OK]${RST} ScrollOverview enabled in hyprpm\n"
    fi

    # Load into a live instance if one is running (definitive proof). Without a
    # session (typical during install) the plugin will load at the next Hyprland
    # start, because autostart runs `hyprpm reload` on hyprland.start.
    if command -v hyprctl >/dev/null 2>&1 && hyprctl -j instanceinfo >/dev/null 2>&1; then
        hyprpm reload >/dev/null 2>&1 || true
        if hyprctl plugin list 2>/dev/null | grep -qi scrolloverview; then
            printf "${GREEN}  [OK]${RST} ScrollOverview LOADED into running Hyprland\n"
        else
            printf "${RED}  ScrollOverview installed but NOT loaded in the running instance. Output of hyprpm reload:${RST}\n"
            hyprpm reload 2>&1 | sed 's/^/    /'
            return 1
        fi
    else
        printf "${GREEN}  [OK]${RST} ScrollOverview installed + enabled (no live Hyprland session yet; loads via autostart 'hyprpm reload')${RST}\n"
    fi
}

# ── Run all dependency steps ──────────────────────────────────────────────────

ensure_yay
install_official_packages
install_aur_packages
ensure_waybar_fallback
install_hyprpm_plugins

printf "${GREEN}[$0]: Dependencies installed${RST}\n"
