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

# No waybar binary at all -> the bar can never appear. Write a diagnostic file
# instead of failing silently (waybar ships from the AUR waybar-cava-git build).
if [[ "$WB" != /* ]] && ! command -v waybar >/dev/null 2>&1; then
    {
        echo "waybar could NOT start: no waybar binary found."
        if [[ -n "${XDG_CACHE_HOME:-$HOME/.cache}/scrow" ]]; then
            echo "Likely cause: the AUR waybar-cava-git build failed during SCROW setup."
            echo "Check: ${XDG_CACHE_HOME:-$HOME/.cache}/scrow/aur-install.log"
            echo "Check: ${XDG_CACHE_HOME:-$HOME/.cache}/scrow/aur-install-failed.txt"
        fi
    } > "$LOG_DIR/diagnose.txt"
    exit 1
fi

pkill waybar 2>/dev/null
sleep 0.3

config=$(cat "$STATE_FILE" 2>/dev/null)

# auto-detect: if config not set or doesn't exist, use the project default
# (scrowland) — same priority order as switch-waybar.sh — so a fresh install
# mirrors the reference bar (workspaces click-to-switch etc.) instead of the
# alphabetically-first preset.
if [[ -z "$config" || ! -f "$DIR/config-${config}.jsonc" ]]; then
    config=""
    for cand in scrowland cxorz athena; do
        if [[ -f "$DIR/config-$cand.jsonc" ]]; then
            config="$cand"
            break
        fi
    done
    if [[ -z "$config" ]]; then
        config=$(ls "$DIR"/config-*.jsonc 2>/dev/null | head -1 | sed 's#.*config-##; s/\.jsonc$//')
    fi
    [[ -n "$config" ]] && echo "$config" > "$STATE_FILE"
fi

CFG="$DIR/config-${config}.jsonc"
STYLE="$DIR/style-${config}.css"
if [[ -f "$CFG" ]]; then
    # Only pass -s if the matching style exists; a missing style (e.g. a config
    # without its css yet) would make waybar fail to start.
    if [[ -f "$STYLE" ]]; then
        setsid "$WB" -c "$CFG" -s "$STYLE" </dev/null >"$LOG_DIR/waybar.log" 2>&1 &
    else
        setsid "$WB" -c "$CFG" </dev/null >"$LOG_DIR/waybar.log" 2>&1 &
    fi
else
    setsid "$WB" </dev/null >"$LOG_DIR/waybar.log" 2>&1 &
fi

# When launched from a PTY (scrow menu), the parent bash is the session leader.
# If it exits before the new waybar detaches into its own session, the kernel
# SIGHUPs waybar's process group and it dies silently. Wait until waybar is up
# so it has left the dying session's group before this script returns.
started=0
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
    if pgrep -x waybar >/dev/null; then
        started=1
        break
    fi
    sleep 0.2
done

# If the bar still is not up, capture the reason into a diagnostic file so a
# headless VM (or a fresh session) leaves a trail instead of a silent missing bar.
if [[ "$started" -eq 0 ]]; then
    {
        echo "waybar did not stay running (checked at $(date '+%H:%M:%S'))"
        echo "binary       : $WB (executable: $([[ -x "$(command -v "$WB" 2>/dev/null)" ]] && echo yes || echo \"$WB\"))"
        echo "state (.current): $config"
        echo "config       : $CFG (exists: $([[ -f "$CFG" ]] && echo yes || echo no))"
        echo "style        : $STYLE (exists: $([[ -f "$STYLE" ]] && echo yes || echo no))"
        echo "-- waybar.log tail --"
        tail -25 "$LOG_DIR/waybar.log" 2>/dev/null || echo "(no log)"
    } > "$LOG_DIR/diagnose.txt"
fi
