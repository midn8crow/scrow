#!/usr/bin/env bash
# rofi "System Apps" tab: curated system apps, launches on selection.

source "$HOME/.config/rofi/lib/_common.sh"

if [ "$ROFI_RETV" = "1" ] && [ -n "$1" ]; then
    cmd="${SYSTEM_APPS[$1]}"
    if [ -n "$cmd" ]; then
        nohup bash -c "$cmd" >/dev/null 2>&1 &
    fi
    exit 0
fi

echo -en "\0prompt\x1fSystem Apps\n"
for name in "${!SYSTEM_APPS[@]}"; do
    icon="${SYSTEM_APP_ICONS[$name]}"
    echo -en "$name\0icon\x1f$icon\n"
done
