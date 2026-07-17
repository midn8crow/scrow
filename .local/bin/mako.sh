#!/usr/bin/env bash
set -euo pipefail

MODE="horizontal"
for arg in "$@"; do
    case "$arg" in
        --vertical) MODE="vertical" ;;
        --horizontal) MODE="horizontal" ;;
        --clear)
            rm -f "${XDG_RUNTIME_DIR:-/tmp}/mako_rofi_blacklist"
            if systemctl --user is-active --quiet mako.service; then
                systemctl --user restart mako.service
            else
                pkill -x mako && mako &
            fi
            exit 0
            ;;
    esac
done

ACTIVE=$(timeout 1 makoctl list -j 2>/dev/null || echo "[]")
ACTIVE=${ACTIVE:-[]}

HISTORY=$(timeout 1 makoctl history -j 2>/dev/null || echo "[]")
HISTORY=${HISTORY:-[]}

MAKO_MODE=$(timeout 1 makoctl mode 2>/dev/null || true)
DND_STATE=""
if [[ "$MAKO_MODE" =~ "do-not-disturb" ]]; then
    DND_STATE="true"
fi

BLACKLIST_FILE="${XDG_RUNTIME_DIR:-/tmp}/mako_rofi_blacklist"
BLACKLIST_RAW=""
if [[ -r "$BLACKLIST_FILE" ]]; then
    BLACKLIST_RAW=$(<"$BLACKLIST_FILE" 2>/dev/null) || true
fi

jq -c -n \
    --argjson active "$ACTIVE" \
    --argjson history "$HISTORY" \
    --arg bl "$BLACKLIST_RAW" \
    --arg dnd "$DND_STATE" \
    --arg mode "$MODE" '

    def extract_notifs:
        if type == "object" and .data then [.data[][]?] else (if type == "array" then . else [] end) end;

    def is_ignored:
        . == "OSD" or . == "scrow-keys" or . == "scrow-cava" or . == "scrow-cava-alert" or
        . == "scrow-glance-narrow" or . == "scrow-glance-wide" or . == "scrow-glance-timer" or
        . == "scrow-glance-alert" or . == "Spotify";

    def pad3:
        tostring |
        length as $l |
        if $l >= 3 then .
        elif $l == 2 then "\u2005" + . + "\u2005"
        elif $l == 1 then " " + . + " "
        else "   " end;

    "\u{f0c1b}" as $dnd_icon | "\u{f0c1a}" as $norm_icon |

    ($bl | split("\n") | map(select(length > 0)) | reduce .[] as $id ({}; .[$id] = true)) as $blacklist_dict

    | (($active | extract_notifs) + ($history | extract_notifs))
    | unique_by(.id)
    | map(select(.summary != null and .summary != ""))
    | map(select((.app_name | is_ignored | not) and ($blacklist_dict[.id | tostring] | not)))
    | length as $count

    | if ($dnd != "") then
        {
            "text": (if $mode == "vertical" then (if $count == 0 then ($dnd_icon | pad3) else ($count | pad3) + "\n" + ($dnd_icon | pad3) end) else (if $count == 0 then $dnd_icon else "\($dnd_icon) \($count)" end) end),
            "tooltip": "Do Not Disturb (\($count) pending)",
            "class": (if $count == 0 then "dnd" else "dnd-pending" end)
        }
      else
        {
            "text": (if $mode == "vertical" then (if $count == 0 then ($norm_icon | pad3) else ($count | pad3) + "\n" + ($norm_icon | pad3) end) else (if $count == 0 then $norm_icon else "\($norm_icon) \($count)" end) end),
            "tooltip": (if $count == 0 then "No notifications" else "\($count) pending notifications" end),
            "class": (if $count == 0 then "empty" else "pending" end)
        }
      end
'
