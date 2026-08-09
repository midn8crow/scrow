#!/usr/bin/env bash

HISTORY=$(cliphist list 2>/dev/null || echo "")

ID_ARRAY=()
MENU_STRING=""

while IFS=$'\t' read -r id preview; do
    [[ -z "$id" ]] && continue
    ID_ARRAY+=("$id")
    MENU_STRING+="${preview}"$'\x1e'
done <<< "$HISTORY"

if [[ -z "$MENU_STRING" ]]; then
    notify-send -t 1500 "󰅆 Clipboard" "Clipboard history is empty."
    exit 0
fi

SELECTED_INDEX=$(echo -n "$MENU_STRING" | rofi -dmenu -i \
    -p "󰅆 Clipboard" \
    -mesg "<b>Alt+y</b>: Clear All  |  <b>Alt+x</b>: Delete Entry" \
    -sep '\x1e' \
    -format 'i' \
    -kb-custom-2 "Alt+y" \
    -kb-custom-3 "Alt+x" \
    -hover-select \
    -me-select-entry '' \
    -me-accept-entry 'MousePrimary' \
    -theme-str 'window {width: 35%;} listview {lines: 6; fixed-height: false;} element {padding: 10px 14px;} element-text {vertical-align: 0.5;}')

ROFI_EXIT=$?

case $ROFI_EXIT in
    0)
        if [[ "$SELECTED_INDEX" =~ ^[0-9]+$ ]]; then
            SELECTED_ID="${ID_ARRAY[$SELECTED_INDEX]}"
            tmp=$(mktemp)
            cliphist decode "$SELECTED_ID" > "$tmp"
            mime=$(file -b --mime-type "$tmp")
            if [[ "$mime" == image/* ]]; then
                wl-copy -t "$mime" < "$tmp"
            else
                wl-copy < "$tmp"
            fi
            rm -f "$tmp"
            notify-send -t 1500 "󰅆 Clipboard" "Copied to clipboard"
        fi
        ;;
    11)
        cliphist wipe
        notify-send -t 1500 "󰅆 Clipboard" "Clipboard history cleared"
        ;;
    12)
        if [[ "$SELECTED_INDEX" =~ ^[0-9]+$ ]]; then
            SELECTED_ID="${ID_ARRAY[$SELECTED_INDEX]}"
            printf '%s\n' "$SELECTED_ID" | cliphist delete
            notify-send -t 1500 "󰅆 Clipboard" "Entry removed"
        fi
        ;;
esac
