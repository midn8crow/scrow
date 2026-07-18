#!/bin/bash

expression=""
history=""

buttons=(
    "sin"  "7"    "8"    "9"    "÷"
    "cos"  "4"    "5"    "6"    "×"
    "tan"  "1"    "2"    "3"    "−"
    "π"    "C"    "0"    "."    "+"
    "√"    "("    ")"    "±"    "="
)

calc_display() {
    local hist="$history"
    local expr="$expression"
    [ -z "$hist" ] && hist="<span color='#6c7086' font='JetBrainsMono Nerd Font 11'>History</span>"
    [ -z "$expr" ] && expr="0"
    echo "${hist}
<span color='#cdd6f4' font='JetBrainsMono Nerd Font Bold 16'>${expr}</span>"
}

append_history() {
    history="${history}<span color='#6c7086' font='JetBrainsMono Nerd Font 11'>${1}</span>
"
    history=$(echo -e "$history" | tail -2)
}

while true; do
    display_msg="$(calc_display)"

    choice=$(printf '%s\n' "${buttons[@]}" | rofi -dmenu \
        -config ~/.config/rofi/calculator.rasi \
        -mesg "$display_msg" \
        -p " Calc" \
        -selected-row 0 \
        -no-custom)

    [ $? -ne 0 ] && exit 0

    case "$choice" in
        "C")
            expression=""
            history=""
            ;;
        "π")
            expression="${expression}pi"
            ;;
        "sin")
            expression="${expression}sin("
            ;;
        "cos")
            expression="${expression}cos("
            ;;
        "tan")
            expression="${expression}tan("
            ;;
        "√")
            expression="${expression}sqrt("
            ;;
        "±")
            if [[ "$expression" == -* ]]; then
                expression="${expression#-}"
            else
                expression="-${expression}"
            fi
            ;;
        "("|")")
            expression="${expression}${choice}"
            ;;
        "=")
            result=$(qalc -t "$expression" 2>/dev/null)
            if [ -n "$result" ] && [ "$result" != "Error" ]; then
                append_history "${expression} = ${result}"
                echo -n "$result" | wl-copy
                notify-send -a "Calculator" -i calculator "${expression} = ${result}" -t 2000
                expression="$result"
            else
                append_history "${expression} = Error"
                expression=""
            fi
            ;;
        "÷")
            expression="${expression}/"
            ;;
        "×")
            expression="${expression}*"
            ;;
        "−")
            expression="${expression}-"
            ;;
        "+")
            expression="${expression}+"
            ;;
        "."|[0-9])
            expression="${expression}${choice}"
            ;;
    esac
done
