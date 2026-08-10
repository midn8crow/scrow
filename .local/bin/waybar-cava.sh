#!/bin/bash
if ! pgrep -f "[w]aybar-cava.py" >/dev/null; then
  setsid nohup "$HOME/.local/bin/waybar-cava.py" >/dev/null 2>&1 </dev/null & disown
fi
cat /tmp/waybar-cava.last 2>/dev/null
