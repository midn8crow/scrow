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

    printf "${BLUE}  Installing %d AUR packages (one at a time to avoid OOM)...${RST}\n" "$total"

    # yay CLONE/BUILD prompts (--answer*) are NOT covered by --noconfirm and they
    # hang/abort on a non-tty install (bash <(curl ...)). Force every answer so
    # the install is deterministic.
    local yay_flags=(--noconfirm --answerdiff None --answerclean None --answeredit None --answerupgrade None)

    local i=0
    while (( i < total )); do
        local pkg="${pkgs[$i]}"
        local num=$(( i + 1 ))
        printf "${BLUE}  [%d/%d] %s${RST}\n" "$num" "$total" "$pkg"

        local attempt=1 ok=0
        while (( attempt <= 2 )); do
            printf -- "--- %s (attempt %d) ---\n" "$pkg" "$attempt" >> "$log_file"

            # Hard per-package ceiling (1800s) + a live heartbeat. Heavy builds
            # (e.g. waybar-cava-git's meson+ninja) run for many minutes and can
            # look "stuck"; the heartbeat proves it's alive, and a genuinely
            # hung package is auto-killed at the ceiling instead of stalling.
            local start_ts last_hb ypid rc pstat
            start_ts=$(date +%s); last_hb=$start_ts
            timeout 1800 "$SCROW_AUR_HELPER" -S --needed "${yay_flags[@]}" "$pkg" \
                >>"$log_file" 2>&1 &
            ypid=$!
            while :; do
                if ! kill -0 "$ypid" 2>/dev/null; then break; fi
                pstat=$(ps -o stat= -p "$ypid" 2>/dev/null | tr -d ' ')
                [[ "$pstat" == Z* ]] && break   # exited, awaiting reap
                sleep 30
                local now
                now=$(date +%s)
                if (( now - last_hb >= 60 )); then
                    last_hb=$now
                    printf "${YELLOW}    ... %s still running (%ds) — latest:${RST}\n" \
                        "$pkg" "$(( now - start_ts ))"
                    tail -1 "$log_file" | sed 's/^/      /'
                fi
            done
            wait "$ypid"; rc=$?
            if (( rc == 124 )); then
                printf "${RED}    ... %s hit the 1800s ceiling — marking failed${RST}\n" "$pkg"
            fi
            if (( rc == 0 )); then
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
install_hyprpm_plugins

printf "${GREEN}[$0]: Dependencies installed${RST}\n"
