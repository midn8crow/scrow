#!/bin/bash

WAYBAR_DIR="${HOME}/.config/waybar"
STATE_FILE="$WAYBAR_DIR/.current"

while true; do
    CHOICE=$(printf "Waybar\nThemes\nCursors\nRefresh Rate\nResolution\nDefault Browser\nDefault File Manager\nSystem Reset" | rofi -dmenu -p "Settings" -theme-str 'configuration { show-icons: false; }')

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

            [ -z "$CUR" ] && continue
            CUR=$(echo "$CUR" | sed 's/ \[active\]$//')
            "$HOME/.local/bin/cursor-switcher.sh" "$CUR"
            ;;
        Themes)
            THEME=$(printf "Dark\nLight" | rofi -dmenu -p "Theme" -theme-str 'configuration { show-icons: false; }')
            [ -z "$THEME" ] && continue
            "$HOME/.local/bin/theme-switcher" "$THEME"
            ;;
        Waybar)
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
        Refresh\ Rate)
            "$HOME/.local/bin/refresh-rate-menu.sh"
            ;;
        Resolution)
            "$HOME/.local/bin/resolution-menu.sh"
            ;;
        Default\ Browser)
            declare -A browser_map=(
                ["brave-browser.desktop"]="Brave"
                ["firefox.desktop"]="Firefox"
                ["zen.desktop"]="Zen Browser"
                ["org.torproject.torbrowser-launcher.desktop"]="Tor Browser"
            )

            current_browser=$(xdg-settings get default-web-browser 2>/dev/null)

            OPTIONS=("Brave" "Firefox" "Zen Browser" "Tor Browser")

            TMPFILE=$(mktemp)
            for opt in "${OPTIONS[@]}"; do
                desktop_file=""
                for key in "${!browser_map[@]}"; do
                    if [[ "${browser_map[$key]}" == "$opt" ]]; then
                        desktop_file="$key"
                        break
                    fi
                done
                if [[ "$desktop_file" == "$current_browser" ]]; then
                    echo "${opt} [active]" >> "$TMPFILE"
                else
                    echo "$opt" >> "$TMPFILE"
                fi
            done

            SEL=$(cat "$TMPFILE" | rofi -dmenu -p "Default Browser" -theme-str 'configuration { show-icons: false; }')
            rm -f "$TMPFILE"

            [ -z "$SEL" ] && continue
            SEL=$(echo "$SEL" | sed 's/ \[active\]$//')

            desktop_file=""
            for key in "${!browser_map[@]}"; do
                if [[ "${browser_map[$key]}" == "$SEL" ]]; then
                    desktop_file="$key"
                    break
                fi
            done

            xdg-settings set default-web-browser "$desktop_file"
            ;;
        Default\ File\ Manager)
            declare -A fm_map=(
                ["thunar.desktop"]="Thunar"
                ["yazi.desktop"]="Yazi"
            )

            current_fm=$(xdg-mime query default inode/directory 2>/dev/null)

            OPTIONS=("Thunar" "Yazi")

            TMPFILE=$(mktemp)
            for opt in "${OPTIONS[@]}"; do
                desktop_file=""
                for key in "${!fm_map[@]}"; do
                    if [[ "${fm_map[$key]}" == "$opt" ]]; then
                        desktop_file="$key"
                        break
                    fi
                done
                if [[ "$desktop_file" == "$current_fm" ]]; then
                    echo "${opt} [active]" >> "$TMPFILE"
                else
                    echo "$opt" >> "$TMPFILE"
                fi
            done

            SEL=$(cat "$TMPFILE" | rofi -dmenu -p "Default File Manager" -theme-str 'configuration { show-icons: false; }')
            rm -f "$TMPFILE"

            [ -z "$SEL" ] && continue
            SEL=$(echo "$SEL" | sed 's/ \[active\]$//')

            desktop_file=""
            for key in "${!fm_map[@]}"; do
                if [[ "${fm_map[$key]}" == "$SEL" ]]; then
                    desktop_file="$key"
                    break
                fi
            done

            xdg-mime default "$desktop_file" inode/directory x-scheme-handler/file
            ;;
        System\ Reset)
            "$HOME/.local/bin/system-reset.sh"
            ;;
    esac
done
