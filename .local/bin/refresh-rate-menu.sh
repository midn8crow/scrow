#!/bin/bash

OUTPUT=$(wlr-randr 2>/dev/null | head -1 | awk '{print $1}')
[ -z "$OUTPUT" ] && exit 1

DATA=$(wlr-randr 2>/dev/null)

CURRENT_HZ=$(echo "$DATA" | awk -v out="$OUTPUT" '
    $1 == out { found=1; next }
    found && /^[A-Z]/ { exit }
    found && /current/ { print $3; exit }
')

CURRENT_RES=$(echo "$DATA" | awk -v out="$OUTPUT" '
    $1 == out { found=1; next }
    found && /^[A-Z]/ { exit }
    found && /current/ { print $1; exit }
')

[ -z "$CURRENT_HZ" ] && exit 1

RATES=$(echo "$DATA" | awk -v out="$OUTPUT" -v res="$CURRENT_RES" '
    $1 == out { found=1; next }
    found && /^[A-Z]/ { exit }
    found && $1 == res && /px,/ {
        hz = $3
        marker = ""
        if ($0 ~ /current/) marker = " [active]"
        else if ($0 ~ /preferred/) marker = " [preferred]"
        if (!seen[hz]++) {
            printf "%s Hz%s\n", hz, marker
        }
    }
')

[ -z "$RATES" ] && exit 1

SEL=$(echo "$RATES" | rofi -dmenu -p "Refresh Rate ($CURRENT_RES)" -theme-str 'configuration { show-icons: false; }')

[ -z "$SEL" ] && exit 0

NEW_HZ=$(echo "$SEL" | sed 's/ Hz\[active\]//; s/ Hz\[preferred\]//; s/ Hz//')

if [ "$NEW_HZ" != "$CURRENT_HZ" ]; then
    wlr-randr --output "$OUTPUT" --mode "${CURRENT_RES}@${NEW_HZ}Hz"

    MONITOR_CFG="$HOME/.config/hypr/modules/monitors.lua"
    if [ -f "$MONITOR_CFG" ]; then
        sed -i "s/mode     = .*/mode     = \"${CURRENT_RES}@${NEW_HZ}\",/" "$MONITOR_CFG"
    fi

    notify-send -t 3000 "Refresh Rate" "Set to $NEW_HZ Hz"
fi
