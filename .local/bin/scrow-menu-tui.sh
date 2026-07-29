#!/bin/bash

WAYBAR_DIR="${HOME}/.config/waybar"
STATE_FILE="$WAYBAR_DIR/.current"

main_menu() {
    if mountpoint -q "$HOME/gdrive" 2>/dev/null; then
        RCLONE_SUFFIX=" [active]"
    else
        RCLONE_SUFFIX=""
    fi

    printf " \uf023  Security\n \uf185  Power Profile\n \uf2ed  System Cleanup\n \uf233  Waybar\n \uf1fc  Themes\n \uf245  Cursors\n \uf0e4  Refresh Rate\n \uf26c  Resolution\n \uf0ac  Default Browser\n \uf07b  Default File Manager\n \uf11c  Keybinds\n \uf304  Update Mirrors\n \uf11b  Games\n \uf013  System Reset\n \uf019  Rclone Mount${RCLONE_SUFFIX}\n \uf04c  WayClick" | fzf --cycle --prompt="Scrow Menu > " --reverse --border --ansi
}

pick_cursor() {
    CURSOR_STATE="$HOME/.config/hypr/.cursor-theme"

    declare -A name_to_theme=(
        ["SCROW (Recommended)"]="Bibata-Modern-Classic"
        ["Bibata Modern Ice"]="Bibata-Modern-Ice"
        ["Bibata Original Classic"]="Bibata-Original-Classic"
        ["Phinger Dark"]="phinger-cursors-dark"
        ["Phinger Light"]="phinger-cursors-light"
        ["Minecraft Animated"]="Minecraft-Animated"
        ["Windows 11 Dark"]="Windows11Dark"
    )

    NAMES=("SCROW (Recommended)" "Bibata Modern Ice" "Bibata Original Classic" "Phinger Dark" "Phinger Light" "Minecraft Animated" "Windows 11 Dark")

    while true; do
        current_cursor=$(cat "$CURSOR_STATE" 2>/dev/null)

        ITEMS=()
        for name in "${NAMES[@]}"; do
            if [[ "${name_to_theme[$name]}" == "$current_cursor" ]]; then
                ITEMS+=("${name} [active]")
            else
                ITEMS+=("$name")
            fi
        done
        ITEMS+=("Back")

        CUR=$(printf "%s\n" "${ITEMS[@]}" | fzf --cycle --prompt="Cursor Theme > " --reverse --border --ansi)

        [ -z "$CUR" ] || [[ "$CUR" == "Back" ]] && return
        CUR="${CUR% \[active\]}"
        "$HOME/.local/bin/cursor-switcher.sh" "$CUR"
    done
}

