#!/usr/bin/env bash
# =============================================================================
# SCROW - hardware / system detection
# =============================================================================

SCROW_GPU="none"
SCROW_LAPTOP=0

SCROW_NET_TIMEOUT=8
SCROW_NET_DIAG=""

# scrow_check_network <url> <label>
# Verifies HTTPS reachability of a resource SCROW actually needs. Returns 0
# when reachable, 1 otherwise with SCROW_NET_DIAG set to a concise reason
# (DNS / connect / timeout / TLS / missing curl). Uses curl over HTTPS, never
# ping: ICMP may be blocked even when HTTPS works (e.g. VM NAT firewalls).
scrow_check_network() {
    local url="$1" label="$2"
    local err rc code
    SCROW_NET_DIAG=""

    if ! command -v curl >/dev/null 2>&1; then
        SCROW_NET_DIAG="curl is unavailable (install curl first)"
        scrow_log "network fail: $label — $SCROW_NET_DIAG"
        return 1
    fi

    err="$(curl -sS --connect-timeout 4 --max-time "$SCROW_NET_TIMEOUT" \
        -o /dev/null -w '%{http_code}' "$url" 2>&1)"
    rc=$?
    code="${err##*$'\n'}"

    if (( rc == 0 )) && [[ "$code" =~ ^[0-9]{3}$ ]]; then
        scrow_log "network ok: $label (HTTP $code)"
        return 0
    fi

    case "$rc" in
        6)  SCROW_NET_DIAG="DNS resolution for $label failed" ;;
        7)  SCROW_NET_DIAG="connection to $label refused (network or firewall)" ;;
        28) SCROW_NET_DIAG="connection to $label timed out (firewall, proxy or no route)" ;;
        35) SCROW_NET_DIAG="TLS handshake with $label failed" ;;
        56) SCROW_NET_DIAG="connection to $label was dropped mid-request" ;;
        60) SCROW_NET_DIAG="TLS certificate verification failed for $label" ;;
        *)  SCROW_NET_DIAG="curl error $rc reaching $label" ;;
    esac
    scrow_log "network fail: $label — $SCROW_NET_DIAG"
    return 1
}

# scrow_check_network_now [--quiet]
# Checks the HTTPS resources the SCROW installer actually needs:
#   - github.com's git smart-HTTP endpoint (the exact URL `git clone` hits
#     for the repository mirror / bootstrap clone)
#   - raw.githubusercontent.com (bootstrap / raw files)
# Returns 0 when both are reachable. With --quiet no status line is printed
# (used by Doctor); failure reasons are always written to the log.
scrow_check_network_now() {
    local quiet=0 gh_ok=0 raw_ok=0 gh_diag="" raw_diag=""
    [[ "${1:-}" == "--quiet" ]] && quiet=1

    while :; do
        gh_ok=0 raw_ok=0 gh_diag="" raw_diag=""

        if scrow_check_network "https://github.com/midn8crow/scrow.git/info/refs?service=git-upload-pack" "github.com"; then
            gh_ok=1
        else
            gh_diag="$SCROW_NET_DIAG"
        fi

        if scrow_check_network "https://raw.githubusercontent.com/midn8crow/scrow/main/bootstrap.sh" "raw.githubusercontent.com"; then
            raw_ok=1
        else
            raw_diag="$SCROW_NET_DIAG"
        fi

        if (( gh_ok && raw_ok )); then
            [[ "$quiet" == "1" ]] || ui_ok "HTTPS connectivity to GitHub verified"
            return 0
        fi

        if (( quiet == 0 )); then
            if (( gh_ok )); then
                ui_err "GitHub is reachable, but raw.githubusercontent.com is not — SCROW cannot fetch its raw files."
                [[ -n "$raw_diag" ]] && ui_dim "  Reason: $raw_diag"
            elif (( raw_ok )); then
                ui_err "raw.githubusercontent.com is reachable, but github.com is not — SCROW cannot clone its repository."
                [[ -n "$gh_diag" ]] && ui_dim "  Reason: $gh_diag"
            else
                ui_err "Unable to reach GitHub over HTTPS — SCROW needs it to fetch its repository and packages."
                [[ -n "$gh_diag" ]]  && ui_dim "  github.com:               $gh_diag"
                [[ -n "$raw_diag" ]] && ui_dim "  raw.githubusercontent.com: $raw_diag"
            fi
            ui_dim "  Check your connection, DNS or proxy settings."
            ui_dim "  Details are in the SCROW log: $SCROW_CURRENT_LOG"
        fi

        [[ "$quiet" == "1" ]] && return 1
        if [[ "$UI_INTERACTIVE" == "1" ]] && ui_confirm "Retry the connectivity check?" "y"; then
            continue
        fi
        return 1
    done
}

scrow_detect_system() {
    ui_step "Checking system…"
    if [[ ! -f /etc/arch-release ]]; then
        ui_err "SCROW requires Arch Linux."
        return 1
    fi
    ui_ok "Arch Linux detected"

    scrow_check_network_now
}

scrow_detect_gpu() {
    SCROW_GPU="none"
    if command -v lspci >/dev/null 2>&1; then
        if lspci 2>/dev/null | grep -qi "nvidia"; then
            SCROW_GPU="nvidia"
        elif lspci 2>/dev/null | grep -qi "amd"; then
            SCROW_GPU="amd"
        elif lspci 2>/dev/null | grep -qi "intel"; then
            SCROW_GPU="intel"
        fi
    fi
    scrow_log "gpu detected: $SCROW_GPU"
}

scrow_detect_laptop() {
    SCROW_LAPTOP=0
    if [[ -d /sys/class/power_supply/BAT0 ]] || [[ -d /sys/class/power_supply/BAT1 ]]; then
        SCROW_LAPTOP=1
    fi
    scrow_log "laptop detected: $SCROW_LAPTOP"
}

scrow_gpu_ucode() {
    case "$SCROW_GPU" in
        amd)   echo "amd-ucode" ;;
        intel) echo "intel-ucode" ;;
        *)     echo "" ;;
    esac
}

scrow_gpu_packages() {
    # Prints the GPU driver / codec packages needed for the detected GPU.
    local ucode
    ucode="$(scrow_gpu_ucode)"
    [[ -n "$ucode" ]] && echo "$ucode"
    case "$SCROW_GPU" in
        amd)
            echo "mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon libva-mesa-driver mesa-vdpau"
            ;;
        intel)
            echo "mesa lib32-mesa vulkan-intel lib32-vulkan-intel intel-media-driver libva-intel-driver"
            ;;
        nvidia)
            echo "nvidia-dkms nvidia-utils lib32-nvidia-utils nvidia-settings libva-nvidia-driver"
            ;;
    esac
}

scrow_gpu_desc() {
    case "$SCROW_GPU" in
        amd) echo "AMD" ;;
        intel) echo "Intel" ;;
        nvidia) echo "NVIDIA" ;;
        *) echo "None detected" ;;
    esac
}
