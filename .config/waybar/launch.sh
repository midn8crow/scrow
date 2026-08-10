#!/bin/bash

DIR="${0%/*}"
STATE_FILE="$DIR/.current"
LOG_DIR="${TMPDIR:-/tmp}/waybar"
mkdir -p "$LOG_DIR"

# prefer the user-built waybar (right-click toggle) over the system one
if [[ -x "$HOME/.local/bin/waybar" ]]; then
    WB="$HOME/.local/bin/waybar"
else
    WB="waybar"
fi

pkill waybar 2>/dev/null
sleep 0.3

config=$(cat "$STATE_FILE" 2>/dev/null)

# auto-detect: if config not set or doesn't exist, use first available
if [[ -z "$config" || ! -f "$DIR/config-${config}.jsonc" ]]; then
    first=$(ls "$DIR"/config-*.jsonc 2>/dev/null | head -1)
    if [[ -n "$first" ]]; then
        config=$(basename "$first" | sed 's/^config-//; s/\.jsonc$//')
        echo "$config" > "$STATE_FILE"
    fi
fi

CFG="$DIR/config-${config}.jsonc"
STYLE="$DIR/style-${config}.css"
if [[ -f "$CFG" ]]; then
    setsid "$WB" -c "$CFG" -s "$STYLE" </dev/null >"$LOG_DIR/waybar.log" 2>&1 &
else
    setsid "$WB" </dev/null >"$LOG_DIR/waybar.log" 2>&1 &
fi

# When launched from a PTY (scrow menu), the parent bash is the session leader.
# If it exits before the new waybar detaches into its own session, the kernel
# SIGHUPs waybar's process group and it dies silently. Wait until waybar is up
# so it has left the dying session's group before this script returns.
for _ in 1 2 3 4 5 6 7 8 9 10; do
    pgrep -x waybar >/dev/null && break
    sleep 0.1
done
