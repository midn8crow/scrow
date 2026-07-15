#!/bin/bash

MARKER="/tmp/gpu-recorder.recording"
PAUSED="/tmp/gpu-recorder.paused"
OUT_DIR="$HOME/Videos/Recording"

mkdir -p "$OUT_DIR"

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

CHOICE=$(echo -e "Record Full Screen\nRecord Region" | rofi -dmenu -p "GPU Recorder" -theme-str 'window {width: 400px;}')

case "$CHOICE" in
    "Record Full Screen")
        AUDIO=$(echo -e "With Audio\nWithout Audio" | rofi -dmenu -p "Audio" -theme-str 'window {width: 400px;}')
        [ -z "$AUDIO" ] && exit 0
        AUDIO_FLAG=""
        [ "$AUDIO" = "With Audio" ] && AUDIO_FLAG="-a default_output"
        FILE="$OUT_DIR/record-$(date +%Y%m%d-%H%M%S).mp4"
        MONITOR=$(hyprctl monitors -j 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['name'])" 2>/dev/null || echo "")
        nohup gpu-screen-recorder -w "$MONITOR" -f 60 -q high $AUDIO_FLAG -o "$FILE" >/dev/null 2>&1 &
        touch "$MARKER"
        ~/.local/bin/record-indicator &
        notify-send "GPU Recorder" "Recording full screen started"
        ;;
    "Record Region")
        REGION=$(slurp 2>/dev/null) || exit 1
        AUDIO=$(echo -e "With Audio\nWithout Audio" | rofi -dmenu -p "Audio" -theme-str 'window {width: 400px;}')
        [ -z "$AUDIO" ] && exit 0
        AUDIO_FLAG=""
        [ "$AUDIO" = "With Audio" ] && AUDIO_FLAG="-a default_output"
        FILE="$OUT_DIR/record-$(date +%Y%m%d-%H%M%S).mp4"
        nohup gpu-screen-recorder -w "$REGION" -f 60 -q high $AUDIO_FLAG -o "$FILE" >/dev/null 2>&1 &
        touch "$MARKER"
        ~/.local/bin/record-indicator &
        notify-send "GPU Recorder" "Recording region started"
        ;;
esac
