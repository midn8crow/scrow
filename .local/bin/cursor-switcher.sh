#!/bin/bash

STATE_FILE="$HOME/.config/hypr/.cursor-theme"

case "$1" in
    "SCROW (Recommended)")      CURSOR_THEME="Bibata-Modern-Classic" ;;
    "Bibata Modern Ice")        CURSOR_THEME="Bibata-Modern-Ice" ;;
    "Bibata Original Classic")  CURSOR_THEME="Bibata-Original-Classic" ;;
    "Phinger Dark")             CURSOR_THEME="phinger-cursors-dark" ;;
    "Phinger Light")            CURSOR_THEME="phinger-cursors-light" ;;
    "Minecraft Animated")       CURSOR_THEME="Minecraft-Animated" ;;
    "Windows 11 Dark")          CURSOR_THEME="Windows11Dark" ;;
    *) exit 1 ;;
esac

echo "$CURSOR_THEME" > "$STATE_FILE"

hyprctl setcursor "$CURSOR_THEME" 24

mkdir -p "$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0"
cat > "$HOME/.config/gtk-3.0/settings.ini" << EOF
[Settings]
gtk-cursor-theme-name=$CURSOR_THEME
gtk-cursor-theme-size=24
EOF
cp "$HOME/.config/gtk-3.0/settings.ini" "$HOME/.config/gtk-4.0/settings.ini"

mkdir -p "$HOME/.icons/default"
cat > "$HOME/.icons/default/index.theme" << EOF
[Icon Theme]
Inherits=$CURSOR_THEME
EOF

notify-send -u low -t 2000 "Cursor" "Switched to $CURSOR_THEME"
