#!/bin/bash

options=" Lock
 Logout
 Suspend
 Reboot
 Shutdown"

chosen=$(echo -e "$options" | rofi -dmenu -p "Power Menu" -theme-str 'window { width: 300; }')

[ -z "$chosen" ] && exit 0
sleep 0.3

case "$chosen" in
    *Lock)     hyprlock ;;
    *Logout)   hyprctl dispatch 'hl.dsp.exit()' ;;
    *Suspend)  systemctl suspend ;;
    *Reboot)   systemctl reboot ;;
    *Shutdown) systemctl poweroff ;;
esac
