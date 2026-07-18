#!/bin/bash
WALL_DIR="$HOME/Pictures/Wallpapers"
HISTORY_FILE="$HOME/.cache/wallpaper-history"
LIVE_ACTIVE=false

# Check if live wallpaper (mpvpaper) is running
if pgrep -f "mpvpaper" >/dev/null 2>&1; then
    LIVE_ACTIVE=true
fi

if [[ "$LIVE_ACTIVE" == true ]]; then
    # Live wallpaper: capture current screen frame
    SCREENSHOT="/tmp/color-pick-screen.png"
    grim -o "$(hyprctl monitors -j | python3 -c 'import sys,json; print(json.load(sys.stdin)[0]["name"])')" -t png "$SCREENSHOT" 2>/dev/null
    [[ ! -f "$SCREENSHOT" ]] && notify-send "Color Pick" "Failed to capture screen" && exit 1
    img_src="$SCREENSHOT"
else
    # Static wallpaper: get current wallpaper path
    idx=0
    [[ -f "$HISTORY_FILE" ]] && idx=$(cat "$HISTORY_FILE" 2>/dev/null) || idx=0
    mapfile -t walls < <(find "$WALL_DIR" -type f \( -name '*.jpg' -o -name '*.png' -o -name '*.jpeg' -o -name '*.webp' \) | sort)
    wall="${walls[$idx]:-}"
    [[ -z "$wall" ]] && notify-send "Color Pick" "No wallpaper found" && exit 1
    img_src="$wall"
fi

