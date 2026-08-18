#!/usr/bin/env bash
# =============================================================================
# SCROW — distro detection
# =============================================================================
# Detect the current Linux distribution and set SCROW_DISTRO_ID.

SCROW_DISTRO_ID="unknown"
SCROW_DISTRO_FAMILY="unknown"

detect_distro() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        source /etc/os-release
        SCROW_DISTRO_ID="${ID:-unknown}"
        SCROW_DISTRO_FAMILY="${ID_LIKE:-$SCROW_DISTRO_ID}"
    elif command -v lsb_release >/dev/null 2>&1; then
        SCROW_DISTRO_ID="$(lsb_release -is 2>/dev/null | tr '[:upper:]' '[:lower:]')"
    fi
}

detect_distro
