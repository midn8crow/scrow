#!/usr/bin/env bash
# Caps Lock indicator for Hyprland
#   - Shows a normal mako notification on each Caps Lock toggle, then it fades
#
# State source: hyprctl devices (compositor truth), sysfs LED as fallback.

exec 9>/tmp/capslock-indicator.lock
flock -n 9 || exit 0
exec </dev/null

echo $$ > /tmp/capslock-indicator.pid
trap 'rm -f /tmp/capslock-indicator.pid' EXIT

BADGE_ID=""

caps_state() {
    local sf
    sf=$(ls /sys/class/leds/*::capslock/brightness 2>/dev/null | head -1)
    if [ -n "$sf" ] && [ -r "$sf" ]; then
        [ "$(cat "$sf")" != "0" ] && echo on || echo off
        return
    fi
    if hyprctl -j devices 2>/dev/null | grep -q '"capsLock": true'; then
        echo on
    else
        echo off
    fi
}

refresh_badge() {
    local state="$1"
    local urgency="low" label="OFF"
    if [ "$state" = on ]; then
        urgency="critical"
        label="ON"
    fi
    if [ -n "$BADGE_ID" ]; then
        notify-send -r "$BADGE_ID" -u "$urgency" -a capslock "CAPS LOCK" "$label"
    else
        notify-send -u "$urgency" -a capslock "CAPS LOCK" "$label"
    fi
    BADGE_ID=$(makoctl list 2>/dev/null | awk '/^Notification /{id=$2; gsub(":","",id)} /App name: capslock/{print id}' | tail -1)
}

last=""
while true; do
    s=$(caps_state)
    if [ "$s" != "$last" ]; then
        last="$s"
        refresh_badge "$s"
    fi
    sleep 0.15
done
