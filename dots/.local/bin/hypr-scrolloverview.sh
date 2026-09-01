#!/usr/bin/env bash
# Ensures the ScrollOverview plugin is loaded at Hyprland startup. Runs from the
# hyprland.start event (after waybar/autostart); self-heals an unloaded/missing
# plugin and only shows the "not installed" hint when the plugin genuinely
# cannot be loaded.
set -u

sleep 2

command -v hyprctl >/dev/null 2>&1 || exit 1
command -v hyprpm  >/dev/null 2>&1 || exit 1

# Only act when Hyprland is actually running (headless boots skip quietly).
hyprctl instanceinfo >/dev/null 2>&1 || exit 0

loaded() {
    hyprctl -j plugin list 2>/dev/null | grep -qi scrolloverview \
        || hyprctl plugin list 2>/dev/null | grep -qi scrolloverview
}

enabled() {
    hyprpm list 2>/dev/null | sed -r 's/\x1b\[[0-9;]*m//g' | grep -qiE 'enabled:[[:space:]]*true'
}

# Already loaded — nothing to do.
if loaded; then
    exit 0
fi

# Enabled but not yet loaded: force a state reload so Hyprland picks it up.
if ! enabled; then
    if ! hyprpm enable scrolloverview >/dev/null 2>&1; then
        sudo hyprpm add https://github.com/yayuuu/hyprland-scroll-overview.git >/dev/null 2>&1 || true
        hyprpm enable scrolloverview >/dev/null 2>&1 || true
    fi
fi

hyprpm reload -f >/dev/null 2>&1 || true
sleep 2

if loaded; then
    exit 0
fi

if command -v notify-send >/dev/null 2>&1; then
    notify-send -u normal -a scrow "ScrollOverview plugin not installed" \
        "run: hyprpm add https://github.com/yayuuu/hyprland-scroll-overview.git" || true
fi
exit 1