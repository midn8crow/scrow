#!/usr/bin/env bash
set -u
TITLE="Video Compressor"
TMPDIR=$(mktemp -d)
trap 'rm -f "$FFPIDFILE"; rm -rf "$TMPDIR"' EXIT

FFPIDFILE="/tmp/.video-compressor-ffpid"

if [ -f "$FFPIDFILE" ]; then
    OLD_PID=$(cat "$FFPIDFILE")
    if kill -0 "$OLD_PID" 2>/dev/null; then
        notify "Cancelling previous..." "Killing old ffmpeg (PID $OLD_PID)"
        kill "$OLD_PID" 2>/dev/null || true
        sleep 0.5
    fi
    rm -f "$FFPIDFILE"
fi

notify() { notify-send -a "$TITLE" "$1" "$2"; }

while true; do
    choice=$(zenity --list --title="$TITLE" --text="Choose an action:" \
        --column="Action" "Compress a video" "Restore from backup" "Quit" \
        --width=400 --height=250)
    case "$choice" in
        "Restore from backup")
            backup=$(zenity --file-selection --title="Select .backup file to restore" \
                --file-filter="Backup files | *.backup" 2>/dev/null)
            [ -z "$backup" ] && continue
            original="${backup%.backup}"
            [ ! -f "$original" ] && { zenity --error --text="Original not found:\n$original"; continue; }
            if zenity --question --text="Restore will replace:\n$original\nwith backup:\n$backup\nContinue?"; then
                cp "$backup" "$original"
                notify "Restored" "$(basename "$original") restored"
                zenity --info --text="Backup restored!"
            fi
            continue ;;
        "Quit"|"") exit 0 ;;
    esac

    INPUT=$(zenity --file-selection --title="Select video to compress" \
        --file-filter="Video files | *.mp4 *.mkv *.avi *.mov *.webm *.m4v" 2>/dev/null)
    [ -z "$INPUT" ] && continue
    command -v ffmpeg >/dev/null 2>&1 || { zenity --error --text="Install ffmpeg first."; continue; }

    BASENAME=$(basename "$INPUT")

    while true; do
        preset=$(zenity --list --title="$TITLE - Quality" \
            --text="Select compression mode for:\n$BASENAME" \
            --column="Mode" --column="Description" \
            "Target file size"   "Compress to a specific size (e.g. 10MB)" \
            "High Quality"       "Best quality, larger file (CRF 23)" \
            "Balanced"           "Good quality, smaller file (CRF 28)" \
            "Small File"         "Lower quality, smallest file (CRF 32)" \
            "Custom CRF"         "Enter your own CRF value (0-51)" \
            "Back"               "Return to main menu" \
            --width=650 --height=420)
        [ -z "$preset" ] && continue 2
        [ "$preset" = "Back" ] && continue 2

        TARGET_SIZE_MB=""
        if [ "$preset" = "Target file size" ]; then
            TARGET_SIZE_MB=$(zenity --entry --title="$TITLE - Target Size" \
                --text="Enter target file size in MB (e.g. 10):" --entry-text="10")
            [ -z "$TARGET_SIZE_MB" ] && continue
        elif [ "$preset" = "Custom CRF" ]; then
            CRF=$(zenity --entry --title="$TITLE - Custom CRF" \
                --text="Enter CRF value (0-51, lower = better quality):" --entry-text="28")
            [ -z "$CRF" ] && continue
        else
            case "$preset" in
                "High Quality") CRF=23 ;; "Balanced") CRF=28 ;; "Small File") CRF=32 ;; *) CRF=28 ;;
            esac
        fi

        while true; do
            res_option=$(zenity --list --title="$TITLE - Resolution" \
                --text="Select resolution for:\n$BASENAME" \
                --column="Option" --column="Description" \
                "Original" "Keep original resolution" \
                "1080p"    "Scale to 1920x1080 (if larger)" \
                "720p"     "Scale to 1280x720" \
                "480p"     "Scale to 854x480" \
                "Back"     "Back to quality menu" \
                --width=500 --height=280)
            [ -z "$res_option" ] && continue 2
            [ "$res_option" = "Back" ] && continue 2

            SCALE=""
            if [ "$res_option" != "Original" ]; then
                case "$res_option" in "1080p") SCALE="1920:1080" ;; "720p") SCALE="1280:720" ;; "480p") SCALE="854:480" ;; esac
            fi
            break
        done

        break
    done

    TIMESTAMP=$(date +%H%M%S)
    OUTPUT="${INPUT%.*}-compressed-${TIMESTAMP}.mp4"

    DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$INPUT" 2>/dev/null || echo "60")
    DUR_SEC=${DUR%.*}
    [ "$DUR_SEC" -lt 1 ] && DUR_SEC=1

    VF=""
    [ -n "$SCALE" ] && VF="-vf scale=$SCALE:force_original_aspect_ratio=decrease,pad=$SCALE:(ow-iw)/2:(oh-ih)/2"

    run_with_progress() {
        local label="$1"; shift

        (
            PIPE_OK=1

            ffmpeg -y -i "$INPUT" "$@" "$OUTPUT" -progress "$TMPDIR/prog" 2>"$TMPDIR/fferr" &
            FFPID=$!
            echo "$FFPID" > "$FFPIDFILE" 2>/dev/null || true

            while kill -0 "$FFPID" 2>/dev/null && [ "$PIPE_OK" -eq 1 ]; do
                if [ -s "$TMPDIR/prog" ]; then
                    t=$(grep -oP 'out_time=\K[0-9:.]+' "$TMPDIR/prog" 2>/dev/null | tail -1)
                    if [ -n "$t" ]; then
                        ts=$(echo "$t" | awk -F: '{print int(($1*3600)+($2*60)+$3)}')
                        pct=$(( ts * 100 / DUR_SEC ))
                        [ "$pct" -gt 100 ] && pct=100
                        echo "$pct" 2>/dev/null || { PIPE_OK=0; break; }
                        echo "# $label ($pct%)" 2>/dev/null || { PIPE_OK=0; break; }
                    fi
                fi
                sleep 0.5
            done

            if [ "$PIPE_OK" -eq 0 ]; then
                kill "$FFPID" 2>/dev/null || true
                rm -f "$OUTPUT" 2>/dev/null || true
                exit 1
            fi

            echo "100" 2>/dev/null || true
            echo "# Done!" 2>/dev/null || true
            wait "$FFPID" 2>/dev/null || true
            exit 0
        ) | zenity --progress --title="$TITLE" --text="$label..." --percentage=0 --auto-close 2>/dev/null

        if [ "${PIPESTATUS[1]}" -eq 1 ]; then
            notify "Cancelled" "Compression was cancelled"
            rm -f "$OUTPUT" 2>/dev/null || true
            return 1
        fi

        if [ ! -f "$OUTPUT" ] || [ ! -s "$OUTPUT" ]; then
            return 1
        fi

        return 0
    }

    if [ -n "$TARGET_SIZE_MB" ]; then
        TARGET_BITS=$(( TARGET_SIZE_MB * 8192 ))
        AUDIO_BR=64
        VIDEO_BR=$(( (TARGET_BITS / DUR_SEC) - AUDIO_BR ))
        [ "$VIDEO_BR" -lt 50 ] && VIDEO_BR=50

        zenity --info --title="$TITLE" --text="Target: ${TARGET_SIZE_MB}MB\nBitrate: ${VIDEO_BR}kbps\nDuration: ${DUR_SEC}s\n\nClick OK to start 2-pass encoding."

        rm -f "$TMPDIR"/ffmpeg2pass*.log 2>/dev/null || true
        rm -f "$HOME"/ffmpeg2pass*.log /tmp/ffmpeg2pass*.log 2>/dev/null || true

        (
            ffmpeg -y -i "$INPUT" -c:v libx264 -b:v "${VIDEO_BR}k" -preset medium $VF -pass 1 -passlogfile "$TMPDIR/ffmpeg2pass" -an -f mp4 /dev/null 2>"$TMPDIR/fferr1"
            echo $? > "$TMPDIR/pass1_rc"
        ) &
        PASS1_PID=$!
        (
            while kill -0 "$PASS1_PID" 2>/dev/null; do
                echo "# Analysing video (pass 1/2)..."
                sleep 0.3
            done
        ) | zenity --progress --title="$TITLE" --text="Analysing video..." --pulsate --auto-close 2>/dev/null
        RC1=${PIPESTATUS[1]}
        if [ "$RC1" -eq 1 ]; then
            kill "$PASS1_PID" 2>/dev/null || true
            notify "Cancelled" "Pass 1 cancelled"
            rm -f "$OUTPUT" 2>/dev/null || true
            continue
        fi
        wait "$PASS1_PID" 2>/dev/null || true
        RC=$(cat "$TMPDIR/pass1_rc" 2>/dev/null || echo 1)

        if [ "$RC" -ne 0 ]; then
            zenity --error --text="Pass 1 failed.\n$(tail -5 "$TMPDIR/fferr1" 2>/dev/null)"
            continue
        fi

        run_with_progress "Encoding ~${TARGET_SIZE_MB}MB target" \
            -c:v libx264 -b:v "${VIDEO_BR}k" -preset medium $VF \
            -pass 2 -passlogfile "$TMPDIR/ffmpeg2pass" -c:a aac -b:a "${AUDIO_BR}k"
        RC=$?
        if [ "$RC" -ne 0 ]; then
            [ "$RC" -eq 1 ] && continue
            zenity --error --text="Pass 2 failed.\n$(tail -5 "$TMPDIR/fferr" 2>/dev/null)"
            continue
        fi

    else
        run_with_progress "Compressing" \
            -c:v libx264 -crf "$CRF" -preset medium $VF -c:a aac -b:a 64k
        RC=$?
        if [ "$RC" -ne 0 ]; then
            [ "$RC" -eq 1 ] && continue
            zenity --error --text="Compression failed.\n$(tail -5 "$TMPDIR/fferr" 2>/dev/null)"
            continue
        fi
    fi

    if [ ! -f "$OUTPUT" ] || [ ! -s "$OUTPUT" ]; then
        notify "Failed" "Output file is empty"
        zenity --error --text="Output is empty. Try different settings."
        continue
    fi

    ORIG_SIZE=$(stat -c%s "$INPUT")
    NEW_SIZE=$(stat -c%s "$OUTPUT")
    REDUCTION=$(( (ORIG_SIZE - NEW_SIZE) * 100 / ORIG_SIZE ))

    notify "Done" "$BASENAME: $(numfmt --to=iec "$ORIG_SIZE") -> $(numfmt --to=iec "$NEW_SIZE") (${REDUCTION}% smaller)"

    zenity --info --title="$TITLE" \
        --text="Done!\n\nOriginal: $(numfmt --to=iec "$ORIG_SIZE")\nCompressed: $(numfmt --to=iec "$NEW_SIZE")\nSaved: ${REDUCTION}%\n\nOutput:\n$OUTPUT" \
        --width=450

done
