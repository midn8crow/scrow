#!/bin/bash
while true; do
    LED_DIR=$(find /sys/class/leds/ -maxdepth 1 -name "*scrolllock" 2>/dev/null | head -1)
    if [ -n "$LED_DIR" ] && [ -f "$LED_DIR/brightness" ]; then
        echo 1 > "$LED_DIR/brightness" 2>/dev/null
    fi
    sleep 0.005
done
