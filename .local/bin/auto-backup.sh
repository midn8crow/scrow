#!/bin/bash
# =============================================================================
# auto-backup.sh - Create initial backup after setup
# =============================================================================
# This runs automatically after ORCHESTRA.sh to save the clean state
# =============================================================================

set -euo pipefail

BACKUP_DIR="$HOME/.config/backup/initial"

# Configs to backup
CONFIGS=(
    ".config/hypr"
    ".config/waybar"
    ".config/kitty"
    ".config/rofi"
    ".config/swaync"
    ".config/starship.toml"
    ".config/fastfetch"
    ".config/mpv"
    ".config/btop"
    ".config/cava"
    ".config/matugen"
    ".config/gtk-3.0"
    ".config/gtk-4.0"
    ".config/qt6ct"
    ".mozilla/firefox"
    ".config/VSCodium/User"
    ".zshrc"
    ".local/bin"
    "user_scripts"
)

echo "Creating initial backup..."

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Backup each config
for config in "${CONFIGS[@]}"; do
    src="$HOME/$config"
    dst="$BACKUP_DIR/$config"
    
    if [[ -e "$src" ]]; then
        mkdir -p "$(dirname "$dst")"
        cp -r "$src" "$dst"
        echo "  ✓ Backed up $(basename "$config")"
    fi
done

echo ""
echo "Initial backup saved to: $BACKUP_DIR"
echo "You can restore this anytime from: System Reset → Update from Backup"
