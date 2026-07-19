#!/bin/bash

DIR="${0%/*}"
STATE_FILE="$DIR/.current"

pkill waybar 2>/dev/null
sleep 0.3

config=$(cat "$STATE_FILE" 2>/dev/null)
if [[ -z "$config" || "$config" == "default" ]]; then
    waybar &
else
    waybar -c "$DIR/config-${config}.jsonc" -s "$DIR/style-${config}.css" &
fi
