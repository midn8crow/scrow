# Hyprland Dotfiles

A complete, ready-to-use Hyprland configuration for Arch Linux. One command to install everything.

![Hyprland](https://img.shields.io/badge/Hyprland-Wayland-5e81ac?style=for-the-badge&logo=hyprland&logoColor=white)
![Arch Linux](https://img.shields.io/badge/Arch%20Linux-1793D1?style=for-the-badge&logo=archlinux&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-yellow?style=for-the-badge)

## What's Included

- **Hyprland** - Wayland compositor with smooth animations
- **Waybar** - Status bar with multiple themes (vertical/horizontal)
- **Kitty** - Terminal with custom colors and fonts
- **Rofi** - App launcher and menus
- **SwayNC** - Notification center
- **Zsh** - Shell with Starship prompt
- **Theming** - Automatic color generation

## Quick Install

### One-Line Install

```bash
git clone --bare --depth 1 https://github.com/YOUR_USERNAME/dotfiles.git $HOME/dotfiles && git --git-dir=$HOME/dotfiles/ --work-tree=$HOME checkout -f && ~/scripts/ORCHESTRA.sh
```

### Step-by-Step

```bash
# 1. Clone the repository (bare repo method)
git clone --bare --depth 1 https://github.com/YOUR_USERNAME/dotfiles.git $HOME/dotfiles

# 2. Deploy all files
git --git-dir=$HOME/dotfiles/ --work-tree=$HOME checkout -f

# 3. Run the installer
~/scripts/ORCHESTRA.sh
```

### What the Installer Does

1. **Detects your hardware** (GPU, laptop/desktop)
2. **Installs all packages** (Hyprland, Waybar, Kitty, etc.)
3. **Installs GPU drivers** (NVIDIA/AMD/Intel)
4. **Copies all configs** to the right places
5. **Configures your shell** (Zsh + Starship)
6. **Enables services** (NetworkManager, Bluetooth, Audio)
7. **Sets up theming** (GTK, Qt, Fonts)

## Features

### Multiple Waybar Themes

Switch between different waybar styles:

```bash
# Next theme
ALT + SHIFT + W

# Previous theme
ALT + W
```

Available themes:
- Default (vertical)
- Athena
- Minimal
- And more...

### Keybinds

| Key | Action |
|-----|--------|
| `SUPER + Q` | Terminal |
| `SUPER + B` | Browser |
| `SUPER + E` | File Manager |
| `SUPER + C` | Close Window |
| `SUPER + M` | Exit Menu |
| `ALT + Space` | App Launcher |
| `ALT + SHIFT + Space` | Power Menu |
| `SUPER + N` | Notifications |
| `SUPER + W` | Switch Wallpaper |
| `SUPER + R` | Reload Hyprland |
| `SUPER + S` | Screenshot Region |
| `SUPER + PRINT` | Screenshot Full |
| `ALT + ↑/↓` | Brightness |
| `ALT + ←/→` | Volume |
| `CTRL + SHIFT + ?` | Keybinds Help |

### Scripts

All scripts are in `~/.local/bin/`:

| Script | Description |
|--------|-------------|
| `wallpaper-switch.sh` | Cycle wallpapers |
| `vol-notify.sh` | Volume control with notification |
| `brightness.sh` | Brightness control |
| `screenshot-region.sh` | Region screenshot |
| `screenshot-full.sh` | Full screenshot |
| `gpu-recorder.sh` | GPU screen recording |
| `theme-menu.sh` | Theme switcher menu |
| `powermenu.sh` | Power/logout menu |
| `force-kill.sh` | Force kill window |
| `keybinds` | Show keybinds |

## Package List

### Core Packages

```
hyprland hyprlock hypridle waybar kitty rofi swaync swww-daemon
wlogout polkit-gnome network-manager-applet blueman pavucontrol
```

### Shell & Terminal

```
zsh zsh-autosuggestions zsh-syntax-highlighting starship
fzf zoxide eza bat fd ripgrep
```

### System Tools

```
fastfetch btop htop nvtop mpv cava brightnessctl playerctl
ffmpeg imagemagick jq yq tree
```

### Fonts

```
ttf-jetbrains-mono-nerd noto-fonts noto-fonts-cjk noto-fonts-emoji
ttf-font-awesome ttf-cascadia-code
```

### Appearance

```
adw-gtk3 kvantum qt6ct nwg-look papirus-icon-theme bibata-cursor-theme
```

### AUR Packages

```
hyprlauncher wlr-randr gpu-screen-recorder zen-browser-bin
visual-studio-code-bin matugen
```

## Hardware

### Tested On

- AMD Ryzen 5 PRO 4650U
- AMD Radeon RX Vega 6
- 16GB DDR4 RAM
- 512GB NVMe SSD
- 14" 1080p IPS Display

### GPU Support

| GPU | Status | Notes |
|-----|--------|-------|
| AMD | ✅ | Full support, best performance |
| NVIDIA | ✅ | Works with proprietary drivers |
| Intel | ✅ | Works with mesa drivers |

### Laptop Features

- ✅ Brightness control (Fn keys)
- ✅ Volume control (Fn keys)
- ✅ Battery indicator
- ✅ Power profiles
- ✅ Touchpad gestures

## Customization

### Changing Colors

Edit `~/.config/waybar/colors/colors.css`:

```css
@define-color bg #1e1e2e;
@define-color fg #cdd6f4;
@define-color module-bg rgba(30, 30, 46, 0.8);
@define-color accent #89b4fa;
```

### Changing Fonts

Edit `~/.config/kitty/kitty.conf`:

```
font_family      YourFont Nerd Font
font_size        12.0
```

### Adding Keybinds

Edit `~/.config/hypr/modules/binds.lua`:

```lua
hl.bind("SUPER + SHIFT + A", hl.dsp.exec_cmd("your-command"))
```

### Monitor Setup

Edit `~/.config/hypr/modules/monitors-hardware.lua`:

```lua
-- Single monitor
hl.monitor({
    output   = "",
    mode     = "1920x1080@144",
    position = "0x0",
    scale    = "1",
})

-- Dual monitor
hl.monitor({
    output   = "eDP-1",
    mode     = "1920x1080@60",
    position = "0x0",
    scale    = "1",
})
hl.monitor({
    output   = "HDMI-A-1",
    mode     = "2560x1440@144",
    position = "1920x0",
    scale    = "1",
})
```

## Troubleshooting

### Waybar not showing

```bash
waybar &
# or
~/.config/waybar/launch.sh
```

### Notifications not working

```bash
swaync &
```

### Wallpaper not changing

```bash
swww-daemon &
swww img /path/to/wallpaper.jpg
```

### Colors not updating

```bash
matugen
```

### Audio not working

```bash
wpctl status
wpctl set-default <sink-id>
```

### Reload Hyprland

```bash
hyprctl reload
```

## Uninstall

```bash
uninstall-dotfiles
```

Or manually:

```bash
rm -rf ~/.config/{hypr,waybar,kitty,rofi,swaync}
rm -f ~/.config/starship.toml
rm -f ~/.zshrc
```

## Contributing

Feel free to fork and customize! Pull requests welcome.

## License

MIT License - see [LICENSE](LICENSE)

## Credits

- [dusklinux/dusky](https://github.com/dusklinux/dusky) - Inspiration for this setup
- [Hyprland](https://hyprland.org/)
- [Waybar](https://github.com/Alexays/Waybar)
- [Kitty](https://sw.kovidgoyal.net/kitty/)
- [Rofi](https://github.com/DaveDavenport/rofi)
- [Starship](https://starship.rs/)

---

**If you like this setup, give it a ⭐ on GitHub!**
