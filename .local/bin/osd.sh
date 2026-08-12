#!/bin/bash
# osd.sh - OSD-style volume/brightness slider (mako + animated fill)
# usage: osd.sh <app> <value> [muted]
# Persists the desired state and lets osd-animator.sh glide the fill smoothly.

app="$1"
value="$2"
muted="${3:-0}"

value=$((10#${value:-0}))
[ "$value" -lt 0 ]  && value=0
[ "$value" -gt 100 ] && value=100

DIR="${XDG_RUNTIME_DIR:-/tmp}/osd"
mkdir -p "$DIR"
echo "$muted" > "$DIR/muted"
echo "$app" > "$DIR/app"
echo "$value" > "$DIR/target"

if ! pgrep -f "osd-animator.sh" >/dev/null 2>&1; then
  nohup "$HOME/.local/bin/osd-animator.sh" >/dev/null 2>&1 &
fi
