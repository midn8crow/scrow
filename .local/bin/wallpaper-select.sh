#!/bin/bash
PATH="/usr/bin:$HOME/.local/bin:$PATH"

WALL_DIR="$HOME/Pictures/Wallpapers"

apply_colors() {
    matugen image "$1" --mode dark --source-color-index 0 2>/dev/null || { echo "matugen failed for $1" >&2; exit 1; }
    "$HOME/.config/matugen/post-apply.sh"
}

mapfile -t walls < <(find "$WALL_DIR" -maxdepth 1 -type f \( -name '*.jpg' -o -name '*.png' -o -name '*.jpeg' -o -name '*.webp' \) | sort)
count=${#walls[@]}

if [[ $count -eq 0 ]]; then
    notify-send "Wallpaper" "No wallpapers found in $WALL_DIR"
    exit 1
fi

THUMB_DIR="$HOME/.cache/wallpaper-thumbs"
mkdir -p "$THUMB_DIR"

TMPFILE=$(mktemp)
for w in "${walls[@]}"; do
    name=$(basename "$w")
    thumb="$THUMB_DIR/$name"
    if [ ! -f "$thumb" ]; then
        ffmpegthumbnailer -i "$w" -o "$thumb" -s 256 -q 6 2>/dev/null
    fi
    printf '%s\0icon\x1f%s\n' "$name" "$thumb" >> "$TMPFILE"
done

SEL=$(rofi -dmenu -i -p "Wallpaper" -show-icons -icon-theme "Papirus-Dark" -theme "$HOME/.config/rofi/wallpaper-picker.rasi" < "$TMPFILE")
rm -f "$TMPFILE"

[ -z "$SEL" ] && exit 0

WALL=""
for w in "${walls[@]}"; do
    [[ "$(basename "$w")" == "$SEL" ]] && WALL="$w" && break
done
[ -z "$WALL" ] && exit 0

# Save selected wallpaper index for restore on reboot
HISTORY_FILE="$HOME/.cache/wallpaper-history"
for i in "${!walls[@]}"; do
    [[ "${walls[$i]}" == "$WALL" ]] && echo "$i" > "$HISTORY_FILE" && break
done
echo "static" > "$HOME/.cache/wallpaper-type"

pgrep -x awww-daemon >/dev/null || awww-daemon &
sleep 0.2
TRANSITIONS=(simple fade left right top bottom wipe wave grow center any outer)
RANDOM_TRANSITION=${TRANSITIONS[$((RANDOM % ${#TRANSITIONS[@]}))]}
awww img "$WALL" --transition-fps 60 --transition-type "$RANDOM_TRANSITION" --transition-duration 1

pkill -f "mpvpaper" 2>/dev/null

apply_colors "$WALL"
