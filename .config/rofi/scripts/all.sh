#!/usr/bin/env bash
# rofi "All Apps" tab: every desktop app (same visibility rules as drun).

APP_MODE=all
PROMPT="All Apps"
source "$HOME/.config/rofi/lib/_applist.sh"
run_applist "$@"
