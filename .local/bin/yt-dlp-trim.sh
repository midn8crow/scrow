#!/usr/bin/env bash
args=()
prev_is_o=0
for a in "$@"; do
  if [ "$prev_is_o" = "1" ]; then
    a="${a//%(title)s/%(title).120B}"
    prev_is_o=0
  elif [ "$a" = "-o" ] || [ "$a" = "--output" ]; then
    prev_is_o=1
  elif [[ "$a" == --output=* || "$a" == -o=* ]]; then
    a="${a//%(title)s/%(title).120B}"
  fi
  args+=("$a")
done
exec /usr/bin/yt-dlp "${args[@]}"
