#!/bin/bash

WALL_DIR="$HOME/Pictures/Wallpapers"
HISTORY_FILE="$HOME/.cache/wallpaper-history"

apply_colors() {
    matugen image "$1" --mode dark --source-color-index 0 2>/dev/null || { echo "matugen failed for $1" >&2; exit 1; }
    "$HOME/.config/matugen/post-apply.sh"
}

# Get all wallpapers sorted
mapfile -t walls < <(find "$WALL_DIR" -type f \( -name '*.jpg' -o -name '*.png' -o -name '*.jpeg' -o -name '*.webp' \) | sort)
count=${#walls[@]}

if [[ $count -eq 0 ]]; then
    echo "No wallpapers found in $WALL_DIR"
    exit 1
fi

# Read current wallpaper index
current=0
if [[ -f "$HISTORY_FILE" ]]; then
    current=$(cat "$HISTORY_FILE" 2>/dev/null)
    current=${current:-0}
fi

# Self-heal a stale/invalid index (e.g. wallpapers were removed since the last
# use). Falling back to 0 (the SCROW default wallpaper) keeps restore working
# without requiring the user to clear the cache manually.
if [[ ! "$current" =~ ^[0-9]+$ ]] || (( current >= count )) || [[ ! -f "${walls[$current]}" ]]; then
    current=0
    echo "$current" > "$HISTORY_FILE"
fi

if [[ "$1" == "restore" ]]; then
    TYPE_FILE="$HOME/.cache/wallpaper-type"
    if [[ -f "$TYPE_FILE" ]] && [[ "$(cat "$TYPE_FILE" 2>/dev/null)" == "live" ]]; then
        LIVE_PATH="$HOME/.cache/wallpaper-live-path"
        if [[ -f "$LIVE_PATH" ]]; then
            LIVE_WALL=$(cat "$LIVE_PATH" 2>/dev/null)
            if [[ -n "$LIVE_WALL" && -f "$LIVE_WALL" ]]; then
                pgrep -x awww-daemon >/dev/null || awww-daemon &
                sleep 0.2
                mpvpaper -o "no-audio --loop" --no-config --hwdec=auto-safe HDMI-A-1 "$LIVE_WALL" >/dev/null 2>&1 &
                sleep 2

                # Capture frame from live wallpaper for color generation
                FRAME="/tmp/mako-color-frame.png"
                grim -o "$(hyprctl monitors -j | python3 -c 'import sys,json; print(json.load(sys.stdin)[0]["name"])')" -t png "$FRAME" 2>/dev/null

                if [[ -f "$FRAME" ]]; then
                    apply_colors "$FRAME"
                fi
                exit 0
            fi
        fi
    fi
    : # keep current index as-is for static wallpapers
elif [[ "$1" == "prev" ]]; then
    current=$(( (current - 1 + count) % count ))
else
    current=$(( (current + 1) % count ))
fi

wall="${walls[$current]}"
echo "$current" > "$HISTORY_FILE"
echo "static" > "$HOME/.cache/wallpaper-type"

# Ensure awww-daemon is running, set correct wallpaper FIRST (while mpvpaper covers screen)
pgrep -x awww-daemon >/dev/null || awww-daemon &
sleep 0.2
TRANSITIONS=(simple fade left right top bottom wipe wave grow center any outer)
RANDOM_TRANSITION=${TRANSITIONS[$((RANDOM % ${#TRANSITIONS[@]}))]}
awww img "$wall" --transition-fps 60 --transition-type "$RANDOM_TRANSITION" --transition-duration 1

# Now kill live wallpaper (awww already has the correct wallpaper ready)
pkill -f "mpvpaper" 2>/dev/null

apply_colors "$wall"
