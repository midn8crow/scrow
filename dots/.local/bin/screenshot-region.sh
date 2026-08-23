#!/bin/bash

DIR="$HOME/Pictures/Screenshots"
mkdir -p "$DIR"
FILE="$DIR/screenshot-$(date +%Y%m%d-%H%M%S).png"

region=$(slurp 2>/dev/null) || exit 1
grim -g "$region" "$FILE" 2>/dev/null || exit 1
wl-copy < "$FILE"
notify-send "Screenshot" "Region saved and copied to clipboard"
