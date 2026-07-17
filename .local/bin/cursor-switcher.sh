#!/bin/bash

CURSOR_SIZE=$(hyprctl getoption cursor_size 2>/dev/null | grep "int:" | awk '{print $2}')
[ -z "$CURSOR_SIZE" ] || [ "$CURSOR_SIZE" -le 0 ] && CURSOR_SIZE=24

ICONS_DIR="$HOME/.local/share/icons"
GTK3_DIR="$HOME/.config/gtk-3.0"
GTK4_DIR="$HOME/.config/gtk-4.0"
STATE_FILE="$HOME/.config/hypr/.cursor-theme"

case "$1" in
    "SCROW (Recommended)")
        CURSOR_THEME="Bibata-Modern-Classic"
        ;;
    "Bibata Modern Ice")
        CURSOR_THEME="Bibata-Modern-Ice"
        ;;
    "Bibata Original Classic")
        CURSOR_THEME="Bibata-Original-Classic"
        ;;
    "Phinger Dark")
        CURSOR_THEME="phinger-cursors-dark"
        ;;
    "Phinger Light")
        CURSOR_THEME="phinger-cursors-light"
        ;;
    "Minecraft Animated")
        CURSOR_THEME="Minecraft-Animated"
        ;;
    "Windows 11 Dark")
        CURSOR_THEME="Windows11Dark"
        ;;
    *)
        exit 1
        ;;
esac

# Save state
mkdir -p "$(dirname "$STATE_FILE")"
echo "$CURSOR_THEME" > "$STATE_FILE"

# Apply cursor via hyprctl
hyprctl setcursor "$CURSOR_THEME" "$CURSOR_SIZE"

# Update GTK settings
mkdir -p "$GTK3_DIR" "$GTK4_DIR"
if [ -f "$GTK3_DIR/settings.ini" ]; then
    sed -i "s/^gtk-cursor-theme-name=.*/gtk-cursor-theme-name=$CURSOR_THEME/" "$GTK3_DIR/settings.ini"
else
    cat > "$GTK3_DIR/settings.ini" << EOF
[Settings]
gtk-cursor-theme-name=$CURSOR_THEME
gtk-cursor-theme-size=$CURSOR_SIZE
EOF
fi
cp "$GTK3_DIR/settings.ini" "$GTK4_DIR/settings.ini"

# Update XDG cursor settings
mkdir -p "$HOME/.icons/default"
cat > "$HOME/.icons/default/index.theme" << EOF
[Icon Theme]
Inherits=$CURSOR_THEME
EOF

# Notify
notify-send -u low -t 2000 "Cursor" "Switched to $CURSOR_THEME"
