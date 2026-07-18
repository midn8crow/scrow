#!/bin/bash
# =============================================================================
# system-reset.sh - System Reset Menu
# =============================================================================
# Options: Update from Backup or Fetch from GitHub
# =============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Paths
DOTFILES_DIR="$HOME/dotfiles"
BACKUP_DIR="$HOME/.config/backup/initial"
GITHUB_REPO="https://github.com/midnight-crow-69/scrow-setup.git"

# Configs to restore
CONFIGS=(
    ".config/hypr"
    ".config/waybar"
    ".config/kitty"
    ".config/rofi"
    ".config/mako"
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

# =============================================================================
# FUNCTIONS
# =============================================================================

print_step() {
    echo -e "${CYAN}→ $1${NC}"
}

print_ok() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_err() {
    echo -e "${RED}✗ $1${NC}"
}

print_warn() {
    echo -e "${YELLOW}! $1${NC}"
}

notify() {
    if command -v notify-send &>/dev/null; then
        notify-send -i "system-shutdown" "System Reset" "$1"
    fi
}

confirm() {
    local prompt="$1"
    read -p "$(echo -e "${YELLOW}${prompt} [y/N]: ${NC}")" answer
    [[ "$answer" =~ ^[Yy]$ ]]
}

# =============================================================================
# RESTORE FROM BACKUP
# =============================================================================

restore_from_backup() {
    print_step "Restoring from backup..."
    
    if [[ ! -d "$BACKUP_DIR" ]]; then
        print_err "No backup found at $BACKUP_DIR"
        notify "No backup found!"
        exit 1
    fi
    
    if ! confirm "This will overwrite your current configs. Continue?"; then
        print_warn "Cancelled"
        exit 0
    fi
    
    for config in "${CONFIGS[@]}"; do
        local src="$BACKUP_DIR/$config"
        local dst="$HOME/$config"
        
        if [[ -e "$src" ]]; then
            # Create parent directory if needed
            mkdir -p "$(dirname "$dst")"
            
            # Remove existing
            rm -rf "$dst"
            
            # Copy from backup
            cp -r "$src" "$dst"
            print_ok "Restored $(basename "$config")"
        fi
    done
    
    # Make scripts executable
    chmod +x "$HOME/.local/bin/"* 2>/dev/null || true
    chmod +x "$HOME/user_scripts/"*/*.sh 2>/dev/null || true
    
    # Reload Hyprland
    hyprctl reload 2>/dev/null || true
    
    print_ok "Restore complete!"
    notify "Configs restored from backup!"
    
    echo ""
    echo -e "${CYAN}You may need to:${NC}"
    echo "  → Log out and back in, or"
    echo "  → Run: hyprctl reload"
}

# =============================================================================
# FETCH FROM GITHUB
# =============================================================================

fetch_from_github() {
    print_step "Fetching latest configs from GitHub..."
    
    if ! confirm "This will overwrite your current configs. Continue?"; then
        print_warn "Cancelled"
        exit 0
    fi
    
    # Check if dotfiles repo exists
    if [[ -d "$DOTFILES_DIR/.git" ]]; then
        print_step "Pulling latest changes..."
        cd "$DOTFILES_DIR"
        git --git-dir="$DOTFILES_DIR" --work-tree="$HOME" pull --force 2>/dev/null || {
            print_err "Failed to pull. Trying fresh clone..."
            fetch_fresh
        }
    else
        print_step "Cloning repository..."
        fetch_fresh
    fi
    
    # Copy configs from repo
    for config in "${CONFIGS[@]}"; do
        local src="$DOTFILES_DIR/$config"
        local dst="$HOME/$config"
        
        if [[ -e "$src" ]]; then
            mkdir -p "$(dirname "$dst")"
            rm -rf "$dst"
            cp -r "$src" "$dst"
            print_ok "Updated $(basename "$config")"
        fi
    done
    
    # Make scripts executable
    chmod +x "$HOME/.local/bin/"* 2>/dev/null || true
    chmod +x "$HOME/user_scripts/"*/*.sh 2>/dev/null || true
    
    # Reload Hyprland
    hyprctl reload 2>/dev/null || true
    
    print_ok "Fetch complete!"
    notify "Configs updated from GitHub!"
    
    echo ""
    echo -e "${CYAN}You may need to:${NC}"
    echo "  → Log out and back in, or"
    echo "  → Run: hyprctl reload"
}

fetch_fresh() {
    local tmp_dir=$(mktemp -d)
    git clone --bare --depth 1 "$GITHUB_REPO" "$tmp_dir/dotfiles" 2>/dev/null
    git --git-dir="$tmp_dir/dotfiles" --work-tree="$HOME" checkout -f 2>/dev/null
    rm -rf "$tmp_dir"
}

# =============================================================================
# MAIN MENU
# =============================================================================

main() {
    CHOICE=$(printf "Back\nUpdate from Backup\nFetch from GitHub" | rofi -dmenu -p "System Reset" -theme-str 'configuration { show-icons: false; }')
    
    [ -z "$CHOICE" ] && exit 0
    [ "$CHOICE" = "Back" ] && exit 0
    
    case "$CHOICE" in
        "Update from Backup")
            restore_from_backup
            ;;
        "Fetch from GitHub")
            fetch_from_github
            ;;
    esac
}

main "$@"
