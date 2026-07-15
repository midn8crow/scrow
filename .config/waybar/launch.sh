#!/bin/bash

DIR="${0%/*}"
STATE_FILE="$DIR/.current"

if pgrep -x waybar > /dev/null; then
    pkill waybar
else
    config=$(cat "$STATE_FILE" 2>/dev/null)
    if [[ -z "$config" || "$config" == "default" ]]; then
        waybar &
    else
        waybar -c "$DIR/config-${config}.jsonc" -s "$DIR/style-${config}.css" &
    fi
fi
