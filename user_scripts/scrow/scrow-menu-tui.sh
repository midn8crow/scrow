#!/bin/bash

WAYBAR_DIR="${HOME}/.config/waybar"
STATE_FILE="$WAYBAR_DIR/.current"

main_menu() {
    if mountpoint -q "$HOME/gdrive" 2>/dev/null; then
        RCLONE_SUFFIX=" [active]"
    else
        RCLONE_SUFFIX=""
    fi

    printf " \uf023  Security\n \uf185  Power Profile\n \uf2ed  System Cleanup\n \uf233  Waybar\n \uf1fc  Themes\n \uf245  Cursors\n \uf0e4  Refresh Rate\n \uf26c  Resolution\n \uf0ac  Default Browser\n \uf07b  Default File Manager\n \uf0e7  Animation Speed\n \uf11c  Keybinds\n \uf304  Update Mirrors\n \uf11b  Games\n \uf013  System Reset\n \uf019  Rclone Mount${RCLONE_SUFFIX}" | fzf --cycle --prompt="Scrow Menu > " --reverse --border --ansi
}

pick_cursor() {
    CURSOR_STATE="$HOME/.config/hypr/.cursor-theme"
    current_cursor=$(cat "$CURSOR_STATE" 2>/dev/null)

    declare -A cursor_map=(
        ["Bibata-Modern-Classic"]="SCROW (Recommended)"
        ["Bibata-Modern-Ice"]="Bibata Modern Ice"
        ["Bibata-Original-Classic"]="Bibata Original Classic"
        ["phinger-cursors-dark"]="Phinger Dark"
        ["phinger-cursors-light"]="Phinger Light"
        ["Minecraft-Animated"]="Minecraft Animated"
        ["Windows11Dark"]="Windows 11 Dark"
    )

    OPTIONS=("SCROW (Recommended)" "Bibata Modern Ice" "Bibata Original Classic" "Phinger Dark" "Phinger Light" "Minecraft Animated" "Windows 11 Dark")

    while true; do
        current_cursor=$(cat "$CURSOR_STATE" 2>/dev/null)

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
        echo "Back" >> "$TMPFILE"

        CUR=$(cat "$TMPFILE" | fzf --cycle --prompt="Cursor Theme > " --reverse --border --ansi)
        rm -f "$TMPFILE"

        [ -z "$CUR" ] && return
        [[ "$CUR" == "Back" ]] && return
        CUR=$(echo "$CUR" | sed 's/ \[active\]$//')
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

pick_anim_speed() {
    CONFIG="$HOME/.config/hypr/modules/decorations.lua"

    set_speed() {
        local cfg="$HOME/.config/hypr/modules/decorations.lua"
        sed -i '/animations = {/!b;n;s/enabled = false/enabled = true/' "$cfg"
        local start=$(grep -n '^-- scrow curves\|^-- Default curves' "$cfg" | head -1 | cut -d: -f1)
        local end=$(grep -n 'leaf = "specialWorkspace"\|leaf = "zoomFactor"' "$cfg" | tail -1 | cut -d: -f1)
        if [[ -z "$start" ]]; then
            start=$(grep -n 'animations = {' "$cfg" | head -1 | cut -d: -f1)
            end=$(awk "NR>=$start && /^\\)/{print NR; exit}" "$cfg")
            if [[ -n "$end" ]]; then
                sed -i "${end}a\\
-- scrow curves\\
hl.curve(\"overshot\",  { type = \"bezier\", points = { {0.05, 0.9}, {0.1, 1.1} } })\\
hl.curve(\"fluid\",     { type = \"bezier\", points = { {0.25, 1}, {0, 1} } })\\
hl.curve(\"snap\",      { type = \"bezier\", points = { {0.5, 0.9}, {0.1, 1.05} } })\\
hl.curve(\"menu_decel\",{ type = \"bezier\", points = { {0.1, 1}, {0, 1} } })\\
hl.curve(\"liner\",     { type = \"bezier\", points = { {1, 1}, {1, 1} } })\\
\\
hl.animation({ leaf = \"windowsIn\",     enabled = true,  speed = $1,  bezier = \"overshot\",   style = \"popin 80%\" })\\
hl.animation({ leaf = \"windowsOut\",    enabled = true,  speed = $2,  bezier = \"snap\",       style = \"popin 80%\" })\\
hl.animation({ leaf = \"windowsMove\",   enabled = true,  speed = $1,  bezier = \"overshot\",   style = \"slide\" })\\
hl.animation({ leaf = \"border\",        enabled = true,  speed = 2,   bezier = \"liner\" })\\
hl.animation({ leaf = \"borderangle\",   enabled = true,  speed = 40,  bezier = \"liner\",      style = \"once\" })\\
hl.animation({ leaf = \"fade\",          enabled = true,  speed = $3,  bezier = \"fluid\" })\\
hl.animation({ leaf = \"layersIn\",      enabled = true,  speed = $4,  bezier = \"overshot\",   style = \"popin 70%\" })\\
hl.animation({ leaf = \"layersOut\",     enabled = false })\\
hl.animation({ leaf = \"fadeLayersIn\",  enabled = true,  speed = 5,   bezier = \"menu_decel\" })\\
hl.animation({ leaf = \"fadeLayersOut\", enabled = true,  speed = 4,   bezier = \"menu_decel\" })\\
hl.animation({ leaf = \"workspaces\",    enabled = true,  speed = $5,  bezier = \"overshot\",   style = \"slidevert\" })\\
hl.animation({ leaf = \"specialWorkspace\", enabled = true, speed = $5, bezier = \"overshot\", style = \"slidevert\" })" "$cfg"
            fi
            return
        fi
        sed -i "s/leaf = \"windowsIn\",.*speed = [0-9.]*/leaf = \"windowsIn\",     enabled = true,  speed = $1,  bezier = \"overshot\",   style = \"popin 80%\"/" "$cfg"
        sed -i "s/leaf = \"windowsOut\",.*speed = [0-9.]*/leaf = \"windowsOut\",    enabled = true,  speed = $2,  bezier = \"snap\",       style = \"popin 80%\"/" "$cfg"
        sed -i "s/leaf = \"windowsMove\",.*speed = [0-9.]*/leaf = \"windowsMove\",   enabled = true,  speed = $1,  bezier = \"overshot\",   style = \"slide\"/" "$cfg"
        sed -i "s/leaf = \"fade\",.*speed = [0-9.]*/leaf = \"fade\",          enabled = true,  speed = $3,  bezier = \"fluid\"/" "$cfg"
        sed -i "s/leaf = \"layersIn\",.*speed = [0-9.]*/leaf = \"layersIn\",      enabled = true,  speed = $4,  bezier = \"overshot\",   style = \"popin 70%\"/" "$cfg"
        sed -i "s/leaf = \"workspaces\",.*speed = [0-9.]*/leaf = \"workspaces\",    enabled = true,  speed = $5,  bezier = \"overshot\",   style = \"slidevert\"/" "$cfg"
        sed -i "s/leaf = \"specialWorkspace\",.*speed = [0-9.]*/leaf = \"specialWorkspace\", enabled = true, speed = $5, bezier = \"overshot\", style = \"slidevert\"/" "$cfg"
    }

    while true; do
        current_speed=$(grep 'leaf = "windowsIn"' "$CONFIG" | grep -oP 'speed\s*=\s*\K[^ ,]+' | head -1)
        anim_disabled=$(grep -A1 'animations = {' "$CONFIG" | grep 'enabled = false')

        OPTIONS=()
        if [[ -n "$anim_disabled" ]]; then
            OPTIONS+=("Disable [active]")
        else
            OPTIONS+=("Disable")
        fi
        if [[ "$current_speed" == "14" ]] && [[ -z "$anim_disabled" ]]; then
            OPTIONS+=("Slow [active]")
        else
            OPTIONS+=("Slow")
        fi
        if { [[ "$current_speed" == "6" ]] || [[ -z "$current_speed" ]]; } && [[ -z "$anim_disabled" ]]; then
            OPTIONS+=("Default [active]")
        else
            OPTIONS+=("Default")
        fi
        if { [[ "$current_speed" == "3" ]] || [[ "$current_speed" == "4" ]]; } && [[ -z "$anim_disabled" ]]; then
            OPTIONS+=("Fast [active]")
        else
            OPTIONS+=("Fast")
        fi
        if { [[ "$current_speed" == "0" ]] || [[ "$current_speed" == "1" ]]; } && [[ -z "$anim_disabled" ]]; then
            OPTIONS+=("Instant (No Animation) [active]")
        else
            OPTIONS+=("Instant (No Animation)")
        fi
        OPTIONS+=("Back")

        SPEED=$(printf "%s\n" "${OPTIONS[@]}" | fzf --cycle --prompt="Animation Speed > " --reverse --border --ansi)
        [ -z "$SPEED" ] && return
        [[ "$SPEED" == "Back" ]] && return
        SPEED=$(echo "$SPEED" | sed 's/ \[active\]$//')

        case "$SPEED" in
            "Disable")
                sed -i 's/enabled = true/enabled = false/' "$CONFIG"
                ;;
            "Slow")
                set_speed 14 10 10 12 16
                ;;
            "Default")
                set_speed 6 4 4 5 7
                ;;
            "Fast")
                set_speed 4 3 3 3 4
                ;;
            "Instant (No Animation)")
                set_speed 1 1 1 1 1
                ;;
        esac
        hyprctl reload
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
        SECURITY_CHOICE=$(printf " \uf1e2  Security Audit\n \uf0e4  System Monitor\n \uf10c  Check AUR Package\n \uf0ac  Apply Security Hardening\n \uf121  Show Commands\n \uf013  Back" | fzf --cycle --prompt="Security > " --reverse --border --ansi)

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
        *Animation\ Speed)     pick_anim_speed ;;
        *Security)             pick_security ;;
        *Keybinds)             "$HOME/.local/bin/keybinds" ;;
        *Power\ Profile)       pick_power_profile ;;
        *Update\ Mirrors)      clear; echo "Updating mirrors..."; sudo reflector --latest 10 --protocol https --sort rate --save /etc/pacman.d/mirrorlist; echo ""; echo "Done! Press any key to continue..."; read -n 1 ;;
        *System\ Cleanup)      clear; echo "Cleaning package cache..."; sudo paccache -r; echo ""; echo "Removing orphan packages..."; sudo pacman -Rns $(pacman -Qdtq) 2>/dev/null; echo ""; echo "Done! Press any key to continue..."; read -n 1 ;;
        *Games)                pick_games ;;
        *System\ Reset)        "$HOME/.local/bin/system-reset.sh" ;;
        *Rclone\ Mount*)       "$HOME/.local/bin/rclone-toggle.sh" ;;
    esac
done
