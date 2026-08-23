#!/usr/bin/env bash
# Shared logic for the "Apps" (normal apps) and "All Apps" rofi modes.
# Defines functions only; mode scripts set APP_MODE/PROMPT, source this file
# and call run_applist.

source "$HOME/.config/rofi/lib/_common.sh"

APP_DIRS=(
    "$HOME/.local/share/applications"
    "/usr/local/share/applications"
    "/usr/share/applications"
)

LANGCODE="${LANG%.*}" # e.g. en_US
LANGCODE_SHORT="${LANGCODE%%_*}"

# Extract fields from a .desktop file in a single read.
# Only the main [Desktop Entry] section is used (action groups are ignored),
# matching how rofi drun builds the app list.
# Output: Type \034 NoDisplay \034 Hidden \034 Name \034 Icon \034 Exec \034 Terminal
read_desktop() {
    local f="$1"
    awk -F'=' -v lang="$LANGCODE" -v langshort="$LANGCODE_SHORT" '
        function val() {
            v = $0;
            sub(/^[^=]*=[[:space:]]*/, "", v);
            return v
        }
        /^\[/          { section = $0 }
        section != "[Desktop Entry]" { next }
        /^Type=/          { type = val() }
        /^NoDisplay=/     { nd   = tolower(val()) }
        /^Hidden=/        { hd   = tolower(val()) }
        /^Name=/          { name = val() }
        /^Name\[[^]]*\]=/ { key = substr($1, 6, length($1) - 6); loc[key] = val() }
        /^Icon=/          { icon = val() }
        /^Exec=/          { ex   = val() }
        /^Terminal=/      { term = tolower(val()) }
        END {
            n = name;
            if (loc[lang] != "") n = loc[lang];
            else if (loc[langshort] != "") n = loc[langshort];
            printf "%s\034%s\034%s\034%s\034%s\034%s\034%s\n", type, nd, hd, n, icon, ex, term
        }
    ' "$f"
}

clean_exec() {
    printf '%s' "$1" | sed -E 's/[[:space:]]*%[A-Za-z]+//g'
}

launch_by_name() {
    local target="$1" f fields type nd hd name icon ex term
    local dir
    for dir in "${APP_DIRS[@]}"; do
        [ -d "$dir" ] || continue
        for f in "$dir"/*.desktop; do
            [ -f "$f" ] || continue
            IFS=$'\034' read -r type nd hd name icon ex term <<<"$(read_desktop "$f")"
            [ "$name" = "$target" ] || continue
            [ -n "$ex" ] || return 0
            ex="$(clean_exec "$ex")"
            if [ "$term" = "true" ]; then
                nohup kitty -e bash -lc "$ex" >/dev/null 2>&1 &
            else
                nohup bash -lc "$ex" >/dev/null 2>&1 &
            fi
            return 0
        done
    done
}

run_applist() {
    if [ "$ROFI_RETV" = "1" ] && [ -n "$1" ]; then
        launch_by_name "$1"
        exit 0
    fi

    echo -en "\0prompt\x1f$PROMPT\n"

    declare -A seen
    local f base fields type nd hd name icon ex term
    local dir
    for dir in "${APP_DIRS[@]}"; do
        [ -d "$dir" ] || continue
        for f in "$dir"/*.desktop; do
            [ -f "$f" ] || continue
            base="${f##*/}"
            [ -n "${seen[$base]+x}" ] && continue
            seen[$base]=1

            IFS=$'\034' read -r type nd hd name icon ex term <<<"$(read_desktop "$f")"
            [ "$type" = "Application" ] || continue
            [ "$nd" = "true" ] && continue
            [ "$hd" = "true" ] && continue
            [ -z "$name" ] && continue
            if [ "$APP_MODE" = "normal" ] && { is_system_app "$name" || is_system_app_file "$base"; }; then
                continue
            fi
            echo -en "$name\0icon\x1f${icon:-system-apps}\n"
        done
    done
}
