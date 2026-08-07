#!/usr/bin/env bash
# Zoom around the mouse cursor on Hyprland.
# usage:
#   zoom.sh reset            -> back to 1x
#   zoom.sh <+delta|-delta>  -> change zoom level, e.g. zoom.sh +0.25

MIN=1
MAX=8

get_zoom() {
    local v
    v=$(hyprctl -j getoption cursor:zoom_factor 2>/dev/null | sed -n 's/.*"float": *\([0-9.]*\).*/\1/p')
    [[ -n "$v" ]] && echo "$v" || echo "$MIN"
}

set_zoom() {
    hyprctl eval "hl.config({ cursor = { zoom_factor = $1 } })" >/dev/null 2>&1
}

change_zoom() {
    local cur new
    cur=$(get_zoom)
    new=$(awk -v c="$cur" -v d="$1" -v mn="$MIN" -v mx="$MAX" \
        'BEGIN { v = c + d; if (v < mn) v = mn; if (v > mx) v = mx; printf "%.4f", v }')
    set_zoom "$new"
}

main() {
    case "${1:-}" in
        reset)
            set_zoom "$MIN"
            ;;
        +*|-*)
            change_zoom "$1"
            ;;
    esac
}

main "$@"
