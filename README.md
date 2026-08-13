







https://github.com/user-attachments/assets/519495e8-0f89-48e2-8342-a281e4031e84











# Hyprland Dotfiles

<h1 align="center">
  <b>🔀 Per-Workspace Layout Switching 🔀</b><br>
  <sub>Switch between Hyprland & Niri tiling styles with one keybind</sub><br>
  <code>SUPER + SHIFT + L</code>
</h1>

A complete, ready-to-use Hyprland configuration for Arch Linux. One command to install everything.

![Hyprland](https://img.shields.io/badge/Hyprland-Wayland-5e81ac?style=for-the-badge&logo=hyprland&logoColor=white)
![Arch Linux](https://img.shields.io/badge/Arch%20Linux-1793D1?style=for-the-badge&logo=archlinux&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-yellow?style=for-the-badge)

## What's Included

- **Hyprland** - Wayland compositor with smooth animations
- **Waybar** - Status bar with multiple themes (vertical/horizontal)
- **Kitty** - Terminal with custom colors and fonts
- **Rofi** - App launcher and menus
- **Mako** - Notification daemon
- **Zsh** - Shell with Starship prompt
- **Theming** - Automatic color generation

## Quick Install

### One-Line Install

```bash
curl -fsSL https://raw.githubusercontent.com/midn8crow/scrow/main/bootstrap.sh | bash
```

This fetches SCROW, starts the installer and opens the SCROW Manager.

### Development / Local Install

```bash
git clone https://github.com/midn8crow/scrow.git
cd scrow
./install.sh
```

### After Installation

Run `scrow` from any directory to open the SCROW Manager again.

### SCROW Manager

| Option | Description |
|--------|-------------|
| **Full Installation** (Recommended) | Complete official SCROW environment |
| **Custom Installation** | Choose individual components |
| **Components** | Install / reinstall / repair individual components |
| **Update SCROW** | Update to a newer SCROW version |
| **Restore** | Return to a previous automatic backup |
| **Reset SCROW** | Restore official files (overwrites local edits) |
| **Doctor / Repair** | Detect and safely repair problems |
| **Uninstall SCROW** | Safely remove SCROW-managed content |

### Automatic Backups

Before any operation that can change SCROW-managed files, SCROW automatically creates a backup in:

```
~/.local/share/scrow/backups/
```

Backups are never deleted automatically. Use **Restore** in the manager to return to a previous backup. Each backup records the SCROW version, manifest, symlinks and installed state.

### Command Line

```bash
./install.sh --help        # Show help
./install.sh --version     # Show version
./install.sh --dry-run     # Preview every change without touching the system
```

## What the Installer Does

1. **Checks the system** (Arch Linux, dependencies)
2. **Detects your hardware** (GPU, laptop/desktop)
3. **Installs required packages** (pacman + AUR via paru)
4. **Installs GPU drivers** (AMD/Intel/NVIDIA only as needed)
5. **Creates a safety backup** of existing configuration
6. **Deploys all configs** and creates symlinks
7. **Configures your shell** (Zsh + Starship)
8. **Enables SCROW services** (NetworkManager, Bluetooth, Audio)
9. **Sets up theming** (GTK, Qt, Fonts)
10. **Verifies the installation**

## Features

### Per-Workspace Layout Switching

**Each workspace gets its own tiling layout.** Switch between different tiling styles on the fly:

| Key | Action |
|-----|--------|
| `SUPER + SHIFT + L` | Toggle between Hyprland & Niri layout |

- **Hyprland style** - Classic dynamic tiling
- **Niri style** - Scrollable column-based tiling
- Change layout per workspace without affecting others

### Multiple Waybar Themes

Switch between different waybar styles:

```bash
# Next theme
ALT + SHIFT + W

# Previous theme
ALT + W
```

Available themes:
- Default (scrowland)
- cxorz
- Athena
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
| `SUPER + SHIFT + L` | Toggle Layout (Hyprland/Niri) |

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
| `scrow-menu.sh` | Scrow menu |
| `powermenu.sh` | Power/logout menu |
| `force-kill.sh` | Force kill window |
| `keybinds` | Show keybinds |

## Package List

### Core Packages

```
hyprland hyprlock hypridle waybar kitty rofi mako swww-daemon
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
mako
```

### Wallpaper not changing

SCROW applies the default wallpaper automatically on login and self-heals a
stale/removed wallpaper index, so no manual cache clearing is needed. To
re-apply manually:

```bash
~/.local/bin/wallpaper-switch.sh restore
```

The default SCROW wallpaper is installed with SCROW and lives in
`~/Pictures/Wallpapers/`. Add more wallpapers there and switch them with
`SUPER + W`.

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

## Hardware Fixes

### Keyboard Backlight (Not Supported on Linux)

Some keyboards don't support Linux keyboard backlight control. Use this script to force the scrolllock LED on:

```bash
#!/bin/bash
while true; do
    LED_DIR=$(find /sys/class/leds/ -maxdepth 1 -name "*scrolllock" 2>/dev/null | head -1)
    if [ -n "$LED_DIR" ] && [ -f "$LED_DIR/brightness" ]; then
        echo 1 > "$LED_DIR/brightness" 2>/dev/null
    fi
    sleep 0.005
done
```

Save as `~/.local/bin/kbd-backlight-keep.sh` and run:

```bash
chmod +x ~/.local/bin/kbd-backlight-keep.sh
~/.local/bin/kbd-backlight-keep.sh &
```

To auto-start, add to `~/.config/hypr/modules/autostart.lua`:

```lua
hl.exec_cmd("bash -c '$HOME/.local/bin/kbd-backlight-keep.sh &'")
```

## Uninstall

Open the SCROW Manager and choose **Uninstall SCROW**:

```bash
scrow
```

Uninstall removes only SCROW-managed files, symlinks, services and the `scrow` command. Your automatic backups are kept, so you can restore a previous state by cloning the repository and running `./install.sh` → **Restore**.

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
