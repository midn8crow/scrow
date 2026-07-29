#!/bin/bash
WALLPAPER="${1:-$(find /home/shadhin/Pictures/Wallpapers -type f \( -name "*.jpg" -o -name "*.png" -o -name "*.webp" \) | shuf -n1)}"

mkdir -p /home/shadhin/.cache/swaync

JSON=$(matugen image "$WALLPAPER" --prefer darkness -j hex 2>/dev/null)

get_color() {
  echo "$JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['colors']['$1']['default']['color'])"
}

cat > /home/shadhin/.cache/swaync/colors.css <<EOF
@define-color background $(get_color background);
@define-color foreground $(get_color on_background);
@define-color background-sec $(get_color surface_container);
@define-color color1 $(get_color primary);
@define-color color2 $(get_color error);
@define-color color3 $(get_color tertiary);
@define-color color4 $(get_color secondary);
@define-color color5 $(get_color primary_container);
@define-color color6 $(get_color secondary_container);
EOF

echo "Generated swaync colors.css"
cat /home/shadhin/.cache/swaync/colors.css
