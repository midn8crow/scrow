#!/bin/bash

# One-time setup script for dotfiles
# Run with sudo: sudo ./setup.sh

RES=$(hyprctl monitors -j 2>/dev/null | python3 -c "
import sys, json
try:
    m = json.load(sys.stdin)[0]
    print(f\"{int(m['width'])}x{int(m['height'])}\")
except:
    print('1920x1080')
" 2>/dev/null)

[ -z "$RES" ] && RES="1920x1080"

echo "Detected resolution: $RES"

# Update GRUB resolution
sed -i "s/^GRUB_GFXMODE=.*/GRUB_GFXMODE=$RES/" /etc/default/grub
echo "Set GRUB_GFXMODE=$RES"

# Regenerate GRUB config
grub-mkconfig -o /boot/grub/grub.cfg
echo "GRUB config updated"

echo "Done! Reboot to see changes."
