# shellcheck shell=bash
# SCROW — environment variables (sourced by setup, not executed directly)

XDG_BIN_HOME="${XDG_BIN_HOME:-$HOME/.local/bin}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"

# Colors
RED=$'\e[31m'
GREEN=$'\e[32m'
YELLOW=$'\e[33m'
BLUE=$'\e[34m'
PURPLE=$'\e[35m'
CYAN=$'\e[36m'
BOLD=$'\e[1m'
FAINT=$'\e[2m'
ITALIC=$'\e[3m'
UNDERLINE=$'\e[4m'
INVERT=$'\e[7m'
RST=$'\e[00m'

# SCROW state
BACKUP_DIR="${BACKUP_DIR:-$HOME/scrow-original-dots-backup}"
INSTALLED_LISTFILE="${XDG_CONFIG_HOME}/scrow/installed_listfile"
FIRSTRUN_FILE="${XDG_CONFIG_HOME}/scrow/installed_true"

# Temp file registry
declare -a TEMP_FILES_TO_CLEANUP=()
