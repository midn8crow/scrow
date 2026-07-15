#!/bin/bash

WAYBAR_DIR="${HOME}/.config/waybar"
STATE_FILE="$WAYBAR_DIR/.current"

CHOICE=$(printf "Waybar\nThemes\nCursors\nRefresh Rate\nResolution\nSystem Reset" | rofi -dmenu -p "Menu" -theme-str 'configuration { show-icons: false; }')

[ -z "$CHOICE" ] && exit 0

case "$CHOICE" in
    Cursors)
        CURSOR_STATE="$HOME/.config/hypr/.cursor-theme"
        current_cursor=$(cat "$CURSOR_STATE" 2>/dev/null)

        declare -A cursor_map=(
            ["Bibata-Modern-Classic"]="ITSME (Recommended)"
            ["Bibata-Modern-Ice"]="Bibata Modern Ice"
            ["Bibata-Original-Classic"]="Bibata Original Classic"
            ["phinger-cursors-dark"]="Phinger Dark"
            ["phinger-cursors-light"]="Phinger Light"
            ["Minecraft-Animated"]="Minecraft Animated"
            ["Windows11Dark"]="Windows 11 Dark"
        )

        OPTIONS=("ITSME (Recommended)" "Bibata Modern Ice" "Bibata Original Classic" "Phinger Dark" "Phinger Light" "Minecraft Animated" "Windows 11 Dark")

        TMPFILE=$(mktemp)
        for opt in "${OPTIONS[@]}"; do
            theme_name=""
            for key in "${!cursor_map[@]}"; do
                if [[ "${cursor_map[$key]}" == "$opt" ]]; then
                    theme_name="$key"
                    break
                fi
            done
            if [[ "$theme_name" == "$current_cursor" ]]; then
                echo "${opt} [active]" >> "$TMPFILE"
            else
                echo "$opt" >> "$TMPFILE"
            fi
        done

        CUR=$(cat "$TMPFILE" | rofi -dmenu -p "Cursor Theme" -theme-str 'configuration { show-icons: false; }')
        rm -f "$TMPFILE"

        [ -z "$CUR" ] && exit 0
        CUR=$(echo "$CUR" | sed 's/ \[active\]$//')
        "$HOME/.local/bin/cursor-switcher.sh" "$CUR"
        ;;
    Themes)
        THEME=$(printf "Dark\nLight" | rofi -dmenu -p "Theme" -theme-str 'configuration { show-icons: false; }')
        [ -z "$THEME" ] && exit 0
        "$HOME/.local/bin/theme-switcher" "$THEME"
        ;;
    Waybar)
        # Auto-detect waybar configs
        CONFIGS=()
        for f in "$WAYBAR_DIR"/config-*.jsonc; do
            [ -f "$f" ] || continue
            name=$(basename "$f" | sed 's/^config-//; s/\.jsonc$//')
            CONFIGS+=("$name")
        done

        [ ${#CONFIGS[@]} -eq 0 ] && exit 0

        current=$(cat "$STATE_FILE" 2>/dev/null | tr -d '[:space:]')

        # Build list with marker on current
        TMPFILE=$(mktemp)
        for name in "${CONFIGS[@]}"; do
            if [[ "$name" == "$current" ]]; then
                echo "${name} [active]" >> "$TMPFILE"
            else
                echo "$name" >> "$TMPFILE"
            fi
        done

        SEL=$(cat "$TMPFILE" | rofi -dmenu -p "Waybar" -theme-str 'configuration { show-icons: false; }')
        rm -f "$TMPFILE"

        [ -z "$SEL" ] && exit 0

        # Strip marker
        SEL=$(echo "$SEL" | sed 's/ \[active\]$//')

        echo "$SEL" > "$STATE_FILE"
        exec "$WAYBAR_DIR/launch.sh"
        ;;
    Refresh\ Rate)
        "$HOME/.local/bin/refresh-rate-menu.sh"
        ;;
    Resolution)
        "$HOME/.local/bin/resolution-menu.sh"
        ;;
    System\ Reset)
        "$HOME/.local/bin/system-reset.sh"
        ;;
esac
