#!/bin/sh
BSSIDS="$(nmcli device wifi list |
    awk 'NR>1 {if ($1 != "*") {print $1}}' |
    tr -d ":" |
    tr "\n" ",")"

LOC=""
REQUEST_GEO="$(wget -qO - http://openwifi.su/api/v1/bssids/"$BSSIDS")"
if [[ "$(jq ".count_results" <<< "$REQUEST_GEO")" -gt 0 ]] ; then
    LAT="$(jq ".lat" <<< "$REQUEST_GEO")"
    LON="$(jq ".lon" <<< "$REQUEST_GEO")"
    LOC="$LAT,$LON"
fi

condition="$(curl -s "https://wttr.in/$LOC?format=%C" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
temp="$(curl -s "https://wttr.in/$LOC?format=%t" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
tooltip="$(curl -s "https://wttr.in/$LOC?0QT" |
    sed 's/\\/\\\\/g' |
    sed ':a;N;$!ba;s/\n/\\n/g' |
    sed 's/"/\\"/g')"

case "$(echo "$condition" | tr '[:upper:]' '[:lower:]')" in
    *sunny*|*clear*)            icon="󰅙" ;;
    *partly*cloud*)             icon="󰅑" ;;
    *cloud*|*overcast*)         icon="󰅟" ;;
    *fog*|*mist*|*haze*)        icon="󰅜" ;;
    *rain*|*drizzle*|*shower*)  icon="󰅓" ;;
    *thunder*|*storm*)          icon="󰅚" ;;
    *snow*|*sleet*|*blizzard*)  icon="󰅗" ;;
    *wind*)                     icon="󰅝" ;;
    *hail*)                     icon="󰅞" ;;
    *)                          icon="󰅟" ;;
esac

text="$icon $temp"

if ! grep -q "Unknown location" <<< "$temp"; then
    echo "{\"text\": \"$text\", \"tooltip\": \"<tt>$tooltip</tt>\", \"class\": \"weather\"}"
fi
