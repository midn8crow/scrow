#!/bin/bash
# Auto-rebuild hyprpm plugins after Hyprland package updates
for user_dir in /home/*/; do
    user=$(basename "$user_dir")
    if id "$user" &>/dev/null; then
        sudo -u "$user" hyprpm update 2>/dev/null || true
    fi
done
