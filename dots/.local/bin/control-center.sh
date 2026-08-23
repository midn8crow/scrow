#!/bin/bash

# Control Center - WiFi & Bluetooth manager via Rofi
# Works with nmcli and bluetoothctl

ROFI_THEME="$HOME/.config/rofi/control-center.rasi"

get_wifi_status() {
    nmcli radio wifi 2>/dev/null
}

get_wifi_icon() {
    local status
    status=$(get_wifi_status)
    if [[ "$status" == "enabled" ]]; then
        local in_use
        in_use=$(nmcli -t -f IN-USE device wifi list 2>/dev/null | grep -c "^:")
        if [[ "$in_use" -gt 0 ]]; then
            echo "󰤨"
        else
            echo "󰤭"
        fi
    else
        echo "󰤭"
    fi
}

get_bt_status() {
    if ! command -v bluetoothctl &>/dev/null; then
        echo "unavailable"
        return
    fi
    if systemctl is-active bluetooth &>/dev/null; then
        echo "enabled"
    else
        echo "disabled"
    fi
}

get_bt_icon() {
    local status
    status=$(get_bt_status)
    if [[ "$status" == "enabled" ]]; then
        echo "󰂯"
    elif [[ "$status" == "unavailable" ]]; then
        echo "󰂜"
    else
        echo "󰂲"
    fi
}

show_wifi_networks() {
    local wifi_status
    wifi_status=$(get_wifi_status)

    if [[ "$wifi_status" != "enabled" ]]; then
        notify-send "WiFi" "WiFi is disabled"
        return
    fi

    nmcli device wifi rescan 2>/dev/null
    sleep 1

    local networks
    networks=$(nmcli -t -f SSID,SIGNAL,SECURITY,IN-USE device wifi list 2>/dev/null | awk -F: '
    {
        if ($1 == "") next
        ssid=$1; signal=$2; security=$3; inuse=$4
        if (inuse == "*") {
            printf "󰤨  %s  (%s%%) %s [connected]\n", ssid, signal, security
        } else {
            if (signal+0 >= 75) icon="󰤨"
            else if (signal+0 >= 50) icon="󰤥"
            else if (signal+0 >= 25) icon="󰤢"
            else icon="󰤟"
            printf "%s  %s  (%s%%) %s\n", icon, ssid, signal, security
        }
    }' | sort -t'[' -k2 -r)

    if [[ -z "$networks" ]]; then
        notify-send "WiFi" "No networks found"
        return
    fi

    local choice
    choice=$(echo "$networks" | rofi -dmenu -p "WiFi Networks" -theme "$ROFI_THEME" -theme-str 'listview { columns: 1; }')

    [[ -z "$choice" ]] && return

    local ssid
    ssid=$(echo "$choice" | sed 's/.*  \([^ ]*\)  .*/\1/' | sed 's/ \[connected\]//')

    if echo "$choice" | grep -q "\[connected\]"; then
        local action
        action=$(printf "Disconnect\nDetails" | rofi -dmenu -p "$ssid" -theme "$ROFI_THEME")
        [[ -z "$action" ]] && return
        case "$action" in
            *Disconnect) nmcli connection down "$ssid" 2>/dev/null && notify-send "WiFi" "Disconnected from $ssid" ;;
            *Details)
                local details
                details=$(nmcli -f SSID,SIGNAL,FREQ,BAND,RATE,SECURITY device wifi list 2>/dev/null | head -5)
                notify-send "WiFi Details" "$details"
                ;;
        esac
    else
        local security
        security=$(echo "$choice" | grep -oP '(WPA2|WPA3|WPA|WEP|OPEN)' | head -1)
        if [[ -n "$security" && "$security" != "OPEN" ]]; then
            local pass
            pass=$(echo "" | rofi -dmenu -p "Password for $ssid" -theme "$ROFI_THEME" -password)
            [[ -z "$pass" ]] && return
            nmcli device wifi connect "$ssid" password "$pass" 2>/dev/null
        else
            nmcli device wifi connect "$ssid" 2>/dev/null
        fi
        if [[ $? -eq 0 ]]; then
            notify-send "WiFi" "Connected to $ssid"
        else
            notify-send "WiFi" "Failed to connect to $ssid"
        fi
    fi
}

