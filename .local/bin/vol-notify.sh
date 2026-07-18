#!/bin/bash

STEP=5
SINK="@DEFAULT_AUDIO_SINK@"

case "$1" in
  up)   wpctl set-volume -l 1 "$SINK" "${STEP}%+" ;;
  down) wpctl set-volume "$SINK" "${STEP}%-" ;;
  mute) wpctl set-mute "$SINK" toggle ;;
esac

VOLUME=$(wpctl get-volume "$SINK" | awk '{print int($2 * 100)}')
MUTED=$(wpctl get-volume "$SINK" | grep -q MUTED && echo 1 || echo 0)

if [[ "$MUTED" -eq 1 ]]; then
  notify-send -h "int:value:0" -h "string:x-canonical-private-synchronous:volume" -t 1500 -a "volume" -u low " "
else
  notify-send -h "int:value:${VOLUME}" -h "string:x-canonical-private-synchronous:volume" -t 1500 -a "volume" -u low " "
fi
