#!/bin/bash

SOCKS_PORT=9050
STATE_FILE="/tmp/.secure-tunnel-state"
PID_FILE="/tmp/.tor.pid"
TORRC_FILE="/tmp/.torrc-secure-tunnel"
TOR_DATA="/tmp/.tor-data-secure"

# Create torrc config
setup_torrc() {
    mkdir -p "$TOR_DATA"
    cat > "$TORRC_FILE" << EOF
SocksPort $SOCKS_PORT
DataDirectory $TOR_DATA
Log notice file /tmp/tor-secure.log
EOF
}

is_tor_running() {
    # Check by PID file
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            return 0
        fi
    fi
    # Fallback: check port
    ss -tlnp 2>/dev/null | grep -q ":${SOCKS_PORT} " && return 0
    return 1
}

get_pid() {
    if [ -f "$PID_FILE" ]; then
        cat "$PID_FILE"
    fi
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
    if is_tor_running; then
        notify "Secure Tunnel" "Already running"
        return 0
    fi

    notify "Secure Tunnel" "Connecting ..."
    setup_torrc

    # Start tor as background process
    nohup tor -f "$TORRC_FILE" > /dev/null 2>&1 &
    local pid=$!
    echo "$pid" > "$PID_FILE"

    # Wait for it to bootstrap (max 30 seconds)
    local waited=0
    while [ $waited -lt 30 ]; do
        if ss -tlnp 2>/dev/null | grep -q ":${SOCKS_PORT} "; then
            # Verify it actually works
            sleep 2
            if curl -s --max-time 5 --socks5 127.0.0.1:$SOCKS_PORT https://check.torproject.org/api/ip 2>/dev/null | grep -q '"IsTor":true'; then
                echo "1" > "$STATE_FILE"
                notify "Secure Tunnel (TOR)" "Enabled"
                return 0
            fi
        fi
        # Check if process died
        if ! kill -0 "$pid" 2>/dev/null; then
            rm -f "$PID_FILE"
            notify "Secure Tunnel" "Failed to start Tor"
            return 1
        fi
        sleep 1
        waited=$((waited + 1))
    done

    # Timeout - kill it
    kill "$pid" 2>/dev/null
    rm -f "$PID_FILE"
    notify "Secure Tunnel" "Failed to start Tor (timeout)"
    return 1
}

stop_tor() {
    if ! is_tor_running; then
        notify "Secure Tunnel" "Not running"
        rm -f "$STATE_FILE" "$PID_FILE"
        return 0
    fi

    notify "Secure Tunnel" "Disconnecting ..."
    local pid=$(get_pid)
    if [ -n "$pid" ]; then
        kill "$pid" 2>/dev/null
        wait "$pid" 2>/dev/null
    fi
    # Fallback: kill by port
    fuser -k "$SOCKS_PORT/tcp" 2>/dev/null
    rm -f "$STATE_FILE" "$PID_FILE"
    notify "Secure Tunnel (TOR)" "Disabled"
}

check_ip() {
    notify "IP Check" "Checking..."
    if is_tor_running; then
        IP=$(curl -s --max-time 10 --socks5-hostname 127.0.0.1:$SOCKS_PORT https://api.ipify.org 2>/dev/null)
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

export_to_opencode() {
    # Set HTTPS_PROXY for opencode to route through Tor
    if is_tor_running; then
        export HTTPS_PROXY="socks5h://127.0.0.1:$SOCKS_PORT"
        notify "OpenCode" "HTTPS_PROXY set to Tor"
    else
        unset HTTPS_PROXY
        notify "OpenCode" "HTTPS_PROXY cleared"
    fi
}

show_menu() {
    STATUS=$(get_status)

    if [ "$STATUS" = "ON" ]; then
        OPTIONS="Secure Tunnel (TOR)  [ON]\nCheck IP\nExport to OpenCode"
    else
        OPTIONS="Secure Tunnel (TOR)  [OFF]\nCheck IP\nExport to OpenCode"
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
        *Export\ to\ OpenCode)
            export_to_opencode
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