show_bluetooth_menu() {
    local bt_status
    bt_status=$(get_bt_status)

    if [[ "$bt_status" == "unavailable" ]]; then
        notify-send "Bluetooth" "Bluetooth not available on this system"
        return
    fi

    if [[ "$bt_status" == "disabled" ]]; then
        local action
        action=$(printf "Turn On" | rofi -dmenu -p "Bluetooth is Off" -theme "$ROFI_THEME")
        [[ -z "$action" ]] && return
        if [[ "$action" == "Turn On" ]]; then
            sudo systemctl start bluetooth 2>/dev/null
            sleep 1
            notify-send "Bluetooth" "Bluetooth enabled"
        fi
        return
    fi

    local options="󰂯  Turn Off
󰂯  Scan Devices
󰂀  Paired Devices"

    local choice
    choice=$(echo "$options" | rofi -dmenu -p "Bluetooth" -theme "$ROFI_THEME")
    [[ -z "$choice" ]] && return

    case "$choice" in
        *Turn\ Off)
            sudo systemctl stop bluetooth 2>/dev/null
            notify-send "Bluetooth" "Bluetooth disabled"
            ;;
        *Scan*)
            bluetoothctl --timeout 10 scan on &>/dev/null &
            sleep 3
            local devices
            devices=$(bluetoothctl devices 2>/dev/null | head -20 | awk '{
                name=""
                for(i=3;i<=NF;i++) name=name" "$i
                printf "%s %s\n", $2, name
            }')

            if [[ -z "$devices" ]]; then
                notify-send "Bluetooth" "No devices found nearby"
                return
            fi

            local dev_choice
            dev_choice=$(echo "$devices" | rofi -dmenu -p "Scan Results" -theme "$ROFI_THEME")
            [[ -z "$dev_choice" ]] && return

            local mac
            mac=$(echo "$dev_choice" | awk '{print $1}')
            local action
            action=$(printf "Pair & Connect\nConnect\nTrust\nRemove" | rofi -dmenu -p "$dev_choice" -theme "$ROFI_THEME")
            [[ -z "$action" ]] && return

            case "$action" in
                *Pair*) bluetoothctl pair "$mac" && bluetoothctl connect "$mac" ;;
                *Connect) bluetoothctl connect "$mac" ;;
                *Trust) bluetoothctl trust "$mac" ;;
                *Remove) bluetoothctl remove "$mac" ;;
            esac
            ;;
        *Paired*)
            local paired
            paired=$(bluetoothctl paired-devices 2>/dev/null | awk '{
                name=""
                for(i=3;i<=NF;i++) name=name" "$i
                printf "%s %s\n", $2, name
            }')

            if [[ -z "$paired" ]]; then
                notify-send "Bluetooth" "No paired devices"
                return
            fi

            local p_choice
            p_choice=$(echo "$paired" | rofi -dmenu -p "Paired Devices" -theme "$ROFI_THEME")
            [[ -z "$p_choice" ]] && return

            local p_mac
            p_mac=$(echo "$p_choice" | awk '{print $1}')
            local p_action
            p_action=$(printf "Connect\nDisconnect\nRemove" | rofi -dmenu -p "$p_choice" -theme "$ROFI_THEME")
            [[ -z "$p_action" ]] && return

            case "$p_action" in
                *Connect) bluetoothctl connect "$p_mac" ;;
                *Disconnect) bluetoothctl disconnect "$p_mac" ;;
                *Remove) bluetoothctl remove "$p_mac" ;;
            esac
            ;;
    esac
}

# --- Main Menu ---
wifi_icon=$(get_wifi_icon)
bt_icon=$(get_bt_icon)

main_options="${wifi_icon}  WiFi
${bt_icon}  Bluetooth"

choice=$(echo "$main_options" | rofi -dmenu -p "Control Center" -theme "$ROFI_THEME")
[[ -z "$choice" ]] && exit 0

case "$choice" in
    *WiFi)      show_wifi_networks ;;
    *Bluetooth) show_bluetooth_menu ;;
esac
