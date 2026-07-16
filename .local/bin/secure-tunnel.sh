#!/bin/bash

SOCKS_PORT=9050
STATE_FILE="/tmp/.secure-tunnel-state"
PROXY_ENV_FILE="/tmp/.secure-tunnel-proxy-env"

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
    sudo systemctl start tor
    sleep 2
    if is_tor_running; then
        cat > "$PROXY_ENV_FILE" << EOF
export http_proxy="socks5h://127.0.0.1:$SOCKS_PORT"
export https_proxy="socks5h://127.0.0.1:$SOCKS_PORT"
export all_proxy="socks5h://127.0.0.1:$SOCKS_PORT"
export no_proxy="localhost,127.0.0.1,::1"
EOF
        echo "1" > "$STATE_FILE"
        notify "Secure Tunnel (TOR)" "Enabled - Traffic routed through Tor"
    else
        notify "Secure Tunnel" "Failed to start Tor"
    fi
}

stop_tor() {
    sudo systemctl stop tor
    rm -f "$PROXY_ENV_FILE"
    rm -f "$STATE_FILE"
    notify "Secure Tunnel (TOR)" "Disabled - Direct connection"
}

check_ip() {
    if is_tor_running; then
        IP=$(curl -s --socks5-hostname 127.0.0.1:$SOCKS_PORT https://api.ipify.org 2>/dev/null)
        if [ -n "$IP" ]; then
            notify "Tor IP" "Your Tor exit IP: $IP"
        else
            notify "Tor IP" "Could not fetch IP. Check connection."
        fi
    else
        IP=$(curl -s https://api.ipify.org 2>/dev/null)
        notify "Direct IP" "Your direct IP: $IP"
    fi
}

show_menu() {
    STATUS=$(get_status)

    if [ "$STATUS" = "ON" ]; then
        OPTIONS="Secure Tunnel (TOR)  [ON]\nStop Tunnel\nCheck IP"
    else
        OPTIONS="Secure Tunnel (TOR)  [OFF]\nStart Tunnel\nCheck IP"
    fi

    CHOICE=$(printf "$OPTIONS" | rofi -dmenu -p "Secure Tunnel" -theme-str 'configuration { show-icons: false; }')

    [ -z "$CHOICE" ] && exit 0

    case "$CHOICE" in
        *Start\ Tunnel)
            start_tor
            ;;
        *Stop\ Tunnel)
            stop_tor
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
