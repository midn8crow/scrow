#!/bin/bash

DIR="${0%/*}"
STATE_FILE="$DIR/.current"

config=$(cat "$STATE_FILE" 2>/dev/null)

pkill waybar

if [[ -z "$config" || "$config" == "default" ]]; then
    waybar &
else
    waybar -c "$DIR/config-${config}.jsonc" -s "$DIR/style-${config}.css" &
fi
