#!/usr/bin/env bash
# =============================================================================
# SCROW - hardware / system detection
# =============================================================================

SCROW_GPU="none"
SCROW_LAPTOP=0

scrow_detect_system() {
    ui_step "Checking system…"
    if [[ ! -f /etc/arch-release ]]; then
        ui_err "SCROW requires Arch Linux."
        return 1
    fi
    ui_ok "Arch Linux detected"

    if ! ping -c 1 -W 3 archlinux.org >/dev/null 2>&1 \
       && ! ping -c 1 -W 3 1.1.1.1 >/dev/null 2>&1; then
        ui_err "No internet connection."
        return 1
    fi
    ui_ok "Internet connection verified"
    return 0
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