pick_waybar() {
    CONFIGS=()
    for f in "$WAYBAR_DIR"/config-*.jsonc; do
        [ -f "$f" ] || continue
        name=$(basename "$f" | sed 's/^config-//; s/\.jsonc$//')
        CONFIGS+=("$name")
    done

    [ ${#CONFIGS[@]} -eq 0 ] && return

    while true; do
        current=$(cat "$STATE_FILE" 2>/dev/null | tr -d '[:space:]')

        TMPFILE=$(mktemp)
        for name in "${CONFIGS[@]}"; do
            if [[ "$name" == "$current" ]]; then
                echo "${name} [active]" >> "$TMPFILE"
            else
                echo "$name" >> "$TMPFILE"
            fi
        done
        echo "Back" >> "$TMPFILE"

        SEL=$(cat "$TMPFILE" | fzf --cycle --prompt="Waybar > " --reverse --border --ansi)
        rm -f "$TMPFILE"

        [ -z "$SEL" ] && return
        [[ "$SEL" == "Back" ]] && return

        SEL=$(echo "$SEL" | sed 's/ \[active\]$//')

        echo "$SEL" > "$STATE_FILE"
        "$WAYBAR_DIR/launch.sh" >/dev/null 2>&1
    done
}

pick_browser() {
    while true; do
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

        [ ! -s "$TMPFILE" ] && { rm -f "$TMPFILE"; return; }
        echo "Back" >> "$TMPFILE"

        SEL=$(cat "$TMPFILE" | fzf --cycle --prompt="Default Browser > " --reverse --border --ansi)
        rm -f "$TMPFILE"

        [ -z "$SEL" ] && return
        [[ "$SEL" == "Back" ]] && return
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

        [ -n "$desktop_file" ] && xdg-settings set default-web-browser "$desktop_file" 2>/dev/null
    done
}

pick_filemanager() {
    while true; do
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

        [ ! -s "$TMPFILE" ] && { rm -f "$TMPFILE"; return; }
        echo "Back" >> "$TMPFILE"

        SEL=$(cat "$TMPFILE" | fzf --cycle --prompt="Default File Manager > " --reverse --border --ansi)
        rm -f "$TMPFILE"

        [ -z "$SEL" ] && return
        [[ "$SEL" == "Back" ]] && return
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

        [ -n "$desktop_file" ] && xdg-mime default "$desktop_file" inode/directory x-scheme-handler/file 2>/dev/null
    done
}


pick_power_profile() {
    while true; do
        current_profile=$(powerprofilesctl get 2>/dev/null)

        OPTIONS=()
        for p in performance balanced power-saver; do
            if [[ "$p" == "$current_profile" ]]; then
                OPTIONS+=("${p} [active]")
            else
                OPTIONS+=("$p")
            fi
        done
        OPTIONS+=("Back")

        SEL=$(printf "%s\n" "${OPTIONS[@]}" | fzf --cycle --prompt="Power Profile > " --reverse --border --ansi)
        [ -z "$SEL" ] && return
        [[ "$SEL" == "Back" ]] && return
        SEL=$(echo "$SEL" | sed 's/ \[active\]$//')

        powerprofilesctl set "$SEL"
        notify-send -u low "Power Profile" "Switched to $SEL"
    done
}

pick_security() {
    while true; do
        SECURITY_CHOICE=$(printf " \uf10c  Check AUR Package\n \uf1e2  Security Audit\n \uf0e4  System Monitor\n \uf0ac  Apply Security Hardening\n \uf121  Show Commands\n \uf013  Back" | fzf --cycle --prompt="Security > " --reverse --border --ansi)

        [ -z "$SECURITY_CHOICE" ] && return
        [[ "$SECURITY_CHOICE" == *"Back"* ]] && return

        case "$SECURITY_CHOICE" in
            *Security\ Audit)
                printf '\033[2J\033[H'
                $HOME/security-hardening/audit.sh
                echo ""
                echo "Press any key to continue..."
                read -n 1
                ;;
            *System\ Monitor)
                printf '\033[2J\033[H'
                $HOME/security-hardening/monitor.sh
                echo ""
                echo "Press any key to continue..."
                read -n 1
                ;;
            *Check\ AUR\ Package)
                read -p "Enter package name: " PKG
                [ -z "$PKG" ] && continue
                printf '\033[2J\033[H'
                $HOME/security-hardening/aur-check.sh "$PKG"
                ;;
            *Apply\ Security\ Hardening)
                printf '\033[2J\033[H'
                sudo "$HOME/security-hardening/harden.sh"
                echo ""
                echo "Press any key to continue..."
                read -n 1
                ;;
            *Show\ Commands)
                printf '\033[2J\033[H'
                echo "=========================================="
                echo "       SECURITY COMMANDS REFERENCE"
                echo "=========================================="
                echo ""
                echo "AUDIT & MONITORING:"
                echo "  ~/security-hardening/audit.sh"
                echo "    - Scans system for security issues"
                echo ""
                echo "  ~/security-hardening/monitor.sh"
                echo "    - Real-time security monitoring"
                echo ""
                echo "AUR PACKAGE SCANNING:"
                echo "  ~/security-hardening/aur-check.sh <package-name>"
                echo "    - Scans AUR package for malware"
                echo ""
                echo "SYSTEM HARDENING (requires sudo):"
                echo "  sudo ~/security-hardening/harden.sh"
                echo ""
                echo "=========================================="
                echo "Press any key to continue..."
                read -n 1
                ;;
        esac
    done
}

