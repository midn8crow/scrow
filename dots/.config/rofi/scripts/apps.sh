#!/usr/bin/env bash
# rofi "Apps" tab: all desktop apps except the curated system apps.

APP_MODE=normal
PROMPT="Apps"
source "$HOME/.config/rofi/lib/_applist.sh"
run_applist "$@"
