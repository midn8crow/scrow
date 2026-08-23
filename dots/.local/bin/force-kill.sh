#!/bin/bash
pid=$(hyprctl activewindow -j | jq -r '.pid')
if [ -n "$pid" ] && [ "$pid" != "null" ] && [ "$pid" -gt 0 ]; then
    kill -9 "$pid" 2>/dev/null
fi
