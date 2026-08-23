#!/bin/bash

# Scrow-style Control Center - WiFi & Bluetooth
ROFI_THEME="$HOME/.config/rofi/control-center.rasi"
SCROW_PY="$HOME/user_scripts/scrow_tui/.venv/bin/python"
TUI_MAIN="$HOME/user_scripts/scrow_tui/python/main/main.py"
TUI_SCRIPT="$HOME/user_scripts/network_manager/tui_scrow_network.py"

options="󰤨  WiFi
󰂯  Bluetooth"

choice=$(echo "$options" | rofi -dmenu -p "Control Center" -theme "$ROFI_THEME" -theme-str 'listview { lines: 2; }')
[[ -z "$choice" ]] && exit 0

case "$choice" in
    *WiFi)
        kitty --class scrow_tui --title "Scrow Network Manager" \
            -o remember_window_size=no \
            -o initial_window_width=960 \
            -o initial_window_height=700 \
            -e "$SCROW_PY" "$TUI_MAIN" "$TUI_SCRIPT"
        ;;
    *Bluetooth)
        blueman-manager
        ;;
esac
