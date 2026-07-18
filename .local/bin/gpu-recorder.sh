#!/bin/bash

MARKER="/tmp/gpu-recorder.recording"
PAUSED="/tmp/gpu-recorder.paused"
OUT_DIR="$HOME/Videos/Recording"
CONF="$HOME/.config/gpu-recorder.conf"

mkdir -p "$OUT_DIR"
mkdir -p "$(dirname "$CONF")"

[ -f "$CONF" ] || printf 'QUALITY="High (hevc)"\nRES="1080p (1920x1080)"\n' > "$CONF"
source "$CONF"

if [ -f "$MARKER" ]; then
    if [ -f "$PAUSED" ]; then
        CHOICE=$(echo -e "Stop Recording\nResume\nCancel" | rofi -dmenu -p "Recording Paused" -theme-str 'window {width: 400px;}')
        if [ "$CHOICE" = "Stop Recording" ]; then
            pkill -SIGINT -f "gpu-screen-recorder" 2>/dev/null
            pkill -f "record-indicator" 2>/dev/null
            rm -f "$MARKER" "$PAUSED"
            notify-send "GPU Recorder" "Recording saved to $OUT_DIR"
        elif [ "$CHOICE" = "Resume" ]; then
            pkill -SIGUSR2 -f "gpu-screen-recorder" 2>/dev/null
            rm -f "$PAUSED"
            notify-send "GPU Recorder" "Recording resumed"
        fi
    else
        CHOICE=$(echo -e "Stop Recording\nPause\nCancel" | rofi -dmenu -p "Recording Active" -theme-str 'window {width: 400px;}')
        if [ "$CHOICE" = "Stop Recording" ]; then
            pkill -SIGINT -f "gpu-screen-recorder" 2>/dev/null
            pkill -f "record-indicator" 2>/dev/null
            rm -f "$MARKER" "$PAUSED"
            notify-send "GPU Recorder" "Recording saved to $OUT_DIR"
        elif [ "$CHOICE" = "Pause" ]; then
            pkill -SIGUSR2 -f "gpu-screen-recorder" 2>/dev/null
            touch "$PAUSED"
            notify-send "GPU Recorder" "Recording paused"
        fi
    fi
    exit 0
fi

save_conf() {
    printf 'QUALITY="%s"\nRES="%s"\n' "$QUALITY" "$RES" > "$CONF"
}

get_q_short() { echo "${1%% (*}"; }
get_r_short() { echo "${1%% (*}"; }

show_settings() {
    Q_SHORT=$(get_q_short "$QUALITY")
    R_SHORT=$(get_r_short "$RES")
    SETTINGS_CHOICE=$(printf "Quality:  %s ◄\nResolution:  %s ◄" "$Q_SHORT" "$R_SHORT" | rofi -dmenu -p "Recording Settings" -theme-str 'window {width: 400px;}')
}

while true; do
    CHOICE=$(echo -e "Record Full Screen\nRecord Region\nRecording Settings" | rofi -dmenu -p "GPU Recorder" -theme-str 'window {width: 400px;}')

    if [ "$CHOICE" = "Recording Settings" ]; then
        show_settings
        if echo "$SETTINGS_CHOICE" | grep -q "^Quality:"; then
            Q_LIST=""
            for opt in "Ultra (hevc)" "High (hevc)" "Balanced (h264)" "Performance (h264)" "Lightweight (h264)"; do
                [ "$opt" = "$QUALITY" ] && Q_LIST="${Q_LIST}● ${opt}\n" || Q_LIST="${Q_LIST}  ${opt}\n"
            done
            NEW_Q=$(printf "$Q_LIST" | rofi -dmenu -p "Quality" -theme-str 'window {width: 400px;}')
            NEW_Q="${NEW_Q#● }"
            NEW_Q="${NEW_Q#  }"
            if [ -n "$NEW_Q" ]; then
                QUALITY="$NEW_Q"
                save_conf
            fi
        elif echo "$SETTINGS_CHOICE" | grep -q "^Resolution:"; then
            R_LIST=""
            for opt in "4K (3840x2160)" "1440p (2560x1440)" "1080p (1920x1080)" "720p (1280x720)" "480p (854x480)" "Native (Original)"; do
                [ "$opt" = "$RES" ] && R_LIST="${R_LIST}● ${opt}\n" || R_LIST="${R_LIST}  ${opt}\n"
            done
            NEW_R=$(printf "$R_LIST" | rofi -dmenu -p "Resolution" -theme-str 'window {width: 400px;}')
            NEW_R="${NEW_R#● }"
            NEW_R="${NEW_R#  }"
            if [ -n "$NEW_R" ]; then
                RES="$NEW_R"
                save_conf
            fi
        elif [ -z "$SETTINGS_CHOICE" ]; then
            continue
        fi
        continue
    fi

    break
done

[ -z "$CHOICE" ] && exit 0
[ "$CHOICE" != "Record Full Screen" ] && [ "$CHOICE" != "Record Region" ] && exit 0

AUDIO=$(echo -e "With Audio\nWithout Audio" | rofi -dmenu -p "Audio" -theme-str 'window {width: 400px;}')
[ -z "$AUDIO" ] && exit 0
AUDIO_FLAG=""
[ "$AUDIO" = "With Audio" ] && AUDIO_FLAG="-a default_output"

case "$QUALITY" in
    "Ultra (hevc)")        Q_FLAGS="-q ultra -k hevc" ;;
    "High (hevc)")         Q_FLAGS="-q high -k hevc" ;;
    "Balanced (h264)")     Q_FLAGS="-q high" ;;
    "Performance (h264)")  Q_FLAGS="-q medium" ;;
    "Lightweight (h264)")  Q_FLAGS="-q low" ;;
esac

case "$RES" in
    "4K (3840x2160)")       RES_FLAGS="-s 3840x2160" ;;
    "1440p (2560x1440)")    RES_FLAGS="-s 2560x1440" ;;
    "1080p (1920x1080)")    RES_FLAGS="-s 1920x1080" ;;
    "720p (1280x720)")      RES_FLAGS="-s 1280x720" ;;
    "480p (854x480)")       RES_FLAGS="-s 854x480" ;;
    "Native (Original)")    RES_FLAGS="" ;;
esac

FILE="$OUT_DIR/record-$(date +%Y%m%d-%H%M%S).mp4"

if [ "$CHOICE" = "Record Full Screen" ]; then
    MONITOR=$(hyprctl monitors -j 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['name'])" 2>/dev/null || echo "")
    nohup gpu-screen-recorder -w "$MONITOR" $Q_FLAGS $RES_FLAGS -f 60 $AUDIO_FLAG -o "$FILE" >/dev/null 2>&1 &
    touch "$MARKER"
    ~/.local/bin/record-indicator &
    notify-send "GPU Recorder" "Recording full screen started"
elif [ "$CHOICE" = "Record Region" ]; then
    REGION=$(slurp 2>/dev/null) || exit 1
    nohup gpu-screen-recorder -w "$REGION" $Q_FLAGS $RES_FLAGS -f 60 $AUDIO_FLAG -o "$FILE" >/dev/null 2>&1 &
    touch "$MARKER"
    ~/.local/bin/record-indicator &
    notify-send "GPU Recorder" "Recording region started"
fi
