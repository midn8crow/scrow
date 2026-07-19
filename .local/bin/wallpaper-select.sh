#!/bin/bash
PATH="/usr/bin:$HOME/.local/bin:$PATH"

WALL_DIR="$HOME/Pictures/Wallpapers"

mapfile -t walls < <(find "$WALL_DIR" -maxdepth 1 -type f \( -name '*.jpg' -o -name '*.png' -o -name '*.jpeg' -o -name '*.webp' \) | sort)
count=${#walls[@]}

if [[ $count -eq 0 ]]; then
    notify-send "Wallpaper" "No wallpapers found in $WALL_DIR"
    exit 1
fi

THUMB_DIR="$HOME/.cache/wallpaper-thumbs"
mkdir -p "$THUMB_DIR"

TMPFILE=$(mktemp)
for w in "${walls[@]}"; do
    name=$(basename "$w")
    thumb="$THUMB_DIR/$name"
    if [ ! -f "$thumb" ]; then
        ffmpegthumbnailer -i "$w" -o "$thumb" -s 256 -q 6 2>/dev/null
    fi
    printf '%s\0icon\x1f%s\n' "$name" "$thumb" >> "$TMPFILE"
done

SEL=$(rofi -dmenu -i -p "Wallpaper" -show-icons -icon-theme "Papirus-Dark" -theme "$HOME/.config/rofi/wallpaper-picker.rasi" < "$TMPFILE")
rm -f "$TMPFILE"

[ -z "$SEL" ] && exit 0

WALL=""
for w in "${walls[@]}"; do
    [[ "$(basename "$w")" == "$SEL" ]] && WALL="$w" && break
done
[ -z "$WALL" ] && exit 0

pgrep -x awww-daemon >/dev/null || awww-daemon &
sleep 0.2
awww img "$WALL" --transition-fps 60 --transition-type grow --transition-duration 1

pkill -f "mpvpaper" 2>/dev/null

json=$(matugen image -j hex --mode dark --prefer lightness "$WALL" 2>/dev/null)
[[ -z "$json" ]] && exit 1

primary=$(echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['colors']['primary']['dark']['color'])")
on_primary=$(echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['colors']['on_primary']['dark']['color'])")
secondary=$(echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['colors']['secondary']['dark']['color'])")
on_secondary=$(echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['colors']['on_secondary']['dark']['color'])")
tertiary=$(echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['colors']['tertiary']['dark']['color'])")
on_tertiary=$(echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['colors']['on_tertiary']['dark']['color'])")
error=$(echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['colors']['error']['dark']['color'])")
on_error=$(echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['colors']['on_error']['dark']['color'])")
background=$(echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['colors']['background']['dark']['color'])")
on_background=$(echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['colors']['on_background']['dark']['color'])")
surface=$(echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['colors']['surface']['dark']['color'])")
on_surface=$(echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['colors']['on_surface']['dark']['color'])")
surface_variant=$(echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['colors']['surface_variant']['dark']['color'])")
on_surface_variant=$(echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['colors']['on_surface_variant']['dark']['color'])")
outline=$(echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['colors']['outline']['dark']['color'])")
surface_container=$(echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['colors']['surface_container']['dark']['color'])")
primary_container=$(echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['colors']['primary_container']['dark']['color'])")
secondary_container=$(echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['colors']['secondary_container']['dark']['color'])")

module_rgb=$(python3 -c "c='$surface_container'; print(f'{int(c[1:3],16)},{int(c[3:5],16)},{int(c[5:7],16)}')")
active_hex=$(python3 -c "print('$primary'[1:])")
inactive_hex=$(python3 -c "print('$on_surface_variant'[1:])")

CSS_FILE="$HOME/.config/waybar/colors/colors.css"
cat > "$CSS_FILE" << EOF
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

killall -SIGUSR2 waybar 2>/dev/null || (killall waybar 2>/dev/null; sleep 0.5; waybar &)

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

cat > "$HOME/.config/qt6ct/qt6ct.conf" << QEOF
[Appearance]
color_scheme_path=
icon_theme=$(grep gtk-icon-theme-name "$HOME/.config/gtk-3.0/settings.ini" | cut -d= -f2)
style=Fusion
color_scheme_type=2
QEOF

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

FF_CHROME=$(find "$HOME/.mozilla/firefox/" -maxdepth 1 -name "*.default-release" -type d -exec echo "{}/chrome" \; 2>/dev/null | head -1)
if [ -n "$FF_CHROME" ]; then
cat > "$FF_CHROME/colors.css" << FFEOF
:root {
  --md-sys-color-primary: ${primary};
  --md-sys-color-on_primary: ${on_primary};
  --md-sys-color-secondary: ${secondary};
  --md-sys-color-on_secondary: ${on_secondary};
  --md-sys-color-tertiary: ${tertiary};
  --md-sys-color-on_tertiary: ${on_tertiary};
  --md-sys-color-error: ${error};
  --md-sys-color-on_error: ${on_error};
  --md-sys-color-background: ${background};
  --md-sys-color-on_background: ${on_background};
  --md-sys-color-surface: ${surface};
  --md-sys-color-on_surface: ${on_surface};
  --md-sys-color-surface_variant: ${surface_variant};
  --md-sys-color-on_surface_variant: ${on_surface_variant};
  --md-sys-color-outline: ${outline};
  --md-sys-color-surface_container: ${surface_container};
}
FFEOF
fi

ZEN_CHROME=$(find "$HOME/.config/zen/" -maxdepth 1 -name "*.Default (release)" -type d -exec echo "{}/chrome" \; 2>/dev/null | head -1)
if [ -n "$ZEN_CHROME" ]; then
cat > "$ZEN_CHROME/colors.css" << ZENEOF
:root {
  --md-sys-color-primary: ${primary};
  --md-sys-color-on_primary: ${on_primary};
  --md-sys-color-secondary: ${secondary};
  --md-sys-color-on_secondary: ${on_secondary};
  --md-sys-color-tertiary: ${tertiary};
  --md-sys-color-on_tertiary: ${on_tertiary};
  --md-sys-color-error: ${error};
  --md-sys-color-on_error: ${on_error};
  --md-sys-color-background: ${background};
  --md-sys-color-on_background: ${on_background};
  --md-sys-color-surface: ${surface};
  --md-sys-color-on_surface: ${on_surface};
  --md-sys-color-surface_variant: ${surface_variant};
  --md-sys-color-on_surface_variant: ${on_surface_variant};
  --md-sys-color-outline: ${outline};
  --md-sys-color-surface_container: ${surface_container};
}
ZENEOF
fi

mkdir -p "$HOME/.config/brave-theme"
hex_to_rgb() { python3 -c "c='$1'; print(f'{int(c[1:3],16)},{int(c[3:5],16)},{int(c[5:7],16)}')"; }
rgb_frame=$(hex_to_rgb "$background")
rgb_toolbar=$(hex_to_rgb "$surface_container")
rgb_tab_text=$(hex_to_rgb "$on_surface")
rgb_toolbar_text=$(hex_to_rgb "$on_surface")
rgb_bookmark=$(hex_to_rgb "$on_surface")
rgb_ntp_bg=$(hex_to_rgb "$background")
rgb_ntp_text=$(hex_to_rgb "$on_background")
rgb_button=$(hex_to_rgb "$surface_container")
cat > "$HOME/.config/brave-theme/manifest.json" << BRAVEEOF
{
  "manifest_version": 2,
  "name": "Matugen Theme",
  "version": "1.0",
  "description": "Auto-generated matugen theme",
  "theme": {
    "colors": {
      "frame": [${rgb_frame}],
      "toolbar": [${rgb_toolbar}],
      "tab_text": [${rgb_tab_text}],
      "toolbar_text": [${rgb_toolbar_text}],
      "bookmark_text": [${rgb_bookmark}],
      "ntp_background": [${rgb_ntp_bg}],
      "ntp_text": [${rgb_ntp_text}],
      "button_background": [${rgb_button}]
    }
  }
}
BRAVEEOF

mkdir -p "$HOME/.cache/mako"
tertiary_dark=$(echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['colors']['tertiary']['dark']['color'])")
cat > "$HOME/.cache/mako/colors.css" << SWEOF
@define-color background ${background};
@define-color foreground ${on_background};
@define-color background-sec ${surface_container};
@define-color color1 ${primary};
@define-color color2 ${error};
@define-color color3 ${tertiary_dark};
@define-color color4 ${secondary};
@define-color color5 ${primary_container};
@define-color color6 ${secondary_container};
SWEOF
killall mako 2>/dev/null; sleep 0.3; nohup mako > /dev/null 2>&1 &

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

sed -i "s/^foreground = .*/foreground = '${primary}'/" "$HOME/.config/cava/config"
