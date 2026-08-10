#!/bin/bash
# osd.sh - OSD-style volume/brightness slider for mako
# usage: osd.sh <app> <value> [muted]
# app: "volume" or "brightness" (drives the icon); mako matches [app-name=osd].
# The slider itself is mako's native progress fill (int:value hint).

app="$1"
value="$2"
muted="${3:-0}"

value=$((10#${value:-0}))
[ "$value" -lt 0 ]  && value=0
[ "$value" -gt 100 ] && value=100

case "$app" in
  volume)
    if [ "$muted" -eq 1 ]; then
      icon="audio-volume-muted"
    elif [ "$value" -ge 67 ]; then
      icon="audio-volume-high"
    elif [ "$value" -ge 34 ]; then
      icon="audio-volume-medium"
    else
      icon="audio-volume-low"
    fi
    ;;
  brightness)
    icon="brightnesssettings"
    ;;
  *) icon="" ;;
esac

if [ "$muted" -eq 1 ]; then
  red=$(awk -F= '/^red=/{print $2; exit}' "$HOME/.config/scrowmenu/colors.conf" 2>/dev/null)
  red="${red:-#ffb4ab}"
  body="<span fgcolor='${red}'>${value}%</span>"
else
  body="${value}%"
fi

notify-send \
  -a osd \
  -u low \
  -t 1500 \
  -i "$icon" \
  -h "string:x-canonical-private-synchronous:osd" \
  -h "int:value:${value}" \
  "OSD" \
  "$body"
