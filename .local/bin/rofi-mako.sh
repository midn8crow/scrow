#!/usr/bin/env bash

ACTIVE=$(makoctl list -j 2>/dev/null || echo "[]")
HISTORY=$(makoctl history -j 2>/dev/null || echo "[]")

[[ -z "$ACTIVE" ]] && ACTIVE="[]"
[[ -z "$HISTORY" ]] && HISTORY="[]"

BLACKLIST_FILE="${XDG_RUNTIME_DIR:-/tmp}/mako_rofi_blacklist"
BLACKLIST_RAW=$(cat "$BLACKLIST_FILE" 2>/dev/null || echo "")

MENU_PAYLOAD=$(jq -r -n \
  --argjson active "$ACTIVE" \
  --argjson history "$HISTORY" \
  --arg bl "$BLACKLIST_RAW" '

  def is_ignored:
    . == "OSD" or . == "scrow-recorder" or . ==  "scrow-keys" or . == "scrow-cava" or . == "scrow-cava-alert" or
    (type == "string" and startswith("scrow-glance")) or . == "scrow-tlp" or . == "scrow-high-ram-alert" or . == "Spotify" or . == "matugen-theme" or . == "scrow-fav-wal";

  def escape_pango:
      if type == "string" then
        gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;") | gsub("\""; "&quot;")
      else
        .
      end;

  def clean_app:
      if .app_name == "notify-send" or .app_name == "mako" or .app_name == null then
        ""
      else
        "[\(.app_name | escape_pango)] "
      end;

  def clean_body:
      if .body == null or .body == "" then
        "\n<span alpha=\"50%\" size=\"smaller\"><i>No additional details</i></span>"
      else
        "\n<span alpha=\"75%\" size=\"smaller\">\((.body) | gsub("<[^>]+>"; "") | escape_pango | gsub("\n"; " ") | sub("^\\s+"; ""))</span>"
      end;

  ($bl | split("\n") | map(select(. != ""))) as $blacklisted_ids

  | ($active | map(. + {__source: "active"})) as $a
  | ($history | map(. + {__source: "history"})) as $h

  | ($a + $h)
  | unique_by(.id)
  | sort_by(.id)
  | reverse
  | .[]
  | select(.summary != null and .summary != "")
  | select(.app_name | is_ignored | not)
  | select((.id | tostring) as $id_str | $blacklisted_ids | index($id_str) | not)

  | "\(.id)\t\(.desktop_entry // .app_name // "" | gsub("\t";" "))\t\(.__source)\t<b>\(clean_app)\(.summary | gsub("<[^>]+>"; "") | escape_pango)</b>\(clean_body)\u001e"
')

if [[ -z "$MENU_PAYLOAD" ]]; then
    notify-send -t 1500 "󰎟 Notifications" "No notifications in buffer."
    exit 0
fi

ID_ARRAY=()
APP_ARRAY=()
SRC_ARRAY=()
MENU_STRING=""

while IFS=$'\t' read -r -d $'\x1e' id app source text; do
    [[ -z "$id" ]] && continue
    ID_ARRAY+=("$id")
    APP_ARRAY+=("$app")
    SRC_ARRAY+=("$source")
    MENU_STRING+="${text}"$'\x1e'
done <<< "$MENU_PAYLOAD"

SELECTED_INDEX=$(echo -n "$MENU_STRING" | rofi -dmenu -i -p "󰎟 Notifications" \
    -mesg "<b>Alt+y</b>: Clear All  |  <b>Alt+t</b>: Toggle DND  |  <b>Click</b>: Action/Dismiss" \
    -markup-rows \
    -sep '\x1e' \
    -format 'i' \
    -eh 2 \
    -kb-custom-2 "Alt+y" \
    -kb-custom-3 "Alt+t" \
    -hover-select \
    -me-select-entry '' \
    -me-accept-entry 'MousePrimary' \
    -theme-str 'window {width: 45%;} listview {lines: 6; fixed-height: false;} element {padding: 10px 14px;} element-text {vertical-align: 0.5;}')

ROFI_EXIT=$?

case $ROFI_EXIT in
    0)
        if [[ "$SELECTED_INDEX" =~ ^[0-9]+$ ]]; then
            SELECTED_ID="${ID_ARRAY[$SELECTED_INDEX]}"
            SELECTED_APP="${APP_ARRAY[$SELECTED_INDEX]}"
            SELECTED_SRC="${SRC_ARRAY[$SELECTED_INDEX]}"

            if [[ "$SELECTED_SRC" == "active" ]]; then
                makoctl invoke -n "$SELECTED_ID" default 2>/dev/null
            else
                if [[ -n "$SELECTED_APP" && "$SELECTED_APP" != "notify-send" && "$SELECTED_APP" != "mako" ]]; then
                    { gtk-launch "$SELECTED_APP" || hyprctl dispatch exec "$SELECTED_APP"; } >/dev/null 2>&1 &
                fi
            fi

            makoctl dismiss -n "$SELECTED_ID" 2>/dev/null
            echo "$SELECTED_ID" >> "$BLACKLIST_FILE"
        fi
        ;;
    11)
        rm -f "$BLACKLIST_FILE"
        if systemctl --user is-active --quiet mako.service; then
            systemctl --user restart mako.service
        else
            pkill -x mako && mako &
        fi
        ;;
    12)
        if makoctl mode | grep -qw "do-not-disturb"; then
            makoctl mode -r do-not-disturb
            notify-send -a "mako" -u normal "󰂚  Do Not Disturb" "Disabled"
        else
            makoctl mode -a do-not-disturb
        fi
        ;;
esac
