#!/usr/bin/env bash
# =============================================================================
# SCROW — environment variables
# =============================================================================
# Colors, paths, and constants used by the entire installer.

# Colors (ANSI escape codes)
C_RST='\033[0m'
C_BOLD='\033[1m'
C_RED='\033[31m'
C_GRN='\033[32m'
C_YLW='\033[33m'
C_BLU='\033[34m'
C_MAG='\033[35m'
C_CYN='\033[36m'
C_DIM='\033[2m'
C_ITL='\033[3m'
C_USR='\033[4m'
C_OK="${C_GRN}"
C_ERR="${C_RED}"
C_WARN="${C_YLW}"
C_ACT="${C_CYN}"
C_DIR="${C_BLU}"

# Repository root (set by setup, inherited by everything)
REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
export REPO_ROOT

# Version
SCROW_VERSION="$(cat "$REPO_ROOT/VERSION" 2>/dev/null || echo "0.0.0")"
export SCROW_VERSION

# XDG base directories
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
export XDG_BIN_HOME="${XDG_BIN_HOME:-$HOME/.local/bin}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"

# SCROW paths
SCROW_BACKUP_DIR="$XDG_CONFIG_HOME/scrow/backups"
SCROW_INSTALLED_FILE="$XDG_CONFIG_HOME/scrow/installed-components"
SCROW_FIRSTRUN_FILE="$XDG_CACHE_HOME/scrow/firstrun-done"