pick_games() {
    while true; do
        GAME=$(printf " \uf11b  Chess\n \uf013  Back" | fzf --cycle --prompt="Games > " --reverse --border --ansi)
        [ -z "$GAME" ] && return
        [[ "$GAME" == *"Back"* ]] && return
        case "$GAME" in
            *Chess)
                clear
                chess-tui -e /usr/bin/stockfish
                echo "Press any key to continue..."
                read -n 1
                ;;
        esac
    done
}

pick_wayclick() {
    WAYCLICK_STATE_FILE="$HOME/.config/dusky/settings/wayclick"
    WAYCLICK_VOLUME_FILE="$HOME/.config/wayclick/volume"

    [ ! -f "$WAYCLICK_VOLUME_FILE" ] && echo "100" > "$WAYCLICK_VOLUME_FILE"

    while true; do
        current_state=$(cat "$WAYCLICK_STATE_FILE" 2>/dev/null || echo "False")
        current_volume=$(cat "$WAYCLICK_VOLUME_FILE" 2>/dev/null || echo "100")

        if [[ "$current_state" == "True" ]]; then
            toggle_display="Toggle WayClick        ON"
        else
            toggle_display="Toggle WayClick        OFF"
        fi

        OPTIONS=("$toggle_display" "Change Volume")
        OPTIONS+=("Back")

        SEL=$(printf "%s\n" "${OPTIONS[@]}" | fzf --cycle --prompt="WayClick > " --reverse --border --ansi)

        [ -z "$SEL" ] && return
        [[ "$SEL" == "Back" ]] && return

        if [[ "$SEL" == *"Toggle"* ]]; then
            "$HOME/.local/bin/wayclick.sh"
        elif [[ "$SEL" == "Change Volume" ]]; then
            vol=$(printf '' | fzf --print-query --prompt="Volume (0-100) > " --reverse --border --ansi 2>/dev/null | head -1)
            if [[ -n "$vol" && "$vol" =~ ^[0-9]+$ && "$vol" -ge 0 && "$vol" -le 100 ]]; then
                echo "$vol" > "$WAYCLICK_VOLUME_FILE"
                notify-send -h "int:value:${vol}" -h "string:x-canonical-private-synchronous:wayclick" -t 1000 "WayClick" "${vol}% volume"
            fi
        fi
    done
}

# Main loop
while true; do
    CHOICE=$(main_menu)

    [ -z "$CHOICE" ] && exit 0

    case "$CHOICE" in
        *Cursors)              pick_cursor ;;
        *Themes)               THEME=$(printf "Dark\nLight" | fzf --cycle --prompt="Theme > " --reverse --border --ansi); [ -n "$THEME" ] && "$HOME/.local/bin/theme-switcher" "$THEME" ;;
        *Waybar)               pick_waybar ;;
        *Refresh\ Rate)        "$HOME/.local/bin/refresh-rate-menu.sh" ;;
        *Resolution)           "$HOME/.local/bin/resolution-menu.sh" ;;
        *Default\ Browser)     pick_browser ;;
        *Default\ File\ Manager) pick_filemanager ;;

        *Security)             pick_security ;;
        *Keybinds)             "$HOME/.local/bin/keybinds" ;;
        *Power\ Profile)       pick_power_profile ;;
        *Update\ Mirrors)      clear; echo "Updating mirrors..."; sudo reflector --latest 10 --protocol https --sort rate --save /etc/pacman.d/mirrorlist; echo ""; echo "Done! Press any key to continue..."; read -n 1 ;;
        *System\ Cleanup)      clear; echo "Cleaning package cache..."; sudo paccache -r; echo ""; echo "Removing orphan packages..."; sudo pacman -Rns $(pacman -Qdtq) 2>/dev/null; echo ""; echo "Done! Press any key to continue..."; read -n 1 ;;
        *Games)                pick_games ;;
        *System\ Reset)        "$HOME/.local/bin/system-reset.sh" ;;
        *Rclone\ Mount*)       "$HOME/.local/bin/rclone-toggle.sh" ;;
        *WayClick)             pick_wayclick ;;
    esac
done
