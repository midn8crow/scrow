#!/usr/bin/env bash

# rotate-screen.sh - rotate the focused monitor's display by 90-degree steps.
# Usage: rotate-screen.sh cw|ccw|half|reset

set -euo pipefail

dir="${1:-cw}"

mon=$(hyprctl -j monitors | jq -r '.[] | select(.focused == true) | .name' | head -n1)
[[ -n "$mon" ]] || { echo "rotate-screen: no focused monitor" >&2; exit 1; }

cur=$(hyprctl -j monitors | jq -c --arg m "$mon" '.[] | select(.name == $m)')
t=$(echo "$cur" | jq -r '.transform')
t=${t:-0}

case "$dir" in
    cw)    nt=$(( (t + 1) % 4 )) ;;
    ccw)   nt=$(( (t + 3) % 4 )) ;;
    half)  nt=$(( (t + 2) % 4 )) ;;
    reset) nt=0 ;;
    *)     echo "usage: $0 cw|ccw|half|reset" >&2; exit 1 ;;
esac

mode=$(echo "$cur" | jq -r '"\(.width)x\(.height)@\(.refreshRate)"')
pos=$(echo "$cur" | jq -r '"\(.x)x\(.y)"')
scale=$(echo "$cur" | jq -r '.scale')

hyprctl eval "hl.monitor({ output = \"$mon\", mode = \"$mode\", position = \"$pos\", scale = \"$scale\", transform = $nt })"

# Only run the mouse-unrotate daemon while the screen is actually rotated.
# On reset the kernel releases the grab and destroys the virtual mouse.
daemon="$HOME/.local/bin/mouse-rotate-daemon.py"
daemon_running() { pgrep -f "$daemon" >/dev/null 2>&1; }
start_daemon() {
    if ! daemon_running; then
        setsid nohup "$daemon" </dev/null >/dev/null 2>&1 &
        disown
    fi
}
kill_daemon() { pkill -f "$daemon" 2>/dev/null || true; }
notify() {
    notify-send --app-name=rotate-screen.sh --icon=object-rotate-right -t 1000 \
        --hint=string:x-canonical-private-synchronous:mouse-driver "$1" "$2" >/dev/null 2>&1 || true
}

if [ "$nt" -eq 0 ]; then
    kill_daemon
    notify "Mouse Driver" "off — normal input"
else
    start_daemon
    notify "Mouse Driver" "on — pointer un-rotated"
fi

case "$nt" in
    0) label="0° (normal)" ;;
    1) label="90°" ;;
    2) label="180°" ;;
    3) label="270°" ;;
    *) label="$nt" ;;
esac

notify-send --app-name=rotate-screen.sh --icon=object-rotate-right -t 1200 "Display Rotated" "$mon • $label" \
    --hint=string:x-canonical-private-synchronous:display-rotate >/dev/null 2>&1 || true
