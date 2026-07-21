#!/bin/bash

WAYBAR_DIR="${HOME}/.config/waybar"
STATE_FILE="$WAYBAR_DIR/.current"

while true; do
    CHOICE=$(printf " \uf233 Waybar\n \uf1fc Themes\n \uf245 Cursors\n \uf0e4  Refresh Rate\n \uf26c  Resolution\n \uf0ac  Default Browser\n \uf07b  Default File Manager\n \uf0e7  Animation Speed\n \uf023  Security\n \uf11c  Keybinds\n \uf013  System Reset" | rofi -dmenu -p "Scrow Menu" -theme-str 'configuration { show-icons: false; } listview { columns: 3; }')

    [ -z "$CHOICE" ] && exit 0

    case "$CHOICE" in
        *Cursors)
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
        *Keybinds)
            "$HOME/.local/bin/keybinds"
            ;;
        *Animation\ Speed)
            CONFIG="$HOME/.config/hypr/modules/decorations.lua"
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

            SPEED=$(printf "%s\n" "${OPTIONS[@]}" | rofi -dmenu -p "Animation Speed" -theme-str 'configuration { show-icons: false; }')
            [ -z "$SPEED" ] && continue
            SPEED=$(echo "$SPEED" | sed 's/ \[active\]$//')

            set_speed() {
                local cfg="$HOME/.config/hypr/modules/decorations.lua"
                local duky="$HOME/.config/hypr/modules/decorations.lua.bak"
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
            ;;
        *Security)
            SECURITY_CHOICE=$(printf " \uf1e2  Security Audit\n \uf0e4  System Monitor\n \uf10c  Check AUR Package\n \uf0ac  Apply Security Hardening\n \uf121  Show Commands\n \uf013  Back to Settings" | rofi -dmenu -p "Security Checks" -theme-str 'configuration { show-icons: false; } listview { columns: 2; }')

            [ -z "$SECURITY_CHOICE" ] && continue

            case "$SECURITY_CHOICE" in
                *Security\ Audit)
                    kitty --class security-terminal -e bash -c '$HOME/security-hardening/audit.sh; echo ""; echo "Press any key to close..."; read -n 1'
                    ;;
                *System\ Monitor)
                    kitty --class security-terminal -e bash -c '$HOME/security-hardening/monitor.sh'
                    ;;
                *Check\ AUR\ Package)
                    PKG_NAME=$(echo "" | rofi -dmenu -p "Enter package name:" -theme-str 'configuration { show-icons: false; }')
                    [ -z "$PKG_NAME" ] && continue
                    kitty --class security-terminal -e bash -c "$HOME/security-hardening/aur-check.sh $PKG_NAME; echo ''; echo 'Press any key to close...'; read -n 1"
                    ;;
                *Apply\ Security\ Hardening)
                    kitty --class security-terminal -e bash -c 'echo "This requires sudo access."; echo "Run: sudo ~/security-hardening/apply-security.sh"; echo ""; echo "Press any key to close..."; read -n 1'
                    ;;
                *Show\ Commands)
                    kitty --class security-terminal -e bash -c 'cat << "EOF"
==========================================
       SECURITY COMMANDS REFERENCE
==========================================

AUDIT & MONITORING:
  ~/security-hardening/audit.sh
    - Scans system for security issues
    - Checks file permissions, firewall, SSH config
    - No sudo needed

  ~/security-hardening/monitor.sh
    - Real-time security monitoring
    - Shows failed logins, active sessions, CPU usage
    - Refreshes every 10 seconds
    - Press Ctrl+C to stop

AUR PACKAGE SCANNING:
  ~/security-hardening/aur-check.sh <package-name>
    - Scans AUR package for malware before install
    - Checks for suspicious patterns (curl|bash, rm -rf, etc.)
    - Shows package votes and maintainer
    - Example: ~/security-hardening/aur-check.sh vscodium

SYSTEM HARDENING (requires sudo):
  sudo ~/security-hardening/apply-security.sh
    - Installs and configures all security tools
    - Sets up firewall, SSH hardening, Fail2Ban
    - Enables ClamAV antivirus
    - Run once after fresh install

  sudo ~/security-hardening/fix-permissions.sh
    - Fixes file permissions (already ran)
    - Locks down .ssh, .bash_history, etc.

QUICK ALIASES (in .zshrc):
  secscan
    - Shortcut for: ~/security-hardening/audit.sh

  secmonitor
    - Shortcut for: ~/security-hardening/monitor.sh

  aurcheck <package>
    - Shortcut for: ~/security-hardening/aur-check.sh <package>

  fuck -S <package>
    - Normal paru install (no scan)
    - Use aurcheck first to scan manually

FILES CREATED:
  ~/security-hardening/
    ├── apply-security.sh      # Master security script
    ├── audit.sh               # Security audit
    ├── monitor.sh             # Real-time monitoring
    ├── aur-check.sh           # AUR package scanner
    ├── fix-permissions.sh     # File permission fixes
    ├── sshd_hardened.conf     # SSH server config
    ├── nftables_hardened.conf # Firewall rules
    ├── sysctl_security.conf   # Kernel hardening
    ├── fail2ban_jail.local    # Brute force protection
    ├── usb-scan.sh            # USB malware scanning
    ├── usb-scan.rules         # USB auto-scan trigger
    ├── clamav-monitor.sh      # Real-time virus monitor
    └── clamav-monitor.service # Systemd service for monitor

==========================================
Press any key to close...
EOF
read -n 1'
                    ;;
                *Back\ to\ Settings)
                    continue
                    ;;
            esac
            ;;
    esac
done
