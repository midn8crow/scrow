#!/bin/bash

STATUS=$(warp-cli status 2>/dev/null | grep -oP 'Status update:\s*\K\S+')

if [[ "$STATUS" == "Connected" ]]; then
    TOGGLE_LABEL="Secure Tunnel: ON (tap to disconnect)"
else
    TOGGLE_LABEL="Secure Tunnel: OFF (tap to connect)"
fi

CHOICE=$(printf "$TOGGLE_LABEL\nCheck IP" | rofi -dmenu -p "Secure Tunnel" -theme-str 'configuration { show-icons: false; }')

[ -z "$CHOICE" ] && exit 0

if [[ "$CHOICE" == *"ON"* ]]; then
    notify-send "Secure Tunnel" "Disconnecting..." -i network-vpn-disconnected
    warp-cli disconnect 2>/dev/null
    notify-send "Secure Tunnel" "WARP Disconnected" -i network-vpn-disconnected
elif [[ "$CHOICE" == *"OFF"* ]]; then
    notify-send "Secure Tunnel" "Connecting..." -i network-vpn
    warp-cli connect 2>/dev/null
    notify-send "Secure Tunnel" "WARP Connected" -i network-vpn
elif [[ "$CHOICE" == *"Check"* ]]; then
    ip=$(curl -s --max-time 5 https://ifconfig.me)
    if [[ -n "$ip" ]]; then
        notify-send "Your Public IP" "$ip" -i network-workgroup
    else
        notify-send "Error" "Could not fetch IP" -i dialog-error
    fi
fi
