#!/bin/bash

SOCKS_PORT=9050
STATE_FILE="/tmp/.secure-tunnel-state"

is_tor_running() {
    systemctl is-active --quiet tor 2>/dev/null
}

get_status() {
    if is_tor_running; then
        echo "ON"
    else
        echo "OFF"
    fi
}

notify() {
    notify-send -u normal -t 3000 "$1" "$2"
}

start_tor() {
    notify "Secure Tunnel" "Connecting ..."
    sudo systemctl start tor
    sleep 2
    if is_tor_running; then
        echo "1" > "$STATE_FILE"
        notify "Secure Tunnel (TOR)" "Enabled - Configure browser SOCKS5 proxy 127.0.0.1:9050"
    else
        notify "Secure Tunnel" "Failed to start Tor"
    fi
}

stop_tor() {
    notify -t 500 "Secure Tunnel" "Disconnecting ..."
    sudo systemctl stop tor
    rm -f "$STATE_FILE"
    notify "Secure Tunnel (TOR)" "Disabled - Direct connection"
}

check_ip() {
    notify "IP Check" "Checking..."
    if is_tor_running; then
        IP=$(curl -s --max-time 5 --socks5-hostname 127.0.0.1:$SOCKS_PORT https://api.ipify.org 2>/dev/null)
        if [ -n "$IP" ]; then
            notify "Tor IP" "Your Tor exit IP: $IP"
        else
            notify "Tor IP" "Could not fetch IP. Check connection."
        fi
    else
        IP=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null)
        if [ -n "$IP" ]; then
            notify "Direct IP" "Your direct IP: $IP"
        else
            notify "Direct IP" "Could not fetch IP."
        fi
    fi
}

show_menu() {
    STATUS=$(get_status)

    if [ "$STATUS" = "ON" ]; then
        OPTIONS="Secure Tunnel (TOR)  [ON]\nCheck IP"
    else
        OPTIONS="Secure Tunnel (TOR)  [OFF]\nCheck IP"
    fi

    CHOICE=$(printf "$OPTIONS" | rofi -dmenu -p "Secure Tunnel" -theme-str 'configuration { show-icons: false; }')

    [ -z "$CHOICE" ] && exit 0

    case "$CHOICE" in
        *Secure\ Tunnel*)
            if is_tor_running; then
                stop_tor
            else
                start_tor
            fi
            ;;
        *Check\ IP)
            check_ip
            ;;
    esac
}

case "${1:-menu}" in
    start)
        start_tor
        ;;
    stop)
        stop_tor
        ;;
    toggle)
        if is_tor_running; then
            stop_tor
        else
            start_tor
        fi
        ;;
    status)
        get_status
        ;;
    *)
        show_menu
        ;;
esac
