#!/bin/bash

DD=/usr/bin/ddcutil
BUS=$($DD detect 2>/dev/null | grep -B1 "Display" | head -1 | grep -oP 'i2c-\d+' | tr -dc '0-9')
[ -z "$BUS" ] && BUS=1

case "${1:-}" in
    get)
        $DD --bus "$BUS" getvcp 10 2>/dev/null | grep -oP 'current value =\s*\K\d+'
        ;;
    set)
        $DD --bus "$BUS" setvcp 10 "$2" 2>/dev/null
        ;;
    up)
        VAL=$($DD --bus "$BUS" getvcp 10 2>/dev/null | grep -oP 'current value =\s*\K\d+')
        [ -z "$VAL" ] && VAL=0
        NEW=$((VAL + ${2:-5}))
        [ "$NEW" -gt 100 ] && NEW=100
        $DD --bus "$BUS" setvcp 10 "$NEW" 2>/dev/null
        ;;
    down)
        VAL=$($DD --bus "$BUS" getvcp 10 2>/dev/null | grep -oP 'current value =\s*\K\d+')
        [ -z "$VAL" ] && VAL=0
        NEW=$((VAL - ${2:-5}))
        [ "$NEW" -lt 0 ] && NEW=0
        $DD --bus "$BUS" setvcp 10 "$NEW" 2>/dev/null
        ;;
    display)
        VAL=$($DD --bus "$BUS" getvcp 10 2>/dev/null | grep -oP 'current value =\s*\K\d+')
        if [ "$VAL" -le 25 ]; then ICON="󰃞"
        elif [ "$VAL" -le 50 ]; then ICON="󰃝"
        elif [ "$VAL" -le 75 ]; then ICON="󰃟"
        else ICON="󰃠"
        fi
        printf '{"text":"%s","class":""}' "$ICON"
        ;;
esac
