#!/bin/bash

options=" Lock
 Logout
 Suspend
 Reboot
 Shutdown"

chosen=$(echo -e "$options" | rofi -dmenu -p "Power Menu")

[ -z "$chosen" ] && exit 0
sleep 0.3

case "$chosen" in
    *Lock)     hyprlock ;;
    *Logout)   hyprctl dispatch 'hl.dsp.exit()' ;;
    *Suspend)  systemctl suspend ;;
    *Reboot)   systemctl reboot ;;
    *Shutdown) systemctl poweroff ;;
esac
