#!/bin/bash

WAYBAR_DIR="${HOME}/.config/waybar"
STATE_FILE="$WAYBAR_DIR/.current"

while true; do
    CHOICE=$(printf " \uf233 Waybar\n \uf1fc Themes\n \uf245 Cursors\n \uf0e4  Refresh Rate\n \uf26c  Resolution\n \uf0ac  Default Browser\n \uf07b  Default File Manager\n \uf013  System Reset" | rofi -dmenu -p "Settings" -theme-str 'configuration { show-icons: false; }')

    [ -z "$CHOICE" ] && exit 0

    case "$CHOICE" in
        *Cursors)
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

            [ -z "$CUR" ] && continue
            CUR=$(echo "$CUR" | sed 's/ \[active\]$//')
            "$HOME/.local/bin/cursor-switcher.sh" "$CUR"
            ;;
        *Themes)
            THEME=$(printf "Dark\nLight" | rofi -dmenu -p "Theme" -theme-str 'configuration { show-icons: false; }')
            [ -z "$THEME" ] && continue
            "$HOME/.local/bin/theme-switcher" "$THEME"
            ;;
        *Waybar)
            CONFIGS=()
            for f in "$WAYBAR_DIR"/config-*.jsonc; do
                [ -f "$f" ] || continue
                name=$(basename "$f" | sed 's/^config-//; s/\.jsonc$//')
                CONFIGS+=("$name")
            done

            [ ${#CONFIGS[@]} -eq 0 ] && continue

            current=$(cat "$STATE_FILE" 2>/dev/null | tr -d '[:space:]')

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

            [ -z "$SEL" ] && continue

            SEL=$(echo "$SEL" | sed 's/ \[active\]$//')

            echo "$SEL" > "$STATE_FILE"
            "$WAYBAR_DIR/launch.sh"
            ;;
        *Refresh\ Rate)
            "$HOME/.local/bin/refresh-rate-menu.sh"
            ;;
        *Resolution)
            "$HOME/.local/bin/resolution-menu.sh"
            ;;
        *Default\ Browser)
            current_browser=$(xdg-settings get default-web-browser 2>/dev/null)

            TMPFILE=$(mktemp)
            for dir in /usr/share/applications /usr/local/share/applications ~/.local/share/applications; do
                [ -d "$dir" ] || continue
                for f in "$dir"/*.desktop; do
                    [ -f "$f" ] || continue
                    grep -qi "x-scheme-handler/http" "$f" || continue
                    grep -qi "NoDisplay=true" "$f" && continue
                    name=$(grep "^Name=" "$f" 2>/dev/null | head -1 | cut -d= -f2-)
                    [ -z "$name" ] && continue
                    [[ "$name" == *"Settings"* ]] && continue
                    desktop=$(basename "$f")
                    if [[ "$desktop" == "$current_browser" ]]; then
                        echo "${name} [active]" >> "$TMPFILE"
                    else
                        echo "$name" >> "$TMPFILE"
                    fi
                done
            done

            [ ! -s "$TMPFILE" ] && { rm -f "$TMPFILE"; continue; }

            SEL=$(cat "$TMPFILE" | rofi -dmenu -p "Default Browser" -theme-str 'configuration { show-icons: false; }')
            rm -f "$TMPFILE"

            [ -z "$SEL" ] && continue
            SEL=$(echo "$SEL" | sed 's/ \[active\]$//')

            desktop_file=""
            for dir in /usr/share/applications /usr/local/share/applications ~/.local/share/applications; do
                [ -d "$dir" ] || continue
                for f in "$dir"/*.desktop; do
                    [ -f "$f" ] || continue
                    name=$(grep "^Name=" "$f" 2>/dev/null | head -1 | cut -d= -f2-)
                    if [[ "$name" == "$SEL" ]]; then
                        desktop_file=$(basename "$f")
                        break 2
                    fi
                done
            done

            [ -n "$desktop_file" ] && xdg-settings set default-web-browser "$desktop_file"
            ;;
        *Default\ File\ Manager)
            current_fm=$(xdg-mime query default inode/directory 2>/dev/null)

            TMPFILE=$(mktemp)
            for dir in /usr/share/applications /usr/local/share/applications ~/.local/share/applications; do
                [ -d "$dir" ] || continue
                for f in "$dir"/*.desktop; do
                    [ -f "$f" ] || continue
                    grep -qi "^Categories=.*FileManager" "$f" || continue
                    grep -qi "NoDisplay=true" "$f" && continue
                    name=$(grep "^Name=" "$f" 2>/dev/null | head -1 | cut -d= -f2-)
                    [ -z "$name" ] && continue
                    desktop=$(basename "$f")
                    if [[ "$desktop" == "$current_fm" ]]; then
                        echo "${name} [active]" >> "$TMPFILE"
                    else
                        echo "$name" >> "$TMPFILE"
                    fi
                done
            done

            [ ! -s "$TMPFILE" ] && { rm -f "$TMPFILE"; continue; }

            SEL=$(cat "$TMPFILE" | rofi -dmenu -p "Default File Manager" -theme-str 'configuration { show-icons: false; }')
            rm -f "$TMPFILE"

            [ -z "$SEL" ] && continue
            SEL=$(echo "$SEL" | sed 's/ \[active\]$//')

            desktop_file=""
            for dir in /usr/share/applications /usr/local/share/applications ~/.local/share/applications; do
                [ -d "$dir" ] || continue
                for f in "$dir"/*.desktop; do
                    [ -f "$f" ] || continue
                    name=$(grep "^Name=" "$f" 2>/dev/null | head -1 | cut -d= -f2-)
                    if [[ "$name" == "$SEL" ]]; then
                        desktop_file=$(basename "$f")
                        break 2
                    fi
                done
            done

            [ -n "$desktop_file" ] && xdg-mime default "$desktop_file" inode/directory x-scheme-handler/file
            ;;
        *System\ Reset)
            "$HOME/.local/bin/system-reset.sh"
            ;;
    esac
done
