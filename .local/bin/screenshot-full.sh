#!/bin/bash

DIR="$HOME/Pictures/Screenshots"
mkdir -p "$DIR"
FILE="$DIR/screenshot-$(date +%Y%m%d-%H%M%S).png"

grim "$FILE" 2>/dev/null || exit 1
wl-copy < "$FILE"
notify-send "Screenshot" "Full screen saved and copied to clipboard"
