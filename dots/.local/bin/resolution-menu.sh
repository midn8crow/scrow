#!/bin/bash
# Resolution Menu - auto-detects all modes from wlr-randr, saves selection to monitors.lua

OUTPUT=$(wlr-randr 2>/dev/null | head -1 | awk '{print $1}')
[ -z "$OUTPUT" ] && exit 1

DATA=$(wlr-randr 2>/dev/null)

CURRENT_MODE=$(echo "$DATA" | awk -v out="$OUTPUT" '
    $1 == out { found=1; next }
    found && /^[A-Z]/ { exit }
    found && /current/ {
        print $1 "@" $3 "Hz"
        exit
    }
')

[ -z "$CURRENT_MODE" ] && exit 1

CURRENT_RES=$(echo "$CURRENT_MODE" | cut -d'@' -f1)

TMPFILE=$(mktemp)

echo "$DATA" | awk -v out="$OUTPUT" -v cur="$CURRENT_RES" -v cur_mode="$CURRENT_MODE" '
    $1 == out { found=1; next }
    found && /^[A-Z]/ { exit }
    found && /px,/ {
        res = $1
        mode = $1 "@" $3 "Hz"
        marker = ""
        if ($0 ~ /current/) marker = " [active]"
        if (!seen[res]++) {
            if (res == cur) mode = cur_mode
            printf "%s%s\t%s\n", res, marker, mode
        }
    }
' > "$TMPFILE"

[ ! -s "$TMPFILE" ] && { rm -f "$TMPFILE"; exit 1; }

DISPLAY_LIST=$(awk -F'\t' '{print $1}' "$TMPFILE")
SEL=$(printf "%s\nBack" "$DISPLAY_LIST" | fzf --prompt="Resolution > " --reverse --border --ansi)

[ -z "$SEL" ] && { rm -f "$TMPFILE"; exit 0; }
[ "$SEL" = "Back" ] && { rm -f "$TMPFILE"; exit 0; }

MODE=$(grep -F "$SEL" "$TMPFILE" | head -1 | cut -f2)
rm -f "$TMPFILE"

[ -z "$MODE" ] && exit 1

NEW_RES=$(echo "$MODE" | cut -d'@' -f1)

if [ "$NEW_RES" != "$CURRENT_RES" ]; then
    wlr-randr --output "$OUTPUT" --mode "$MODE"

    MONITOR_CFG="$HOME/.config/hypr/modules/monitors.lua"
    if [ -f "$MONITOR_CFG" ]; then
        sed -i "s/mode     = .*/mode     = \"${MODE}\",/" "$MONITOR_CFG"
    fi

    notify-send -t 3000 "Resolution" "Set to $NEW_RES"
fi
