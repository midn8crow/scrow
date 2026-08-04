#!/bin/bash
# =============================================================================
# ORCHESTRA.sh - Complete Installation Script
# =============================================================================
# This script installs everything and configures the system exactly like my setup
# =============================================================================

set -euo pipefail

# =============================================================================
# COLORS & ICONS
# =============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

CHECK="${GREEN}✓${NC}"
CROSS="${RED}✗${NC}"
ARROW="${CYAN}→${NC}"
WARN="${YELLOW}!${NC}"
INFO="${BLUE}i${NC}"

# =============================================================================
# VARIABLES
# =============================================================================
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUP_DIR="$HOME/.config/backup/$(date +%Y%m%d_%H%M%S)"
LOG_FILE="/tmp/orchestra-install.log"
GPU="unknown"
IS_LAPTOP=false
# AUR-only packages filtered out of the core pacman list (installed via paru later)
AUR_EXTRA=()

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

print_banner() {
    clear
    echo -e "${PURPLE}"
    cat << 'EOF'
    ╔═══════════════════════════════════════════════════════════════╗
    ║                                                               ║
    ║   ██████╗ ██╗   ██╗███╗   ██╗ ██████╗ ███████╗ ██████╗ ██╗   ║
    ║   ██╔══██╗██║   ██║████╗  ██║██╔════╝ ██╔════╝██╔═══██╗██║   ║
    ║   ██║  ██║██║   ██║██╔██╗ ██║██║  ███╗█████╗  ██║   ██║██║   ║
    ║   ██║  ██║██║   ██║██║╚██╗██║██║   ██║██╔══╝  ██║   ██║██║   ║
    ║   ██████╔╝╚██████╔╝██║ ╚████║╚██████╔╝███████╗╚██████╔╝██║   ║
    ║   ╚═════╝  ╚═════╝ ╚═╝  ╚═══╝ ╚═════╝ ╚══════╝ ╚═════╝ ╚═╝   ║
    ║                                                               ║
    ║              Complete Hyprland Setup Installer                ║
    ║                                                               ║
    ╚═══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

print_step() {
    echo -e "\n${BLUE}${ARROW} ${WHITE}$1${NC}"
}

print_ok() {
    echo -e "${GREEN}${CHECK} $1${NC}"
}

print_err() {
    echo -e "${RED}${CROSS} $1${NC}"
}

print_warn() {
    echo -e "${YELLOW}${WARN} $1${NC}"
}

print_info() {
    echo -e "${CYAN}${INFO} $1${NC}"
}

confirm() {
    local prompt="$1"
    local default="${2:-y}"
    local options="[Y/n]"
    [[ "$default" == "n" ]] && options="[y/N]"
    
    read -p "$(echo -e "${CYAN}${prompt} ${options}: ${NC}")" answer
    [[ "${answer:-$default}" =~ ^[Yy]$ ]]
}

ask_sudo() {
    echo -e "${YELLOW}${WARN} This action requires sudo privileges${NC}"
    sudo -v 2>/dev/null || {
        print_info "Please enter your password:"
        sudo -v
    }
}

log() {
    echo "[$(date '+%H:%M:%S')] $1" >> "$LOG_FILE"
}

# =============================================================================
# DETECTION FUNCTIONS
# =============================================================================

check_system() {
    print_step "Checking system..."
    
    if [[ ! -f /etc/arch-release ]]; then
        print_err "This script requires Arch Linux"
        exit 1
    fi
    print_ok "Arch Linux detected"
    
    if ! ping -c 1 -W 3 google.com &>/dev/null; then
        print_err "No internet connection"
        exit 1
    fi
    print_ok "Internet connection verified"
}

detect_gpu() {
    print_step "Detecting GPU..."
    
    if lspci 2>/dev/null | grep -qi "nvidia"; then
        GPU="nvidia"
        print_ok "NVIDIA GPU detected"
    elif lspci 2>/dev/null | grep -qi "amd"; then
        GPU="amd"
        print_ok "AMD GPU detected"
    elif lspci 2>/dev/null | grep -qi "intel"; then
        GPU="intel"
        print_ok "Intel GPU detected"
    else
        GPU="none"
        print_warn "No dedicated GPU detected"
    fi
}

detect_laptop() {
    print_step "Detecting device type..."
    
    if [[ -d /sys/class/power_supply/BAT0 ]] || [[ -d /sys/class/power_supply/BAT1 ]]; then
        IS_LAPTOP=true
        print_ok "Laptop detected"
    else
        IS_LAPTOP=false
        print_ok "Desktop detected"
    fi
}

# =============================================================================
# INSTALLATION FUNCTIONS
# =============================================================================

install_paru() {
    print_step "Installing AUR helper (paru)..."
    
    if command -v paru &>/dev/null; then
        print_ok "paru already installed"
        return 0
    fi
    
    ask_sudo
    sudo pacman -S --needed --noconfirm base-devel git
    
    local tmp_dir=$(mktemp -d)
    git clone https://aur.archlinux.org/paru-bin.git "$tmp_dir/paru-bin"
    cd "$tmp_dir/paru-bin"
    makepkg -si --noconfirm
    cd -
    rm -rf "$tmp_dir"
    
    print_ok "paru installed"
}

install_core_packages() {
    print_step "Installing core packages..."
    
    ask_sudo
    
    # Wayland & Hyprland
    local wayland_pkgs=(
        "hyprland"
        "hyprlock"
        "hypridle"
        "xdg-desktop-portal-hyprland"
        "xdg-desktop-portal-gtk"
        "xdg-utils"
    )
    
    # Status bar & Launcher
    local ui_pkgs=(
        "waybar"
        "rofi"
        "mako"
        "nm-connection-editor"
        "network-manager-applet"
        "blueman"
        "pavucontrol"
        "hyprpolkitagent"
    )
    
    # Terminal & Shell
    local terminal_pkgs=(
        "kitty"
        "zsh"
        "zsh-autosuggestions"
        "zsh-syntax-highlighting"
        "starship"
        "fzf"
        "zoxide"
        "eza"
        "ripgrep"
        "p7zip"
        "wget"
        "curl"
        "git"
    )
    
    # File Managers
    local filemanager_pkgs=(
        "thunar"
        "gvfs"
        "file-roller"
        "ffmpegthumbnailer"
    )
    
    # Fonts
    local font_pkgs=(
        "ttf-jetbrains-mono-nerd"
        "noto-fonts"
        "noto-fonts-emoji"
    )
    
    # Appearance
    local theme_pkgs=(
        "adw-gtk-theme"
        "qt6ct"
        "papirus-icon-theme"
    )
    
    # System Tools
    local tools_pkgs=(
        "fastfetch"
        "btop"
        "htop"
        "mpv"
        "cava"
        "brightnessctl"
        "playerctl"
        "ffmpeg"
        "wireplumber"
        "jq"
        "pacman-contrib"
        "reflector"
        "awww"
        "rclone"
        "loupe"
        "firefox"
        "7zip"
        "amd-ucode"
        "attr"
        "base"
        "base-devel"
        "blender"
        "bluez"
        "bluez-utils"
        "catppuccin-gtk-theme-mocha"
        "chess-tui"
        "chromium"
        "cloudflare-warp-bin"
        "cmatrix"
        "cups"
        "cups-pk-helper"
        "ddcutil"
        "dunst"
        "efibootmgr"
        "fcitx5"
        "fcitx5-configtool"
        "fcitx5-gtk"
        "fcitx5-qt"
        "file"
        "flac"
        "fuse3"
        "gimp"
        "git-delta"
        "github-cli"
        "gpsd"
        "grim"
        "grub"
        "gst-plugin-pipewire"
        "gvfs-afc"
        "gvfs-dnssd"
        "gvfs-gphoto2"
        "gvfs-mtp"
        "hyprshot"
        "inkscape"
        "intel-media-driver"
        "iproute2"
        "keypunch-git"
        "kimageformats"
        "libgepub"
        "libgsf"
        "libopenraw"
        "libpulse"
        "libqalculate"
        "libreoffice-fresh"
        "libva-intel-driver"
        "libva-utils"
        "linux-firmware"
        "llvm"
        "localsend"
        "lua"
        "lynis"
        "mkinitcpio"
        "modemmanager"
        "mousepad"
        "mpvpaper"
        "ncurses"
        "neovim"
        "networkmanager"
        "obsidian"
        "openbangla-keyboard-fcitx-git"
        "opencode"
        "p11-kit"
        "pacseek-bin"
        "paru-debug"
        "pipewire"
        "pipewire-alsa"
        "pipewire-jack"
        "pipewire-pulse"
        "polkit-kde-agent"
        "poppler-glib"
        "power-profiles-daemon"
        "proton-vpn-gtk-app"
        "proxychains-ng"
        "psmisc"
        "python-distro"
        "python-keyring"
        "qt5-wayland"
        "qt6-wayland"
        "resvg"
        "rofi-emoji"
        "satty"
        "sddm"
        "slurp"
        "smartmontools"
        "songrec"
        "stockfish"
        "swappy"
        "system-config-printer"
        "systemd-sysvcompat"
        "tela-circle-icon-theme-dracula"
        "tela-circle-icon-theme-nord"
        "telegram-desktop"
        "tesseract"
        "tesseract-data-ben"
        "tesseract-data-eng"
        "tor"
        "torbrowser-launcher"
        "traceroute"
        "tty-clock"
        "tumbler"
        "uv"
        "uwsm"
        "vim"
        "vulkan-intel"
        "vulkan-nouveau"
        "vulkan-radeon"
        "waybar-cava-git"
        "webp-pixbuf-loader"
        "wofi"
        "wtype"
        "xdg-user-dirs"
        "xf86-video-amdgpu"
        "xf86-video-ati"
        "xf86-video-nouveau"
        "xorg-server"
        "yazi"
        "ytdlp-gui"
        "zenity"
        "zram-generator"
        "7zip"
        "amd-ucode"
        "attr"
        "base"
        "base-devel"
        "blender"
        "bluez"
        "bluez-utils"
        "catppuccin-gtk-theme-mocha"
        "chess-tui"
        "chromium"
        "cloudflare-warp-bin"
        "cmatrix"
        "cups"
        "cups-pk-helper"
        "ddcutil"
        "dunst"
        "efibootmgr"
        "fcitx5"
        "fcitx5-configtool"
        "fcitx5-gtk"
        "fcitx5-qt"
        "file"
        "flac"
        "fuse3"
        "gimp"
        "git-delta"
        "github-cli"
        "gpsd"
        "grim"
        "grub"
        "gst-plugin-pipewire"
        "gvfs-afc"
        "gvfs-dnssd"
        "gvfs-gphoto2"
        "gvfs-mtp"
        "hyprshot"
        "inkscape"
        "intel-media-driver"
        "iproute2"
        "keypunch-git"
        "kimageformats"
        "libgepub"
        "libgsf"
        "libopenraw"
        "libpulse"
        "libqalculate"
        "libreoffice-fresh"
        "libva-intel-driver"
        "libva-utils"
        "linux-firmware"
        "llvm"
        "localsend"
        "lua"
        "lynis"
        "mkinitcpio"
        "modemmanager"
        "mousepad"
        "mpvpaper"
        "ncurses"
        "neovim"
        "networkmanager"
        "obsidian"
        "openbangla-keyboard-fcitx-git"
        "opencode"
        "p11-kit"
        "pacseek-bin"
        "paru-debug"
        "pipewire"
        "pipewire-alsa"
        "pipewire-jack"
        "pipewire-pulse"
        "polkit-kde-agent"
        "poppler-glib"
        "power-profiles-daemon"
        "proton-vpn-gtk-app"
        "proxychains-ng"
        "psmisc"
        "python-distro"
        "python-keyring"
        "qt5-wayland"
        "qt6-wayland"
        "resvg"
        "rofi-emoji"
        "satty"
        "sddm"
        "slurp"
        "smartmontools"
        "songrec"
        "stockfish"
        "swappy"
        "system-config-printer"
        "systemd-sysvcompat"
        "tela-circle-icon-theme-dracula"
        "tela-circle-icon-theme-nord"
        "telegram-desktop"
        "tesseract"
        "tesseract-data-ben"
        "tesseract-data-eng"
        "tor"
        "torbrowser-launcher"
        "traceroute"
        "tty-clock"
        "tumbler"
        "uv"
        "uwsm"
        "vim"
        "vulkan-intel"
        "vulkan-nouveau"
        "vulkan-radeon"
        "waybar-cava-git"
        "webp-pixbuf-loader"
        "wofi"
        "wtype"
        "xdg-user-dirs"
        "xf86-video-amdgpu"
        "xf86-video-ati"
        "xf86-video-nouveau"
        "xorg-server"
        "yazi"
        "ytdlp-gui"
        "zenity"
        "zram-generator"
        "graphicsmagick"
        "graphicsmagick"
        "moviebox-tui"
        "rust"
        "hypr-kdeconnect-fix-git"
        "kdeconnect"
    )
    
    # Clipboard
    local clipboard_pkgs=(
        "wl-clipboard"
        "cliphist"
    )
    
    # Security
    local security_pkgs=(
        "nftables"
        "fail2ban"
        "clamav"
        "rkhunter"
    )
    
    # NVIDIA (if detected)
    local nvidia_pkgs=()
    if [[ "$GPU" == "nvidia" ]]; then
        nvidia_pkgs=(
            "nvidia-dkms"
            "nvidia-utils"
            "lib32-nvidia-utils"
            "nvidia-settings"
            "libva-nvidia-driver"
        )
    fi
    
    # AMD (if detected)
    local amd_pkgs=()
    if [[ "$GPU" == "amd" ]]; then
        amd_pkgs=(
            "mesa"
            "lib32-mesa"
            "vulkan-radeon"
            "lib32-vulkan-radeon"
            "libva-mesa-driver"
            "mesa-vdpau"
        )
    fi
    
    # Intel (if detected)
    local intel_pkgs=()
    if [[ "$GPU" == "intel" ]]; then
        intel_pkgs=(
            "mesa"
            "lib32-mesa"
            "vulkan-intel"
            "lib32-vulkan-intel"
            "intel-media-driver"
            "libva-intel-driver"
        )
    fi
    
    # Split tools into repo vs AUR packages (AUR ones go to the paru step so
    # pacman is never given a target it cannot resolve).
    # Make sure the sync database exists first so pacman -Si works on a fresh install.
    if [[ ! -d /var/lib/pacman/sync ]]; then
        print_info "No pacman sync database found - syncing..."
        sudo pacman -Sy --noconfirm >/dev/null 2>&1 || true
    fi
    local repo_tools=() p
    AUR_EXTRA=()
    for p in "${tools_pkgs[@]}"; do
        if pacman -Si "$p" >/dev/null 2>&1; then
            repo_tools+=("$p")
        else
            AUR_EXTRA+=("$p")
        fi
    done
    local aur_only_count=${#AUR_EXTRA[@]}
    if [[ "$aur_only_count" -gt 0 ]]; then
        print_info "Moving $aur_only_count AUR package(s) to the paru step"
    fi

    # Install all packages
    sudo pacman -S --needed --noconfirm \
        "${wayland_pkgs[@]}" \
        "${ui_pkgs[@]}" \
        "${terminal_pkgs[@]}" \
        "${filemanager_pkgs[@]}" \
        "${font_pkgs[@]}" \
        "${theme_pkgs[@]}" \
        "${repo_tools[@]}" \
        "${clipboard_pkgs[@]}" \
        "${security_pkgs[@]}" \
        "${nvidia_pkgs[@]}" \
        "${amd_pkgs[@]}" \
        "${intel_pkgs[@]}"
    
    print_ok "Core packages installed"
}

install_aur_packages() {
    print_step "Installing AUR packages..."
    
    local aur_pkgs=(
        "wlr-randr"
        "gpu-screen-recorder"
        "brave-bin"
        "vscodium-bin"
        "matugen"
    )
    
    # Laptop specific
    if [[ "$IS_LAPTOP" == true ]]; then
        aur_pkgs+=(
            "power-profiles-daemon"
            "tlp"
        )
    fi
    
    # Include any AUR-only packages filtered out of the core list, then install.
    if [[ ${#AUR_EXTRA[@]} -gt 0 ]]; then
        aur_pkgs+=("${AUR_EXTRA[@]}")
    fi

    if ! paru -S --needed --noconfirm "${aur_pkgs[@]}"; then
        print_warn "Some AUR packages failed to install (continuing). Check the log."
    fi
    
    print_ok "AUR packages installed"
}

# =============================================================================
# CONFIGURATION FUNCTIONS
# =============================================================================

backup_existing() {
    print_step "Backing up existing configs..."
    
    mkdir -p "$BACKUP_DIR"
    
    local configs=(
        ".config/hypr"
        ".config/waybar"
        ".config/kitty"
        ".config/rofi"
        ".config/mako"
        ".config/starship.toml"
        ".zshrc"
    )
    
    for config in "${configs[@]}"; do
        local src="$HOME/$config"
        if [[ -e "$src" ]]; then
            cp -r "$src" "$BACKUP_DIR/"
            print_warn "Backed up $(basename "$config")"
        fi
    done
    
    print_ok "Backup saved to $BACKUP_DIR"
}

deploy_configs() {
    print_step "Deploying configurations..."
    
    # Create directories
    mkdir -p "$HOME/.config"
    mkdir -p "$HOME/.local/bin"
    mkdir -p "$HOME/user_scripts"
    
    # Copy .config contents
    if [[ -d "$DOTFILES_DIR/.config" ]]; then
        cp -r "$DOTFILES_DIR/.config/"* "$HOME/.config/"
        print_ok "Config files deployed"
    fi
    
    # Copy .local/bin
    if [[ -d "$DOTFILES_DIR/.local/bin" ]]; then
        cp -r "$DOTFILES_DIR/.local/bin/"* "$HOME/.local/bin/"
        chmod +x "$HOME/.local/bin/"*
        print_ok "Scripts deployed"
    fi
    
    # Copy user_scripts
    if [[ -d "$DOTFILES_DIR/user_scripts" ]]; then
        cp -r "$DOTFILES_DIR/user_scripts/"* "$HOME/user_scripts/"
        chmod +x "$HOME/user_scripts/"*/*.sh 2>/dev/null || true
        print_ok "User scripts deployed"
    fi
    
    # Copy shell config
    if [[ -f "$DOTFILES_DIR/.zshrc" ]]; then
        cp "$DOTFILES_DIR/.zshrc" "$HOME/.zshrc"
        print_ok "Zsh config deployed"
    fi
    
    # Copy cursor themes
    if [[ -d "$DOTFILES_DIR/.local/share/icons" ]]; then
        mkdir -p "$HOME/.local/share/icons"
        cp -r "$DOTFILES_DIR/.local/share/icons/"* "$HOME/.local/share/icons/"
        print_ok "Cursor themes deployed"
    fi
}

configure_hyprland() {
    print_step "Configuring Hyprland..."
    
    local hypr_dir="$HOME/.config/hypr"
    
    # Generate hardware-specific env vars
    cat > "$hypr_dir/modules/env-hardware.lua" << EOF
-- Hardware-specific environment variables
-- Generated by ORCHESTRA.sh

EOF
    
    case "$GPU" in
        "nvidia")
            cat >> "$hypr_dir/modules/env-hardware.lua" << 'EOF'
-- NVIDIA Environment
hl.env("NVIDIA_NO_OVERLAY", "1")
hl.env("__NV_PRIME_RENDER_OFFLOAD", "1")
hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
hl.env("GBM_BACKEND", "nvidia-drm")
hl.env("__GL_GSYNC_ALLOWED", "1")
hl.env("__GL_VRR_ALLOWED", "1")
hl.env("WLR_NO_HARDWARE_CURSORS", "1")
EOF
            ;;
        "amd")
            cat >> "$hypr_dir/modules/env-hardware.lua" << 'EOF'
-- AMD Environment
hl.env("AMD_VULKAN_ICD", "RADV")
hl.env("RADV_PERFTEST", "gpl")
hl.env("mesa_glthread", "true")
hl.env("vblank_mode", "0")
EOF
            ;;
        "intel")
            cat >> "$hypr_dir/modules/env-hardware.lua" << 'EOF'
-- Intel Environment
hl.env("INTEL_DESKTOP伉", "1")
hl.env("LIBVA_DRIVER_NAME", "iHD")
EOF
            ;;
    esac
    
    # Generate hardware-specific monitor config
    cat > "$hypr_dir/modules/monitors-hardware.lua" << 'EOF'
-- Monitor configuration
-- Adjust resolution and refresh rate for your display

hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "0x0",
    scale    = "1",
})

-- Add additional monitors here
-- hl.monitor({
--     output   = "HDMI-A-1",
--     mode     = "1920x1080@60",
--     position = "1920x0",
--     scale    = "1",
-- })
EOF
    
    # Update hyprland.lua to include hardware config
    if [[ -f "$hypr_dir/hyprland.lua" ]]; then
        # Add hardware env if not already there
        if ! grep -q "env-hardware" "$hypr_dir/hyprland.lua"; then
            sed -i 's/require("modules.env")/require("modules.env")\nrequire("modules.env-hardware")/' "$hypr_dir/hyprland.lua"
        fi
    fi
    
    print_ok "Hyprland configured"
}

configure_shell() {
    print_step "Configuring shell..."
    
    # Set zsh as default
    if [[ "$SHELL" != "$(which zsh)" ]]; then
        chsh -s "$(which zsh)" 2>/dev/null || print_warn "Could not change default shell (run manually: chsh -s \$(which zsh))"
    fi
    
    # Initialize tools
    command -v starship &>/dev/null && starship init zsh > "$HOME/.starship-init.zsh" 2>/dev/null
    command -v fzf &>/dev/null && fzf --zsh > "$HOME/.fzf-init.zsh" 2>/dev/null
    command -v zoxide &>/dev/null && zoxide init zsh > "$HOME/.zoxide-init.zsh" 2>/dev/null

    # Wire rustup cargo env (guarded so a system without rustup doesn't error)
    if [[ -f "$HOME/.zshrc" ]] && ! grep -q 'cargo/env' "$HOME/.zshrc"; then
        printf '\n. "$HOME/.cargo/env" 2>/dev/null || true\n' >> "$HOME/.zshrc"
        print_ok "cargo (rustup) env wired into .zshrc"
    fi
    
    print_ok "Shell configured"
}

configure_gtk() {
    print_step "Configuring GTK theme..."
    
    mkdir -p "$HOME/.config/gtk-3.0"
    cat > "$HOME/.config/gtk-3.0/settings.ini" << 'EOF'
[Settings]
gtk-cursor-theme-name=Bibata-Modern-Classic
gtk-cursor-theme-size=24
EOF
    
    mkdir -p "$HOME/.config/gtk-4.0"
    cp "$HOME/.config/gtk-3.0/settings.ini" "$HOME/.config/gtk-4.0/settings.ini"
    
    gsettings set org.gnome.desktop.interface color-scheme prefer-dark 2>/dev/null || true
    
    # Qt config
    mkdir -p "$HOME/.config/qt6ct"
    cat > "$HOME/.config/qt6ct/qt6ct.conf" << 'EOF'
[Appearance]
color_scheme_path=
icon_theme=
style=Fusion
color_scheme_type=2
EOF
    
    print_ok "GTK configured"
}

configure_loupe() {
    print_step "Configuring Loupe (Image Viewer)..."
    gsettings set org.gnome.Loupe show-properties false 2>/dev/null || true
    print_ok "Loupe configured"
}

configure_fonts() {
    print_step "Configuring fonts..."
    
    fc-cache -fv
    
    print_ok "Fonts configured"
}

configure_services() {
    print_step "Configuring services..."
    
    ask_sudo
    
    # NetworkManager
    sudo systemctl enable --now NetworkManager 2>/dev/null || true
    
    # Bluetooth
    if [[ "$IS_LAPTOP" == true ]] || ls /sys/class/bluetooth/ &>/dev/null; then
        sudo systemctl enable --now bluetooth 2>/dev/null || true
    fi
    
    # Power management for laptops
    if [[ "$IS_LAPTOP" == true ]]; then
        sudo systemctl enable --now power-profiles-daemon 2>/dev/null || true
    fi
    
    # PipeWire audio
    sudo systemctl enable --now pipewire 2>/dev/null || true
    sudo systemctl enable --now pipewire-pulse 2>/dev/null || true
    sudo systemctl enable --now wireplumber 2>/dev/null || true
    
    print_ok "Services configured"
}

configure_security() {
    print_step "Configuring security..."
    
    ask_sudo
    
    local security_dir="$DOTFILES_DIR/security-hardening"
    
    # Install security packages
    print_info "Installing security packages..."
    sudo pacman -S --needed --noconfirm nftables fail2ban clamav rkhunter pacman-contrib bubblewrap 2>/dev/null || true
    
    # Deploy security scripts to ~/security-hardening/
    print_info "Deploying security scripts..."
    mkdir -p "$HOME/security-hardening"
    if [[ -d "$security_dir" ]]; then
        cp "$security_dir"/* "$HOME/security-hardening/" 2>/dev/null || true
        chmod +x "$HOME/security-hardening/"*.sh 2>/dev/null || true
        print_ok "Security scripts deployed to ~/security-hardening/"
    fi

    # Install the pre-install package scan hook (fires on every pacman/paru update)
    print_info "Installing update-scan pacman hook..."
    mkdir -p /etc/pacman.d/hooks
    if [ -f "$HOME/security-hardening/update-scan.hook" ]; then
        sudo install -Dm644 "$HOME/security-hardening/update-scan.hook" /etc/pacman.d/hooks/update-scan.hook
        print_ok "Update-scan hook installed (every update is scanned before install)"
    else
        print_warn "update-scan.hook not found, skipping"
    fi
    
    # Deploy scrow menu scripts to ~/.local/bin/
    print_info "Deploying scrow menu scripts..."
    local scrow_dir="$DOTFILES_DIR/user_scripts/scrow"
    if [[ -d "$scrow_dir" ]]; then
        mkdir -p "$HOME/.local/bin"
        cp "$scrow_dir"/* "$HOME/.local/bin/" 2>/dev/null || true
        chmod +x "$HOME/.local/bin/"* 2>/dev/null || true
        print_ok "Scrow scripts deployed to ~/.local/bin/"
    fi
    
    # Copy security configs
    print_info "Deploying security configurations..."
    sudo cp "$security_dir/sshd_hardened.conf" /etc/ssh/sshd_config.d/99-hardened.conf 2>/dev/null || true
    sudo cp "$security_dir/nftables_hardened.conf" /etc/nftables.conf 2>/dev/null || true
    sudo cp "$security_dir/sysctl_security.conf" /etc/sysctl.d/99-security.conf 2>/dev/null || true
    sudo cp "$security_dir/fail2ban_jail.local" /etc/fail2ban/jail.local 2>/dev/null || true
    sudo cp "$security_dir/usb-scan.sh" /usr/local/bin/usb-scan.sh 2>/dev/null || true
    sudo cp "$security_dir/usb-scan.rules" /etc/udev/rules.d/99-usb-scan.rules 2>/dev/null || true
    sudo cp "$security_dir/clamav-monitor.sh" /usr/local/bin/clamav-monitor.sh 2>/dev/null || true
    sudo cp "$security_dir/clamav-monitor.service" /etc/systemd/system/clamav-monitor.service 2>/dev/null || true
    
    # Make scripts executable
    sudo chmod +x /usr/local/bin/usb-scan.sh 2>/dev/null || true
    sudo chmod +x /usr/local/bin/clamav-monitor.sh 2>/dev/null || true
    
    # Load firewall rules directly (systemctl start can fail in terminals)
    print_info "Loading firewall rules..."
    sudo nft -f /etc/nftables.conf 2>/dev/null || true
    sudo systemctl enable nftables 2>/dev/null || true
    
    # Apply kernel hardening
    print_info "Applying kernel hardening..."
    sudo sysctl --system > /dev/null 2>&1 || true
    
    # Enable services
    print_info "Enabling security services..."
    sudo systemctl enable fail2ban 2>/dev/null || true
    sudo systemctl start fail2ban 2>/dev/null || true
    sudo systemctl enable sshd 2>/dev/null || true
    sudo systemctl start sshd 2>/dev/null || true
    sudo systemctl daemon-reload 2>/dev/null || true
    sudo systemctl enable clamav-monitor 2>/dev/null || true
    sudo systemctl start clamav-monitor 2>/dev/null || true
    
    # Install VPN/WARP firewall re-apply hook
    print_info "Installing VPN firewall hook..."
    sudo tee /etc/NetworkManager/dispatcher.d/99-reapply-firewall > /dev/null << 'HOOK'
#!/bin/bash
INTERFACE=$1
ACTION=$2
if [ "$ACTION" = "up" ]; then
    /usr/bin/nft -f /etc/nftables.conf 2>/dev/null
fi
HOOK
    sudo chmod 755 /etc/NetworkManager/dispatcher.d/99-reapply-firewall
    sudo systemctl restart NetworkManager 2>/dev/null || true
    
    # Disable LLMNR
    print_info "Disabling LLMNR..."
    if [ -f /etc/systemd/resolved.conf ]; then
        sudo sed -i 's/^#LLMNR=.*/LLMNR=no/' /etc/systemd/resolved.conf 2>/dev/null || true
        grep -q "^LLMNR=" /etc/systemd/resolved.conf 2>/dev/null || echo "LLMNR=no" | sudo tee -a /etc/systemd/resolved.conf > /dev/null
        sudo systemctl restart systemd-resolved 2>/dev/null || true
    fi
    
    # Disable unused services
    print_info "Disabling unused services..."
    for svc in avahi-daemon cups; do
        sudo systemctl disable --now "$svc" 2>/dev/null || true
    done
    
    # Fix user file permissions
    print_info "Fixing file permissions..."
    chmod 700 ~/.ssh 2>/dev/null || true
    chmod 600 ~/.ssh/id_* 2>/dev/null || true
    chmod 600 ~/.ssh/*_key 2>/dev/null || true
    chmod 644 ~/.ssh/*.pub 2>/dev/null || true
    chmod 600 ~/.bash_history 2>/dev/null || true
    chmod 600 ~/.zsh_history 2>/dev/null || true
    
    # Update ClamAV definitions
    print_info "Updating ClamAV definitions..."
    sudo freshclam 2>/dev/null || true
    
    print_ok "Security configured"
}

configure_grub() {
    print_step "Configuring GRUB theme..."
    
    ask_sudo
    
    local theme_dir="/boot/grub/themes/minegrub"
    local dotfiles_grub="$DOTFILES_DIR/boot/grub"
    
    # Copy theme files
    if [[ -d "$dotfiles_grub/themes/minegrub" ]]; then
        sudo cp -r "$dotfiles_grub/themes/minegrub" /boot/grub/themes/
        print_ok "Minecraft GRUB theme files copied"
    else
        print_warn "GRUB theme files not found, skipping"
        return 0
    fi
    
    # Update GRUB config if not already set
    if ! grep -q "minegrub" /etc/default/grub 2>/dev/null; then
        sudo sed -i 's|#.*GRUB_THEME=.*|GRUB_THEME=/boot/grub/themes/minegrub/theme.txt|' /etc/default/grub
        if ! grep -q "GRUB_THEME" /etc/default/grub; then
            echo "GRUB_THEME=/boot/grub/themes/minegrub/theme.txt" | sudo tee -a /etc/default/grub > /dev/null
        fi
        print_ok "GRUB config updated"
    else
        print_ok "GRUB theme already configured"
    fi
    
    # Regenerate GRUB config
    sudo grub-mkconfig -o /boot/grub/grub.cfg 2>/dev/null || print_warn "Could not regenerate GRUB config (run manually: sudo grub-mkconfig -o /boot/grub/grub.cfg)"
    
    print_ok "GRUB configured"
}

configure_hyprpm() {
    print_step "Setting up hyprpm auto-update hook..."

    ask_sudo

    sudo mkdir -p /etc/pacman.d/hooks
    sudo cp "$DOTFILES_DIR/etc/pacman.d/hooks/hyprpm-update.hook" /etc/pacman.d/hooks/
    sudo cp "$DOTFILES_DIR/etc/pacman.d/hooks/hyprpm-post-update.sh" /etc/pacman.d/hooks/
    sudo chmod +x /etc/pacman.d/hooks/hyprpm-post-update.sh

    print_ok "Hyprpm auto-update hook installed"

    print_step "Installing ScrollOverview plugin..."

    hyprpm add https://github.com/yayuuu/hyprland-scroll-overview.git || true
    hyprpm update || true
    hyprpm enable scrolloverview || true

    print_ok "ScrollOverview plugin installed"
}

set_permissions() {
    print_step "Setting permissions..."
    
    # Make scripts executable
    chmod +x "$HOME/.local/bin/"* 2>/dev/null || true
    chmod +x "$HOME/user_scripts/"*/*.sh 2>/dev/null || true
    chmod +x "$HOME/.config/waybar/"*.sh 2>/dev/null || true
    
    print_ok "Permissions set"
}

# =============================================================================
# FINAL SETUP
# =============================================================================

create_uninstall_script() {
    cat > "$HOME/.local/bin/uninstall-dotfiles" << 'UNINSTALL'
#!/bin/bash
# Uninstall script - removes deployed configs

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${RED}This will remove all deployed dotfiles configs!${NC}"
read -p "Are you sure? (y/N): " confirm
[[ "$confirm" =~ ^[Yy]$ ]] || exit 0

echo "Removing configs..."
rm -rf ~/.config/hypr
rm -rf ~/.config/waybar
rm -rf ~/.config/kitty
rm -rf ~/.config/rofi
rm -rf ~/.config/mako
rm -f ~/.config/starship.toml
rm -f ~/.zshrc

echo -e "${GREEN}Configs removed. Backup still available in ~/.config/backup/${NC}"
UNINSTALL
    chmod +x "$HOME/.local/bin/uninstall-dotfiles"
}

create_initial_backup() {
    print_step "Creating initial backup..."
    
    local backup_dir="$HOME/.config/backup/initial"
    mkdir -p "$backup_dir"
    
    local configs=(
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
    
    for config in "${configs[@]}"; do
        local src="$HOME/$config"
        local dst="$backup_dir/$config"
        
        if [[ -e "$src" ]]; then
            mkdir -p "$(dirname "$dst")"
            cp -r "$src" "$dst"
        fi
    done
    
    print_ok "Initial backup created at $backup_dir"
}

print_summary() {
    echo -e "\n${GREEN}"
    cat << 'EOF'
    ╔═══════════════════════════════════════════════════════════════╗
    ║                                                               ║
    ║                  Installation Complete!                       ║
    ║                                                               ║
    ╚═══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    
    echo -e "${CYAN}${WHITE}System Info:${NC}"
    echo -e "  ${ARROW} GPU: ${GPU}"
    echo -e "  ${ARROW} Device: ${IS_LAPTOP:+Laptop}${IS_LAPTOP:-Desktop}"
    echo -e "  ${ARROW} Backup: ${BACKUP_DIR}"
    echo -e "  ${ARROW} Log: ${LOG_FILE}"
    
    echo -e "\n${CYAN}${WHITE}Quick Start:${NC}"
    echo -e "  ${ARROW} Log out and log back in (or reboot)"
    echo -e "  ${ARROW} Or run: Hyprland"
    
    echo -e "\n${CYAN}${WHITE}Keybinds:${NC}"
    echo -e "  ${ARROW} SUPER + Q      → Terminal"
    echo -e "  ${ARROW} SUPER + B      → Browser"
    echo -e "  ${ARROW} SUPER + E      → File Manager"
    echo -e "  ${ARROW} ALT + Space    → App Launcher"
    echo -e "  ${ARROW} CTRL + SHIFT + ? → Keybinds"
    
    echo -e "\n${CYAN}${WHITE}Useful Commands:${NC}"
    echo -e "  ${ARROW} hyprctl reload        → Reload Hyprland"
    echo -e "  ${ARROW} waybar-restart        → Restart Waybar"
    echo -e "  ${ARROW} update-colors        → Update theme colors"
    
    echo -e "\n${CYAN}${WHITE}Uninstall:${NC}"
    echo -e "  ${ARROW} Run: uninstall-dotfiles"
    
    echo -e "\n${GREEN}Enjoy your new setup!${NC}\n"
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    print_banner
    
    echo -e "${CYAN}This will install and configure everything like my setup.${NC}\n"
    
    if ! confirm "Ready to begin?"; then
        echo -e "\n${YELLOW}Installation cancelled.${NC}"
        exit 0
    fi
    
    # Initialize log
    echo "=== Installation started at $(date) ===" > "$LOG_FILE"
    
    # Detection
    check_system
    detect_gpu
    detect_laptop
    
    echo -e "\n${CYAN}${WHITE}Detected:${NC}"
    echo -e "  ${ARROW} GPU: ${GPU}"
    echo -e "  ${ARROW} Device: ${IS_LAPTOP:+Laptop}${IS_LAPTOP:-Desktop}"
    
    if ! confirm "Proceed with installation?"; then
        echo -e "\n${YELLOW}Installation cancelled.${NC}"
        exit 0
    fi
    
    # Installation
    install_paru
    install_core_packages
    install_aur_packages
    
    # Configuration
    backup_existing
    deploy_configs
    configure_hyprland
    configure_shell
    configure_gtk
    configure_loupe
    configure_fonts
    configure_services
    configure_security
    configure_grub
    configure_hyprpm
    set_permissions
    
    # Final
    create_uninstall_script
    create_initial_backup
    print_summary
    
    echo "=== Installation completed at $(date) ===" >> "$LOG_FILE"
}

main "$@"
