#!/bin/bash

LIVE_DIR="$HOME/Pictures/Wallpapers/live"

mapfile -t files < <(find "$LIVE_DIR" -type f \( -name '*.gif' -o -name '*.mp4' -o -name '*.webm' -o -name '*.mkv' -o -name '*.mov' \) 2>/dev/null | sort)

if [[ ${#files[@]} -eq 0 ]]; then
    notify-send "Live Wallpapers" "No live wallpapers found in $LIVE_DIR"
    exit 1
fi

THUMB_DIR="$HOME/.cache/live-wallpaper-thumbs"
mkdir -p "$THUMB_DIR"

TMPFILE=$(mktemp)
for f in "${files[@]}"; do
    name=$(basename "$f")
    thumb="$THUMB_DIR/${name}.jpg"
    if [ ! -f "$thumb" ]; then
        ffmpeg -i "$f" -ss 00:00:01 -vframes 1 -q:v 5 "$thumb" 2>/dev/null
    fi
    printf '%s\0icon\x1f%s\n' "$name" "$thumb" >> "$TMPFILE"
done

SEL=$(rofi -dmenu -i -p "Live Wallpaper" -show-icons -icon-theme "Papirus-Dark" -theme "$HOME/.config/rofi/wallpaper-picker.rasi" < "$TMPFILE")
rm -f "$TMPFILE"

[ -z "$SEL" ] && exit 0

FULL=""
for f in "${files[@]}"; do
    if [[ "$(basename "$f")" == "$SEL" ]]; then
        FULL="$f"
        break
    fi
done

[ -z "$FULL" ] && exit 0

pkill -f "mpvpaper" 2>/dev/null
sleep 0.2

mpvpaper -o "no-audio --loop" --no-config --hwdec=auto-safe HDMI-A-1 "$FULL" >/dev/null 2>&1 &
