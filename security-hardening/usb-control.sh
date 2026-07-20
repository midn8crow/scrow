#!/bin/bash
# USB Control Script
# Run without sudo to toggle USB storage

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

case "$1" in
    block)
        echo "Blocking USB storage devices..."
        for dev in /sys/bus/usb/devices/*/authorized; do
            echo 0 > "$dev" 2>/dev/null
        done
        echo -e "${GREEN}[OK]${NC} USB storage blocked"
        ;;
    allow)
        echo "Allowing USB storage devices..."
        for dev in /sys/bus/usb/devices/*/authorized; do
            echo 1 > "$dev" 2>/dev/null
        done
        echo -e "${GREEN}[OK]${NC} USB storage allowed (will block again on reboot)"
        ;;
    status)
        echo "USB device authorization status:"
        for dev in /sys/bus/usb/devices/*/authorized; do
            device=$(dirname "$dev" | xargs basename)
            status=$(cat "$dev" 2>/dev/null || echo "N/A")
            if [ "$status" = "1" ]; then
                echo -e "  $device: ${RED}ALLOWED${NC}"
            else
                echo -e "  $device: ${GREEN}BLOCKED${NC}"
            fi
        done
        ;;
    *)
        echo "Usage: $0 {block|allow|status}"
        echo ""
        echo "  block  - Block all USB storage (default on boot)"
        echo "  allow  - Temporarily allow USB (re-blocks on reboot)"
        echo "  status - Show current USB device status"
        ;;
esac
