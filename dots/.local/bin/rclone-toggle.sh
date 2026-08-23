#!/bin/bash

MOUNT_POINT="$HOME/gdrive"
REMOTE="gdrive"
PIDFILE="/tmp/rclone-gdrive.pid"

cleanup() {
    if [ -f "$PIDFILE" ]; then
        kill "$(cat "$PIDFILE")" 2>/dev/null
        rm -f "$PIDFILE"
    fi
    fusermount3 -uz "$MOUNT_POINT" 2>/dev/null
}

if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
    cleanup
    sleep 1
    notify-send -t 3000 "Rclone" "Unmounted gdrive"
else
    cleanup
    sleep 1
    mkdir -p "$MOUNT_POINT"
    rclone mount "$REMOTE": "$MOUNT_POINT" \
        --vfs-cache-mode full \
        --dir-cache-time 72h \
        --poll-interval 15s \
        --buffer-size 64M \
        --vfs-read-chunk-size 32M \
        --vfs-read-chunk-size-limit 2G \
        --attr-timeout 1h \
        --no-modtime \
        --daemon \
        --daemon-wait 10s
    echo $! > "$PIDFILE" 2>/dev/null
    sleep 3
    if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
        notify-send -t 3000 "Rclone" "Mounted gdrive"
    else
        notify-send -u critical -t 5000 "Rclone" "Failed to mount gdrive"
        rm -f "$PIDFILE"
    fi
fi