# Get screen dimensions
eval $(hyprctl monitors -j | python3 -c "
import sys, json
m = json.load(sys.stdin)[0]
w, h = m['width'], m['height']
sx, sy = m['x'], m['y']
scale = m['scale']
print(f'SW={w} SH={h} SX={sx} SY={sy} SCALE={scale}')
")

# Let user select a region
region=$(slurp -w 0 -b '#00000000' -c '#ffffff80' 2>/dev/null) || exit 1
# region format: X,Y WxH
x=$(echo "$region" | cut -d, -f1)
y=$(echo "$region" | cut -d, -f2 | cut -d' ' -f1)
w=$(echo "$region" | cut -d' ' -f2 | cut -dx -f1)
h=$(echo "$region" | cut -dx -f2)

# Get image dimensions
img_w=$(ffprobe -v error -select_streams v:0 -show_entries stream=width  -of csv=p=0 "$img_src")
img_h=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$img_src")

rw=$(echo "$img_w $SW $w" | awk '{ printf "%d", ($1 / $2) * $3 }')
rh=$(echo "$img_h $SH $h" | awk '{ printf "%d", ($1 / $2) * $3 }')
rx=$(echo "$img_w $SW $x" | awk '{ printf "%d", ($1 / $2) * $3 }')
ry=$(echo "$img_h $SH $y" | awk '{ printf "%d", ($1 / $2) * $3 }')

# Crop and resize
crop="/tmp/cava-color-crop.png"
ffmpeg -i "$img_src" -vf "crop=${rw}:${rh}:${rx}:${ry},scale=400:400:force_original_aspect_ratio=decrease" -y "$crop" 2>/dev/null

json=$(matugen image -j hex --mode dark --prefer lightness "$crop" 2>/dev/null)
[[ -z "$json" ]] && notify-send "Color Pick" "matugen failed" && exit 1

primary=$(echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['colors']['primary']['dark']['color'])")
on_primary=$(echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['colors']['on_primary']['dark']['color'])")
background=$(echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['colors']['background']['dark']['color'])")
on_background=$(echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['colors']['on_background']['dark']['color'])")
surface=$(echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['colors']['surface']['dark']['color'])")
surface_container=$(echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['colors']['surface_container']['dark']['color'])")
surface_variant=$(echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['colors']['surface_variant']['dark']['color'])")
on_surface=$(echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['colors']['on_surface']['dark']['color'])")
on_surface_variant=$(echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['colors']['on_surface_variant']['dark']['color'])")
error=$(echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['colors']['error']['dark']['color'])")
tertiary=$(echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['colors']['tertiary']['dark']['color'])")
secondary=$(echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['colors']['secondary']['dark']['color'])")
primary_container=$(echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['colors']['primary_container']['dark']['color'])")
secondary_container=$(echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['colors']['secondary_container']['dark']['color'])")
outline=$(echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['colors']['outline']['dark']['color'])")

module_rgb=$(python3 -c "c='$surface_container'; print(f'{int(c[1:3],16)},{int(c[3:5],16)},{int(c[5:7],16)}')")
active_hex=$(python3 -c "print('$primary'[1:])")
inactive_hex=$(python3 -c "print('$on_surface_variant'[1:])")

hex_to_rgba() { python3 -c "c='$1'; print(f'rgba({int(c[1:3],16)}, {int(c[3:5],16)}, {int(c[5:7],16)}, $2)')"; }

# Waybar colors
cat > "$HOME/.config/waybar/colors/colors.css" << EOF
@define-color module-bg     rgba($module_rgb, 0.9);
@define-color tooltip-bg    @module-bg;
@define-color inactive      $on_surface_variant;
@define-color fg            $on_surface;
@define-color workspace-fg  @fg;
@define-color highlight     $primary;
@define-color red           $error;
@define-color blue          $primary;
@define-color yellow        $tertiary;
@define-color green         $secondary;
EOF

# Hyprland borders
cat > "$HOME/.config/hypr/modules/borders.lua" << BEOF
hl.config({
    general = {
        col = {
            active_border   = "rgba(${active_hex}ee)",
            inactive_border = "rgba(${inactive_hex}aa)",
        },
    },
})
BEOF
hyprctl eval "hl.config({ general = { col = { active_border = \"rgba(${active_hex}ee)\", inactive_border = \"rgba(${inactive_hex}aa)\" } } })"

# Rofi colors (scrow style)
bg2=$(python3 -c "
bg='${background}'
sc='${surface_container}'
r0,g0,b0=int(bg[1:3],16),int(bg[3:5],16),int(bg[5:7],16)
r1,g1,b1=int(sc[1:3],16),int(sc[3:5],16),int(sc[5:7],16)
print(f'#{(r0+r1*2)//3:02x}{(g0+g1*2)//3:02x}{(b0+b1*2)//3:02x}')
")
cat > "$HOME/.config/rofi/colors.rasi" << ROFI
* {
    bg0: ${background}66;
    bg1: ${surface_container}66;
    bg2: ${bg2}66;
    fg0: ${on_background};
    fg1: ${on_surface_variant};

    red: ${error};
    green: ${secondary};
    yellow: ${tertiary};
    blue: ${primary};
    purple: ${primary};
    aqua: ${primary_container};

    highlight: ${primary}33;
}
ROFI

# Cava foreground
sed -i "s/^foreground = .*/foreground = '${primary}'/" "$HOME/.config/cava/config"

# Mako colors (Glass Dynamic Island)
cat > "$HOME/.config/mako/mako-colors.ini" << MEOF
# Auto-generated by color picker - DO NOT EDIT
background-color=${surface}cc
text-color=${on_surface}
border-color=#ffffff22
progress-color=${primary_container}ff
MEOF
killall mako 2>/dev/null; sleep 0.3; nohup mako > /dev/null 2>&1 &

# Kitty colors
cat > "$HOME/.config/kitty/kitty-colors.conf" << KEOF
background ${background}
foreground ${on_background}
cursor ${on_background}
cursor_text_color ${background}
selection_background ${primary}
selection_foreground ${background}
url_color ${tertiary}
active_tab_foreground ${background}
active_tab_background ${primary}
inactive_tab_foreground ${on_background}
inactive_tab_background ${surface_container}
color0 ${background}
color1 ${error}
color2 ${secondary}
color3 ${tertiary}
color4 ${primary}
color5 ${surface_variant}
color6 ${primary_container}
color7 ${on_background}
color8 ${surface_container}
color9 ${error}
color10 ${secondary}
color11 ${tertiary}
color12 ${primary}
color13 ${surface_variant}
color14 ${primary_container}
color15 ${on_background}
KEOF

# Firefox colors
cat > "$HOME/.config/firefox/colors.css" << FEOF
/* Auto-generated by color picker */
:root {
  --md-sys-color-primary: ${primary};
  --md-sys-color-on_primary: ${on_primary};
  --md-sys-color-secondary: ${secondary};
  --md-sys-color-on_secondary: ${on_background};
  --md-sys-color-tertiary: ${tertiary};
  --md-sys-color-on_tertiary: ${on_background};
  --md-sys-color-error: ${error};
  --md-sys-color-on_error: ${on_background};
  --md-sys-color-background: ${background};
  --md-sys-color-on_background: ${on_background};
  --md-sys-color-surface: ${surface};
  --md-sys-color-on_surface: ${on_surface};
  --md-sys-color-surface_variant: ${surface_variant};
  --md-sys-color-on_surface_variant: ${on_surface_variant};
  --md-sys-color-outline: ${outline};
  --md-sys-color-surface_container: ${surface_container};
}
FEOF

# Copy to Firefox profile
cp "$HOME/.config/firefox/colors.css" "$HOME/.mozilla/firefox/efypgmxk.default-release/chrome/colors.css" 2>/dev/null

# Reload waybar
killall -SIGUSR2 waybar 2>/dev/null || (killall waybar 2>/dev/null; sleep 0.5; waybar &)

notify-send "Color Pick" "Colors extracted from selected region"
