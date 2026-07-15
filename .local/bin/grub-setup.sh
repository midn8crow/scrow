#!/bin/bash
# =============================================================================
# grub-setup.sh - Install Minecraft GRUB Theme
# =============================================================================

set -euo pipefail

THEME_DIR="/boot/grub/themes/minegrub"
DOTFILES_GRUB="$HOME/dotfiles/boot/grub"

echo "Installing Minecraft GRUB theme..."

# Copy theme files
if [[ -d "$DOTFILES_GRUB/themes/minegrub" ]]; then
    sudo cp -r "$DOTFILES_GRUB/themes/minegrub" /boot/grub/themes/
    echo "✓ Theme files copied"
else
    echo "✗ Theme files not found in dotfiles"
    exit 1
fi

# Update GRUB config
if ! grep -q "minegrub" /etc/default/grub; then
    sudo sed -i 's|#GRUB_THEME=|GRUB_THEME=/boot/grub/themes/minegrub/theme.txt|' /etc/default/grub
    echo "✓ GRUB config updated"
else
    echo "✓ GRUB config already set"
fi

# Regenerate grub config
sudo grub-mkconfig -o /boot/grub/grub.cfg
echo "✓ GRUB config regenerated"

echo ""
echo "Minecraft GRUB theme installed!"
echo "Restart to see it."
