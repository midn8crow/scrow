#!/usr/bin/env sh

# emoji-launch.sh - launches the rofi emoji picker.
# Opens on "Recently Used" when there is history, otherwise on "All Emojis"
# (so a fresh system without recents starts on the full grid).

HISTORY_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/emoji-history"

MODI="recents:$HOME/.local/bin/emoji-recents.sh,all:$HOME/.local/bin/emoji-all.sh,people:$HOME/.local/bin/emoji-people.sh,organs:$HOME/.local/bin/emoji-organs.sh,animals:$HOME/.local/bin/emoji-animals.sh,food:$HOME/.local/bin/emoji-food.sh,symbols:$HOME/.local/bin/emoji-symbols.sh"

if [ -s "$HISTORY_FILE" ]; then
    MODE=recents
else
    MODE=all
fi

exec rofi -config "$HOME/.config/rofi/emoji.rasi" -show "$MODE" -modi "$MODI" -sidebar-mode
