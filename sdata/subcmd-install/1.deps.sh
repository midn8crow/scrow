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

# ── Run one yay install, capturing output to the log, with live status ────────

# Single-pass (many packages): a compact per-package ticker watches yay's build
# dir (~/.cache/yay). Each AUR package shows up there as a directory and gets a
# built *.pkg.tar.zst when done, so we can print "[N/14 built]  working on: ..."
# WITHOUT parsing yay's stdout — yay downloads several sources in parallel and
# that output is garbled (see Jguer/yay#1620). One-at-a-time: spinner + elapsed
# time. yay's real exit code is smuggled through the pipe as a trailing
# "AUR_RC=n" marker so set -e and callers always see the true status.
aur_install_run() {
    local log_file="$1"; shift
    local msg="$1"; shift
    local n="$#"
    local tty_display=0
    [[ -t 1 ]] && tty_display=1

    local build_dir
    build_dir="$("$SCROW_AUR_HELPER" -Pg 2>/dev/null | sed -n 's/.*"buildDir"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
    [[ -n "$build_dir" ]] || build_dir="${XDG_CACHE_HOME:-$HOME/.cache}/yay"

    ( timeout 1800 "$SCROW_AUR_HELPER" -S --needed "${yay_flags[@]}" "$@" 2>&1
      echo "AUR_RC=$?" ) | aur_consume "$log_file" "$n" "$build_dir" "$msg" "$tty_display" &

    local ypid=$!
    local rc=0
    wait "$ypid" && rc=0 || rc=$?
    return "$rc"
}

