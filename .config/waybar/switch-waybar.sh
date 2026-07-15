#!/bin/bash

DIR="${0%/*}"
STATE_FILE="$DIR/.current"

# Auto-detect waybar configs
CONFIGS=()
for f in "$DIR"/config-*.jsonc; do
    [ -f "$f" ] || continue
    name=$(basename "$f" | sed 's/^config-//; s/\.jsonc$//')
    CONFIGS+=("$name")
done

current=$(cat "$STATE_FILE" 2>/dev/null || echo "${CONFIGS[0]}")

case "$1" in
    prev)
        for i in "${!CONFIGS[@]}"; do
            if [[ "${CONFIGS[$i]}" == "$current" ]]; then
                prev=$(( (i - 1 + ${#CONFIGS[@]}) % ${#CONFIGS[@]} ))
                echo "${CONFIGS[$prev]}" > "$STATE_FILE"
                break
            fi
        done
        ;;
    next|*)
        for i in "${!CONFIGS[@]}"; do
            if [[ "${CONFIGS[$i]}" == "$current" ]]; then
                next=$(( (i + 1) % ${#CONFIGS[@]} ))
                echo "${CONFIGS[$next]}" > "$STATE_FILE"
                break
            fi
        done
        ;;
esac

exec "$DIR/launch.sh"
