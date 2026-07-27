#!/bin/bash
# Refresh Rate Menu - auto-detects all modes from wlr-randr, saves selection to monitors.lua

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
CURRENT_HZ=$(echo "$CURRENT_MODE" | sed 's/.*@//; s/Hz//')

TMPFILE=$(mktemp)

echo "$DATA" | awk -v out="$OUTPUT" -v res="$CURRENT_RES" '
    $1 == out { found=1; next }
    found && /^[A-Z]/ { exit }
    found && $1 == res && /px,/ {
        hz = $3
        mode = $1 "@" $3 "Hz"
        marker = ""
        if ($0 ~ /current/) marker = " [active]"
        else if ($0 ~ /preferred/) marker = " [preferred]"
        if (!seen[hz]++) {
            printf "%s Hz%s\t%s\n", hz, marker, mode
        }
    }
' > "$TMPFILE"

[ ! -s "$TMPFILE" ] && { rm -f "$TMPFILE"; exit 1; }

DISPLAY_LIST=$(awk -F'\t' '{print $1}' "$TMPFILE")
SEL=$(printf "%s\nBack" "$DISPLAY_LIST" | fzf --prompt="Refresh Rate ($CURRENT_RES) > " --reverse --border --ansi)

[ -z "$SEL" ] && { rm -f "$TMPFILE"; exit 0; }
[ "$SEL" = "Back" ] && { rm -f "$TMPFILE"; exit 0; }

MODE=$(grep -F "$SEL" "$TMPFILE" | head -1 | cut -f2)
rm -f "$TMPFILE"

[ -z "$MODE" ] && exit 1

NEW_HZ=$(echo "$MODE" | sed 's/.*@//; s/Hz//')

if [ "$NEW_HZ" != "$CURRENT_HZ" ]; then
    wlr-randr --output "$OUTPUT" --mode "$MODE"

    MONITOR_CFG="$HOME/.config/hypr/modules/monitors.lua"
    if [ -f "$MONITOR_CFG" ]; then
        sed -i "s/mode     = .*/mode     = \"${MODE}\",/" "$MONITOR_CFG"
    fi

    notify-send -t 3000 "Refresh Rate" "Set to $NEW_HZ Hz"
fi
