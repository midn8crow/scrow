#!/bin/bash

expression=""
last_eq=""

buttons=(
    "C"    "⌫"    "()"   "÷"
    "7"    "8"    "9"    "×"
    "4"    "5"    "6"    "−"
    "1"    "2"    "3"    "+"
    "±"    "0"    "."    "="
)

calc_display() {
    if [ -n "$last_eq" ]; then
        echo "<span color='#a6e3a1' font='JetBrainsMono Nerd Font Bold 15'>${last_eq}</span>"
    elif [ -n "$expression" ]; then
        echo "<span color='#cdd6f4' font='JetBrainsMono Nerd Font Bold 18'>${expression}</span>"
    else
        echo "<span color='#6c7086' font='JetBrainsMono Nerd Font 14'>0</span>"
    fi
}

while true; do
    display_msg="$(calc_display)"

    choice=$(printf '%s\n' "${buttons[@]}" | rofi -dmenu \
        -config ~/.config/rofi/calculator.rasi \
        -mesg "$display_msg" \
        -selected-row 0 \
        -no-custom)

    [ $? -ne 0 ] && exit 0

    case "$choice" in
        "C")
            expression=""
            last_eq=""
            ;;
        "⌫")
            expression="${expression%?}"
            last_eq=""
            ;;
        "()")
            if [[ "$expression" == *"("* ]]; then
                expression="${expression})"
            else
                expression="${expression}("
            fi
            last_eq=""
            ;;
        "=")
            result=$(qalc -t "$expression" 2>/dev/null)
            if [ -n "$result" ] && [ "$result" != "Error" ]; then
                last_eq="${expression} = ${result}"
                echo -n "$result" | wl-copy
                notify-send -a "Calculator" -i calculator "$last_eq" -t 2000
                expression="$result"
            else
                last_eq="${expression} = Error"
                expression=""
            fi
            ;;
        "±")
            if [[ "$expression" == -* ]]; then
                expression="${expression#-}"
            else
                expression="-${expression}"
            fi
            last_eq=""
            ;;
        "÷")
            expression="${expression}/"
            last_eq=""
            ;;
        "×")
            expression="${expression}*"
            last_eq=""
            ;;
        "−")
            expression="${expression}-"
            last_eq=""
            ;;
        "+")
            expression="${expression}+"
            last_eq=""
            ;;
        "."|"()"|[0-9])
            expression="${expression}${choice}"
            last_eq=""
            ;;
    esac
done
