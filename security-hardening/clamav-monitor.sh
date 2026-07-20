#!/bin/bash
# ClamAV Real-Time Monitor
# Watches folders for new/modified files and scans them

WATCH_DIRS=("$HOME/Downloads" "$HOME/Documents" "/tmp")
SCAN_INTERVAL=300  # seconds
LOG="/tmp/clamav-monitor.log"

echo "$(date): ClamAV monitor started" >> $LOG

while true; do
    for dir in "${WATCH_DIRS[@]}"; do
        if [ -d "$dir" ]; then
            # Find files modified in last interval
            find "$dir" -type f -mmin -$((SCAN_INTERVAL/60)) 2>/dev/null | while read file; do
                # Scan each file
                RESULT=$(clamscan "$file" 2>/dev/null)
                if echo "$RESULT" | grep -q " FOUND"; then
                    # Move to quarantine
                    mkdir -p /tmp/quarantine
                    mv "$file" /tmp/quarantine/ 2>/dev/null
                    echo "$(date): QUARANTINED: $file" >> $LOG
                    notify-send -u critical "Virus Found!" "Quarantined: $(basename $file)" 2>/dev/null || true
                fi
            done
        fi
    done
    sleep $SCAN_INTERVAL
done
