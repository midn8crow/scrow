#!/bin/bash

OUTPUT=$(wlr-randr 2>/dev/null | head -1 | awk '{print $1}')
[ -z "$OUTPUT" ] && exit 1

DATA=$(wlr-randr 2>/dev/null)

CURRENT_RES=$(echo "$DATA" | awk -v out="$OUTPUT" '
    $1 == out { found=1; next }
    found && /^[A-Z]/ { exit }
    found && /current/ { print $1; exit }
')

[ -z "$CURRENT_RES" ] && exit 1

RESOLUTIONS=$(echo "$DATA" | awk -v out="$OUTPUT" -v cur="$CURRENT_RES" '
    $1 == out { found=1; next }
    found && /^[A-Z]/ { exit }
    found && /px,/ {
        res = $1
        marker = ""
        if ($0 ~ /current/) marker = " [active]"
        if (!seen[res]++) {
            if (res == cur) marker = " [active]"
            printf "%s%s\n", res, marker
        }
    }
')

[ -z "$RESOLUTIONS" ] && exit 1

SEL=$(printf "Back\n$RESOLUTIONS" | rofi -dmenu -p "Resolution" -theme-str 'configuration { show-icons: false; }')

[ -z "$SEL" ] && exit 0
[ "$SEL" = "Back" ] && exit 0

NEW_RES=$(echo "$SEL" | sed 's/ \[active\]//')

if [ "$NEW_RES" != "$CURRENT_RES" ]; then
    # Get the preferred Hz for the new resolution
    PREF_HZ=$(echo "$DATA" | awk -v out="$OUTPUT" -v res="$NEW_RES" '
        $1 == out { found=1; next }
        found && /^[A-Z]/ { exit }
        found && $1 == res && /px,/ {
            if ($0 ~ /preferred/) { print $3; exit }
        }
    ')
    [ -z "$PREF_HZ" ] && PREF_HZ=$(echo "$DATA" | awk -v out="$OUTPUT" -v res="$NEW_RES" '
        $1 == out { found=1; next }
        found && /^[A-Z]/ { exit }
        found && $1 == res && /px,/ { print $3; exit }
    ')

    wlr-randr --output "$OUTPUT" --mode "${NEW_RES}@${PREF_HZ}Hz"

    MONITOR_CFG="$HOME/.config/hypr/modules/monitors.lua"
    if [ -f "$MONITOR_CFG" ]; then
        sed -i "s/mode     = .*/mode     = \"${NEW_RES}@${PREF_HZ}\",/" "$MONITOR_CFG"
    fi

    notify-send -t 3000 "Resolution" "Set to ${NEW_RES}@${PREF_HZ}Hz"
fi
