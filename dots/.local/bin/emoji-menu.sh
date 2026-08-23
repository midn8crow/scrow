#!/usr/bin/env bash

# emoji-menu.sh - rofi script mode emoji picker.
# Mode is picked from the script name (symlinks into this file):
#   emoji-recents.sh   -> "Recently Used" (history)
#   emoji-all.sh       -> "All Emojis"    (everything, minus recents)
#   emoji-people.sh    -> "People"        (People & Body)
#   emoji-organs.sh    -> "Organs"        (People & Body, hand* + body-parts subgroups)
#   emoji-animals.sh   -> "Animals"       (Animals & Nature)
#   emoji-food.sh      -> "Food"          (Food & Drink)
#   emoji-symbols.sh   -> "Symbols"
# Selecting an emoji records it in the history and types it into the
# focused window. Lists are generated with a single awk pass so that rofi's
# startup (which inits every mode) stays fast.

set -euo pipefail

DATA_FILE="${EMOJI_DATA_FILE:-/usr/share/rofi-emoji/all_emojis.txt}"
HISTORY_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/emoji-history"
HISTORY_MAX=30

MODE=all
PROMPT="All Emojis"
GROUP=""
case "$(basename "$0")" in
    emoji-recents.sh) MODE=recents PROMPT="Recently Used" ;;
    emoji-all.sh)     MODE=all     PROMPT="All Emojis" ;;
    emoji-people.sh)  MODE=people  PROMPT="People"  GROUP="People & Body" ;;
    emoji-organs.sh)  MODE=organs  PROMPT="Organs"  GROUP="People & Body" ;;
    emoji-animals.sh) MODE=animals PROMPT="Animals" GROUP="Animals & Nature" ;;
    emoji-food.sh)    MODE=food    PROMPT="Food"    GROUP="Food & Drink" ;;
    emoji-symbols.sh) MODE=symbols PROMPT="Symbols" GROUP="Symbols" ;;
esac

record_use() {
    local emoji="$1" e
    local tmp
    tmp="$(mktemp "${HISTORY_FILE}.XXXXXX")"
    printf '%s\n' "$emoji" > "$tmp"
    if [[ -f "$HISTORY_FILE" ]]; then
        while IFS= read -r e; do
            [[ -n "$e" && "$e" != "$emoji" ]] || continue
            printf '%s\n' "$e" >> "$tmp"
        done < "$HISTORY_FILE"
    fi
    head -n "$HISTORY_MAX" "$tmp" > "$HISTORY_FILE"
    rm -f "$tmp"
}

forget_use() {
    local emoji="$1" e
    [[ -f "$HISTORY_FILE" ]] || return 0
    local tmp
    tmp="$(mktemp "${HISTORY_FILE}.XXXXXX")"
    while IFS= read -r e; do
        [[ -n "$e" && "$e" != "$emoji" ]] || continue
        printf '%s\n' "$e" >> "$tmp"
    done < "$HISTORY_FILE"
    mv "$tmp" "$HISTORY_FILE"
}

print_list() {
    local hist="$HISTORY_FILE"
    [[ -f "$hist" ]] || hist=/dev/null

    printf '\0no-custom\x1ftrue\n'
    printf '\0prompt\x1f%s\n' "$PROMPT"

    case "$MODE" in
        recents)
            awk -F'\t' '
                NR==FNR { meta[$1] = $4 " " $5; next }
                $1 in meta { printf "%s\0meta\x1f%s\x1finfo\x1f%s\n", $1, meta[$1], $1 }
            ' "$DATA_FILE" "$hist"
            ;;
        all)
            awk -F'\t' '
                ARGIND==1 { skip[$1] = 1; next }
                ARGIND==2 && $1 != "" && !($1 in skip) {
                    printf "%s\0meta\x1f%s %s\x1finfo\x1f%s\n", $1, $4, $5, $1
                }
            ' "$hist" "$DATA_FILE"
            ;;
        people)
            awk -F'\t' '
                $2 == "People & Body" && $3 !~ /^hand/ && $3 != "body-parts" && $1 != "" {
                    printf "%s\0meta\x1f%s %s\x1finfo\x1f%s\n", $1, $4, $5, $1
                }
            ' "$DATA_FILE"
            ;;
        organs)
            awk -F'\t' '
                $2 == "People & Body" && ($3 ~ /^hand/ || $3 == "body-parts") && $1 != "" {
                    printf "%s\0meta\x1f%s %s\x1finfo\x1f%s\n", $1, $4, $5, $1
                }
            ' "$DATA_FILE"
            ;;
        *)
            awk -F'\t' -v g="$GROUP" '
                $2 == g && $1 != "" {
                    printf "%s\0meta\x1f%s %s\x1finfo\x1f%s\n", $1, $4, $5, $1
                }
            ' "$DATA_FILE"
            ;;
    esac
}

retv="${ROFI_RETV:-0}"

if (( retv == 1 || retv == 2 )); then
    emoji="${ROFI_INFO:-${1:-}}"
    [[ -n "$emoji" ]] || exit 0

    record_use "$emoji"

    rofi_pid="${ROFI_OUTSIDE:-}"
    (
        while [[ -n "$rofi_pid" ]] && kill -0 "$rofi_pid" 2>/dev/null; do
            sleep 0.02
        done
        sleep 0.2
        exec wtype "$emoji"
    ) >/dev/null 2>&1 &
    disown || true
    exit 0
fi

if (( retv == 3 )); then
    [[ -n "${ROFI_INFO:-${1:-}}" ]] && forget_use "${ROFI_INFO:-$1}"
fi

print_list
