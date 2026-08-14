#!/bin/bash
WALL_DIR="$HOME/Pictures/Wallpapers"
HISTORY_FILE="$HOME/.cache/wallpaper-history"

apply_colors() {
    matugen image "$1" --mode dark 2>/dev/null || { notify-send "Color Pick" "matugen failed"; exit 1; }
    "$HOME/.config/matugen/post-apply.sh"
}

# Check if live wallpaper (mpvpaper) is running
if pgrep -f "mpvpaper" >/dev/null 2>&1; then
    SCREENSHOT="/tmp/color-pick-screen.png"
    grim -o "$(hyprctl monitors -j | python3 -c 'import sys,json; print(json.load(sys.stdin)[0]["name"])')" -t png "$SCREENSHOT" 2>/dev/null
    [[ ! -f "$SCREENSHOT" ]] && notify-send "Color Pick" "Failed to capture screen" && exit 1
    img_src="$SCREENSHOT"
else
    idx=0
    [[ -f "$HISTORY_FILE" ]] && idx=$(cat "$HISTORY_FILE" 2>/dev/null) || idx=0
    mapfile -t walls < <(find "$WALL_DIR" -type f \( -name '*.jpg' -o -name '*.png' -o -name '*.jpeg' -o -name '*.webp' \) | sort)
    wall="${walls[$idx]:-}"
    [[ -z "$wall" ]] && notify-send "Color Pick" "No wallpaper found" && exit 1
    img_src="$wall"
fi

# Get screen dimensions
eval $(hyprctl monitors -j | python3 -c "
import sys, json
m = json.load(sys.stdin)[0]
w, h = m['width'], m['height']
sx, sy = m['x'], m['y']
scale = m['scale']
print(f'SW={w} SH={h} SX={sx} SY={sy} SCALE={scale}')
")

# Let user select a region
region=$(slurp -w 0 -b '#00000000' -c '#ffffff80' 2>/dev/null) || exit 1
x=$(echo "$region" | cut -d, -f1)
y=$(echo "$region" | cut -d, -f2 | cut -d' ' -f1)
w=$(echo "$region" | cut -d' ' -f2 | cut -dx -f1)
h=$(echo "$region" | cut -dx -f2)

# Get image dimensions
img_w=$(ffprobe -v error -select_streams v:0 -show_entries stream=width  -of csv=p=0 "$img_src")
img_h=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$img_src")

rw=$(echo "$img_w $SW $w" | awk '{ printf "%d", ($1 / $2) * $3 }')
rh=$(echo "$img_h $SH $h" | awk '{ printf "%d", ($1 / $2) * $3 }')
rx=$(echo "$img_w $SW $x" | awk '{ printf "%d", ($1 / $2) * $3 }')
ry=$(echo "$img_h $SH $y" | awk '{ printf "%d", ($1 / $2) * $3 }')

# Crop and resize
crop="/tmp/color-pick-crop.png"
ffmpeg -i "$img_src" -vf "crop=${rw}:${rh}:${rx}:${ry},scale=400:400:force_original_aspect_ratio=decrease" -y "$crop" 2>/dev/null

apply_colors "$crop"
rm -f "$crop"

notify-send "Color Pick" "Colors extracted from selected region"
