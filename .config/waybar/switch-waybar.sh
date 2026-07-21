#!/bin/bash

DIR="${0%/*}"
STATE_FILE="$DIR/.current"

# auto-detect waybar configs
CONFIGS=()
for f in "$DIR"/config-*.jsonc; do
    [ -f "$f" ] || continue
    name=$(basename "$f" | sed 's/^config-//; s/\.jsonc$//')
    CONFIGS+=("$name")
done

if [[ ${#CONFIGS[@]} -eq 0 ]]; then
    echo "No configs found"
    exit 1
fi

current=$(cat "$STATE_FILE" 2>/dev/null)

# if current doesn't exist in list, start from first
found=0
for c in "${CONFIGS[@]}"; do
    [[ "$c" == "$current" ]] && found=1 && break
done
[[ $found -eq 0 ]] && current="${CONFIGS[0]}"

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

echo "Switching to: $(cat "$STATE_FILE")"
exec "$DIR/launch.sh"
