#!/bin/bash
# Toggle per-window blur for the active window (dusky-style)
# Usage: called by SUPER+period keybind

ADDR=$(hyprctl activewindow -j | jq -r '.address')

# Check current no_blur state via the window's decoration info
# We use tags to track state since no_blur isn't exposed by hyprctl
TAGS=$(hyprctl activewindow -j | jq -r '.tags[]' 2>/dev/null)

if echo "$TAGS" | grep -q "^nobblur$"; then
    hyprctl dispatch "setprop address:$ADDR noblur 0"
    hyprctl dispatch "setprop address:$ADDR opaque 0"
else
    hyprctl dispatch "setprop address:$ADDR noblur 1"  
    hyprctl dispatch "setprop address:$ADDR opaque 1"
fi
