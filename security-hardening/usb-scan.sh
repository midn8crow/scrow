#!/bin/bash
# USB Auto-Scan Script
# Scans USB drive for malware when connected

DEVICE="$1"
LOG="/tmp/usb-scan.log"
MOUNT_POINT="/mnt/usb-scan"

# Wait for device to be ready
sleep 2

# Find mount point
MOUNT_DIR=$(lsblk -o MOUNTPOINT -n /dev/$DEVICE 2>/dev/null | head -1)

if [ -z "$MOUNT_DIR" ]; then
    # Try to mount temporarily
    mkdir -p $MOUNT_POINT
    mount -o ro /dev/$DEVICE $MOUNT_POINT 2>/dev/null
    MOUNT_DIR=$MOUNT_POINT
fi

if [ -z "$MOUNT_DIR" ] || [ ! -d "$MOUNT_DIR" ]; then
    echo "$(date): Failed to mount /dev/$DEVICE for scanning" >> $LOG
    exit 1
fi

echo "$(date): Scanning USB device $DEVICE mounted at $MOUNT_DIR" >> $LOG

# Scan with ClamAV
if command -v clamscan &>/dev/null; then
    RESULT=$(clamscan -r --bell --move=/tmp/quarantine "$MOUNT_DIR" 2>&1)
    INFECTED=$(echo "$RESULT" | grep "Infected files:" | awk '{print $3}')
    
    if [ "$INFECTED" -gt 0 ]; then
        echo "$(date): WARNING! $INFECTED infected files found on $DEVICE" >> $LOG
        # Send notification if possible
        notify-send -u critical "USB Security Alert" "Infected files found on USB drive!\nCheck $LOG for details" 2>/dev/null || true
    else
        echo "$(date): $DEVICE is clean" >> $LOG
        notify-send "USB Scan Complete" "Drive is clean" 2>/dev/null || true
    fi
else
    echo "$(date): clamscan not found, skipping scan" >> $LOG
fi

# Unmount if we mounted it
if [ "$MOUNT_DIR" = "$MOUNT_POINT" ]; then
    umount $MOUNT_POINT 2>/dev/null
fi
