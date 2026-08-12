#!/bin/bash
# osd-animator.sh - glides the OSD fill from the current value to the target
# Spawned by osd.sh; reads state from $XDG_RUNTIME_DIR/osd and sends animated
# intermediate frames via mako's synchronous replacement.

DIR="${XDG_RUNTIME_DIR:-/tmp}/osd"

clamp() {
  local v=$((10#$1))
  [ "$v" -lt 0 ] && v=0
  [ "$v" -gt 100 ] && v=100
  echo "$v"
}

read_state() {
  cat "$DIR/$1" 2>/dev/null
}

declare -A ICON_CACHE

resolve_icon() {
  local name="$1" path
  if [ -n "${ICON_CACHE[$name]:-}" ]; then
    echo "${ICON_CACHE[$name]}"
    return
  fi
  path=$(find /usr/share/icons/Papirus-Dark /usr/share/icons/Papirus /usr/share/icons/hicolor \
    -name "${name}.svg" -o -name "${name}.png" 2>/dev/null | head -1)
  ICON_CACHE[$name]="$path"
  echo "$path"
}

icon_for() {
  local app="$1" muted="$2" value="$3"
  case "$app" in
    volume)
      if [ "$muted" -eq 1 ]; then
        echo "audio-volume-muted"
      elif [ "$value" -ge 67 ]; then
        echo "audio-volume-high"
      elif [ "$value" -ge 34 ]; then
        echo "audio-volume-medium"
      else
        echo "audio-volume-low"
      fi
      ;;
    brightness) echo "brightnesssettings" ;;
    *) echo "" ;;
  esac
}

send_frame() {
  local app="$1" value="$2" muted="$3" icon body
  icon=$(icon_for "$app" "$muted" "$value")
  [ -n "$icon" ] && icon=$(resolve_icon "$icon")
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
}

now_ms() {
  echo "$(( $(date +%s%N) / 1000000 ))"
}

app=$(read_state app); app="${app:-volume}"
muted=$(read_state muted); muted="${muted:-0}"
target=$(read_state target); target=$(clamp "$target")
cur=$(read_state "${app}-current")
cur=$(clamp "${cur:-$target}")

last_muted=""
last_app=""
idle_until=$(( $(now_ms) + 1200 ))

while :; do
  target=$(read_state target); target=$(clamp "$target")
  muted=$(read_state muted); muted="${muted:-0}"

  if [ "$cur" -eq "$target" ] && [ "$muted" == "$last_muted" ] && [ "$app" == "$last_app" ]; then
    if [ "$(now_ms)" -ge "$idle_until" ]; then
      break
    fi
    sleep 0.04
    continue
  fi

  if [ "$target" -gt "$cur" ]; then
    step=$(( (target - cur) * 3 / 10 + 1 ))
    cur=$(( cur + step > target ? target : cur + step ))
  elif [ "$target" -lt "$cur" ]; then
    step=$(( (cur - target) * 3 / 10 + 1 ))
    cur=$(( cur - step < target ? target : cur - step ))
  fi

  echo "$cur" > "$DIR/${app}-current"
  send_frame "$app" "$cur" "$muted"
  last_muted="$muted"
  last_app="$app"
  idle_until=$(( $(now_ms) + 1200 ))
  sleep 0.015
done
