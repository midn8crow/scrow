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
    setsid waybar >/dev/null 2>&1 &
else
    CFG="$DIR/config-${config}.jsonc"
    STYLE="$DIR/style-${config}.css"
    mapfile -t OUT <<< "$(python3 "$DIR/capslock.py" "$CFG" "$STYLE")"
    PCFG="${OUT[0]}"
    PSTYLE="${OUT[1]}"
    [[ -z "$PSTYLE" ]] && PSTYLE="$STYLE"
    if [[ -n "$PCFG" && -f "$PCFG" ]]; then
        setsid waybar -c "$PCFG" -s "$PSTYLE" >/dev/null 2>&1 &
    else
        setsid waybar -c "$CFG" -s "$STYLE" >/dev/null 2>&1 &
    fi
    find "$DIR" -maxdepth 1 -name ".capslock-style-*.css" ! -name ".capslock-style-${config}.css" -delete 2>/dev/null
fi
