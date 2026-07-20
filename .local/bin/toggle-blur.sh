#!/bin/bash
ADDR=$(hyprctl activewindow -j | jq -r '.address')
STATE="/tmp/hypr_blur_$ADDR"

if [ -f "$STATE" ]; then
    hyprctl dispatch --batch "setprop address:$ADDR opaque 0 ; setprop address:$ADDR no_blur 0" >/dev/null 2>&1
    rm -f "$STATE"
else
    hyprctl dispatch --batch "setprop address:$ADDR opaque 1 ; setprop address:$ADDR no_blur 1" >/dev/null 2>&1
    touch "$STATE"
fi