# Reads yay's stream from the pipe, appends it to the log, and draws live
# status while it runs. Returns the marker rc (yay's own exit code).
aur_consume() {
    local log_file="$1" n="$2" build_dir="$3" msg="$4" tty_display="$5"
    local rc=0 line tick=0 start=$SECONDS
    local d
    declare -Ag seen=()
    for d in "$build_dir"/*/; do
        [[ -e "$d" ]] || continue
        seen["$(basename "$d")"]=1
    done

    while :; do
        if IFS= read -r -t 0.25 line; then
            if [[ "${line:0:7}" == "AUR_RC=" ]]; then
                rc="${line:7}"
                break
            fi
            printf '%s\n' "$line" >>"$log_file"
        fi
        (( tty_display )) || continue
        (( ++tick % 2 == 0 )) || continue
        draw_aur_status "$build_dir" "$msg" "$n" "$start"
    done

    if (( tty_display && n > 1 )); then
        local el=$(( SECONDS - start ))
        printf "\r\033[K  ${GREEN}  All %d AUR packages processed in %d:%02d${RST}\n" "$n" $((el/60)) $((el%60))
    elif (( tty_display )); then
        printf "\r\033[K"
    fi
    return "${rc:-1}"
}

draw_aur_status() {
    local build_dir="$1" msg="$2" n="$3" start="$4"
    local working=() built=0 tot=0 name
    local el=$(( SECONDS - start ))
    for d in "$build_dir"/*/; do
        [[ -e "$d" ]] || continue
        name="$(basename "$d")"
        [[ "${seen[$name]+1}" ]] && continue
        tot=$(( tot + 1 ))
        if ls "$d"/*.pkg.tar.zst >/dev/null 2>&1; then
            built=$(( built + 1 ))
        elif (( ${#working[@]} < 4 )); then
            working+=("$name")
        fi
    done
    local now_str pct=0
    printf -v now_str "%d:%02d" $((el/60)) $((el%60))
    (( n > 0 )) && pct=$(( built * 100 / n ))
    local suffix
    if (( tot > 0 && built == tot )); then
        suffix="${YELLOW}installing (pacman transaction)…${RST}"
    elif (( tot == 0 )); then
        suffix="${YELLOW}resolving…${RST}"
    else
        suffix="${YELLOW}working on: $(IFS=' '; printf '%s' "${working[*]}")${RST}"
    fi
    printf "\r\033[K  [%d/%d built]  (%d%%)  %s  %s  %s" \
        "$built" "$n" "$pct" "$suffix" "$now_str" "$msg"
}

# ── Waybar: local cava-enabled build, NO stock fallback ────────────────────────
# The AUR waybar-cava-git builds moving-git master via a full clone that keeps
# aborting on this installer's slow/throttled link. Instead we build waybar WITH
# the compiled cava module from a pinned Waybar *git snapshot* commit
# (packages/waybar-cava/PKGBUILD + AUR `libcava`, which ships the libcava.pc
# that waybar's meson looks for). The snapshot is the same code line upstream
# waybar-cava-git builds (master), pinned deterministically. If that local build
# fails the install STOPS - the cava module is required, never degraded.
install_waybar_cava() {
    pacman -Q waybar-cava >/dev/null 2>&1 && return 0

    local pkgdir="$REPO_ROOT/packages/waybar-cava"
    local log_dir="${XDG_CACHE_HOME:-$HOME/.cache}/scrow"
    local build_log="$log_dir/waybar-cava-build.log"
    mkdir -p "$log_dir"

    if [[ ! -f "$pkgdir/PKGBUILD" ]]; then
        printf "${YELLOW}  No local waybar PKGBUILD at %s — cannot build cava-enabled waybar${RST}\n" "$pkgdir"
        return 1
    fi
    if ! pacman -Q libcava >/dev/null 2>&1; then
        printf "${YELLOW}  libcava missing (AUR phase failed?) — cannot build cava-enabled waybar${RST}\n"
        return 1
    fi

    # Resolve the sudo credential ONCE, explicitly and visibly, BEFORE the
    # build: makepkg -s auto-installs any missing deps and sudo pacman -U
    # installs the finished package, so making credentials valid up-front keeps
    # a password prompt from ever appearing mid-display. Any late sudo ask
    # (slow build, >15min) fails fast via /dev/null and prints an explicit line.
    if sudo -n -v 2>/dev/null; then
        printf "${GREEN}  [sudo] already authenticated (valid credential from the package phases) - build will not prompt${RST}\n"
    else
        printf "${BLUE}  [sudo] the waybar build needs your password once:${RST}\n"
        if ! sudo -v; then
            printf "${YELLOW}  sudo did not accept credentials - cannot build waybar locally (cava module required)${RST}\n"
            return 1
        fi
        printf "${GREEN}  [sudo] credentials OK - the build proceeds without further prompts${RST}\n"
    fi

    printf "${BLUE}  Building waybar with the compiled cava module (pinned git snapshot, no stock fallback — log: %s)...${RST}\n" "$build_log"
    # Build in a disk-backed dir under XDG_CACHE_HOME, NEVER /tmp: on many
    # machines /tmp is a small tmpfs or mounted noexec and the full waybar+cava
    # compile would die there. A fixed reusable name keeps reruns clean.
    local build_dir t0=$SECONDS
    build_dir="${XDG_CACHE_HOME:-$HOME/.cache}/scrow/waybar-build"
    rm -rf "$build_dir"
    mkdir -p "$build_dir"
    cp "$pkgdir/PKGBUILD" "$build_dir/" 2>/dev/null || true

    # The build must work on ANY machine, whatever its starting state. makepkg's
    # -s (--syncdeps) auto-resolves and installs any missing depends/makedepends
    # on first run, so machines missing parts of a full set are fixed by makepkg
    # itself instead of by a hand-maintained list. The sudo credential is
    # pre-cached by sudo -v above (no prompt appears behind the display) and
    # makepkg gets stdin from /dev/null so any LATE sudo ask fails fast and
    # loudly rather than hanging. We do NOT use -i: the built package is
    # installed with ONE explicit, clean sudo below, after the display stops.
    (cd "$build_dir" && timeout 5400 makepkg --noconfirm -f -s </dev/null >"$build_log" 2>&1) &
    local mpid=$!

    # REAL progress, not a fake animation: read ninja's own build counter
    # "[done/total]" straight from the log as it grows and show the % from it.
    # Before the numbers appear we show the actual makepkg stage name. Updates
    # are throttled to 0.3s but every move reflects work actually completed.
    if [[ -t 1 ]]; then
        local pos=0 pct= count= phase="starting" sz chunk num den
        while kill -0 "$mpid" 2>/dev/null; do
            if [[ -f "$build_log" ]]; then
                sz="$(stat -c %s "$build_log" 2>/dev/null || echo 0)"
                if (( sz > pos )); then
                    chunk="$(dd if="$build_log" bs=1 skip="$pos" count=$((sz - pos)) 2>/dev/null | tr '\r' '\n')"
                    pos=$sz
                    case "$chunk" in
                        *'==> Downloading sources'*)      phase="downloading" ;;&
                        *'==> Validating source files'*)  phase="validating" ;;&
                        *'==> Extracting sources'*)       phase="extracting" ;;&
                        *'==> Starting build()'*)         phase="compiling" ;;&
                        *'==> Entering fakeroot'*)        phase="packaging" ;;&
                        *'==> Starting package()'*)       phase="packaging" ;;&
                        *'==> Making package:'*)          phase="packaging" ;;
                    esac
                    count="$(printf '%s' "$chunk" | grep -aoE '\[[0-9]+/[0-9]+\]' | tail -1)"
                    if [[ -n "$count" ]]; then
                        num="${count#\[}"; num="${num%%/*}"
                        den="${count%\]}"; den="${den##*/}"
                        (( den > 0 )) && pct=$(( num * 100 / den ))
                    fi
                fi
            fi
            local el=$(( SECONDS - t0 ))
            if [[ -n "$pct" ]]; then
                printf "\r\033[K  [%d%%]  %s  %s · %d:%02d  " \
                    "$pct" "$count" "$phase" $((el/60)) $((el%60))
            else
                printf "\r\033[K  [--%%]  %s · %d:%02d  " \
                    "$phase" $((el/60)) $((el%60))
            fi
            sleep 0.3
        done
        printf "\r\033[K"
    fi
    local rc=0
    wait "$mpid" && rc=0 || rc=$?

    if (( rc != 0 )); then
        printf "${RED}  Local waybar-cava build failed (makepkg rc=%d)${RST}\n" "$rc"
        printf "${YELLOW}  ===== last lines of %s =====${RST}\n" "$build_log"
        tail -n 30 "$build_log" 2>/dev/null | sed 's/^/    /'
        printf "${YELLOW}  ===== end of log =====${RST}\n"
        rm -rf "$build_dir" 2>/dev/null || true
        return 1
    fi

    # Install the freshly built package: ONE clean, explicit sudo moment, after
    # the progress display is gone, so the prompt is plain and typeable.
    local pkgfile
    pkgfile=""
    for f in "$build_dir"/*.pkg.tar.zst; do
        [[ -e "$f" ]] || continue
        [[ "$f" == *-debug-* ]] && continue
        pkgfile="$f"
        break
    done
    if [[ -z "$pkgfile" ]]; then
        printf "${RED}  waybar built but no package file found in %s${RST}\n" "$build_dir"
        printf "${YELLOW}  artifacts present: %s${RST}\n" "$(ls "$build_dir" 2>/dev/null | sed 's/^/    /')"
        rm -rf "$build_dir" 2>/dev/null || true
        return 1
    fi
    printf "${BLUE}  Installing freshly built waybar-cava package...${RST}\n"
    sudo -n -v 2>/dev/null || sudo -v
    sudo pacman -R --noconfirm waybar 2>/dev/null || sudo pacman -Rd --noconfirm waybar 2>/dev/null || true
    if ! sudo pacman -U --noconfirm "$pkgfile"; then
        printf "${RED}  sudo pacman -U failed (see log: %s)${RST}\n" "$build_log"
        rm -rf "$build_dir" 2>/dev/null || true
        return 2
    fi
    rm -rf "$build_dir" 2>/dev/null || true
command -v waybar >/dev/null 2>&1
}

# ── Install AUR packages one by one ───────────────────────────────────────────

install_aur_packages() {
    local manifest="$REPO_ROOT/packages/aur.txt"
    [[ ! -f "$manifest" ]] && { printf "${YELLOW}  No aur.txt found, skipping${RST}\n"; return 0; }

    ensure_yay || { printf "${RED}  Cannot install AUR packages without an AUR helper${RST}\n"; return 1; }

    # Slow/fragile network hardening for -git clones (fixes -git packages like
    # hypr-kdeconnect-fix-git dropping mid-download on QEMU user-net / throttled
    # links): git aborts "slow but alive" transfers by default and HTTP/2
    # multiplexing stalls on SLIRP. Use HTTP/1.1, no low-speed abort, and a
    # bigger request buffer so long clones have time to complete.
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
install_waybar_cava || {
        printf "${RED}  No stock fallback: waybar with the cava module built in is REQUIRED and could not be built.\n"
        printf "  Full build log: %s — fix the cause and rerun; nothing was degraded.${RST}\n" "${XDG_CACHE_HOME:-$HOME/.cache}/scrow/waybar-cava-build.log"
        return 1
    }
install_hyprpm_plugins

printf "${GREEN}[$0]: Dependencies installed${RST}\n"
