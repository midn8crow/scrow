#!/bin/bash

STEP=5
MIN=1
MAX=100
LOCK="/tmp/brightness.lock"

# Prevent overlapping ddcutil calls
[ -f "$LOCK" ] && exit 0
touch "$LOCK"
trap 'rm -f "$LOCK"' EXIT

get_brightness() {
    ddcutil getvcp 10 2>/dev/null | sed 's/,/ /g' | awk '{for(i=1;i<=NF;i++) if($(i)=="value" && $(i+1)=="=") {gsub(/[^0-9]/,"",$(i+2)); print $(i+2)}}' | head -1
}

CURRENT=$(get_brightness)
CURRENT=${CURRENT:-50}

case "$1" in
  up)
    NEW=$((CURRENT + STEP))
    [ "$NEW" -gt "$MAX" ] && NEW="$MAX"
    ddcutil setvcp 10 "$NEW" 2>/dev/null
    ;;
  down)
    NEW=$((CURRENT - STEP))
    [ "$NEW" -lt "$MIN" ] && NEW="$MIN"
    ddcutil setvcp 10 "$NEW" 2>/dev/null
    ;;
esac

sleep 0.3
BRIGHTNESS=$(get_brightness)

if [[ -n "$BRIGHTNESS" ]]; then
  notify-send -h "int:value:${BRIGHTNESS}" -h "string:x-canonical-private-synchronous:brightness" -t 1500 -a "brightness" -u low " "
fi
