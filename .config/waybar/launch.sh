#!/bin/bash

DIR="${0%/*}"
STATE_FILE="$DIR/.current"

pkill waybar 2>/dev/null
sleep 0.3

config=$(cat "$STATE_FILE" 2>/dev/null)

# auto-detect: if config not set or doesn't exist, use first available
if [[ -z "$config" || ! -f "$DIR/config-${config}.jsonc" ]]; then
    first=$(ls "$DIR"/config-*.jsonc 2>/dev/null | head -1)
    if [[ -n "$first" ]]; then
        config=$(basename "$first" | sed 's/^config-//; s/\.jsonc$//')
        echo "$config" > "$STATE_FILE"
    fi
fi

if [[ -z "$config" || ! -f "$DIR/config-${config}.jsonc" ]]; then
    waybar &
else
    waybar -c "$DIR/config-${config}.jsonc" -s "$DIR/style-${config}.css" &
fi
