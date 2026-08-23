#!/bin/bash

WIDTH=11

json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

status=$(playerctl status 2>/dev/null)
if [[ -z "$status" ]]; then
  fill='~/\~~/\~~/\'
  printf '{"text":"󰏤 %s"}\n' "$(json_escape "$fill")"
  exit 0
fi
  case "$status" in
    Playing) icon="󰝚" ;;
    *)       icon="󰏤" ;;
  esac
  title=$(playerctl metadata title 2>/dev/null)
  artist=$(playerctl metadata artist 2>/dev/null)
  [[ -z "$title" ]] && title="Unknown"

escape() {
  printf '%s' "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'
}

if [[ ${#title} -gt $WIDTH ]]; then
  title_part="${title:0:$WIDTH}"
else
  title_part="$title"
fi

title_part=$(escape "$title_part")
printf -v padded "%-${WIDTH}s" "$title_part"

if [[ -n "$artist" ]]; then
  tooltip=$(escape "$artist - $title")
  printf '{"text":"%s %s","tooltip":"%s"}\n' "$icon" "$(json_escape "$padded")" "$(json_escape "$tooltip")"
else
  printf '{"text":"%s %s"}\n' "$icon" "$(json_escape "$padded")"
fi
