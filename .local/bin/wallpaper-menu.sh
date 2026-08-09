#!/bin/bash

SEL=$(printf "Wallpaper\nLive Wallpaper" | rofi -dmenu -p "Wallpaper" -theme-str 'configuration { show-icons: false; } window { width: 14%; }')

[ -z "$SEL" ] && exit 0

case "$SEL" in
    Wallpaper)
        exec "$HOME/.local/bin/wallpaper-select.sh"
        ;;
    Live\ Wallpaper)
        exec "$HOME/.local/bin/live-wallpaper-select.sh"
        ;;
esac
