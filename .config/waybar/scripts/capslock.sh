#!/usr/bin/env bash
# Waybar caps lock status. Shows a pill only while Caps Lock is on.
# Reads the sysfs LED (cheap); falls back to hyprctl if not available.

caps="off"
sf=$(ls /sys/class/leds/*::capslock/brightness 2>/dev/null | head -1)
if [ -n "$sf" ] && [ -r "$sf" ]; then
    [ "$(cat "$sf")" != "0" ] && caps="on"
elif hyprctl -j devices 2>/dev/null | grep -q '"capsLock": true'; then
    caps="on"
fi

if [ "$caps" = on ]; then
    printf '{"text": " 󰌌 CAPS ", "class": "on", "alt": "on"}\n'
else
    printf '{"text": "", "class": "off", "alt": "off"}\n'
fi
