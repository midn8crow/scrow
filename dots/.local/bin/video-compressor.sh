#!/usr/bin/env bash
set -u
TITLE="Compressor"
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

compress_photos() {
    files=$(zenity --file-selection --title="Select photos to compress" --multiple \
        --file-filter="Images | *.jpg *.jpeg *.png *.webp *.gif" 2>/dev/null)
    [ -z "$files" ] && return 1
    IFS='|' read -ra PHOTOS <<< "$files"

    qopt=$(zenity --list --title="$TITLE - Photos: Quality" \
        --text="Select quality for ${#PHOTOS[@]} photo(s):" \
        --column="Mode" --column="Description" \
        "Target file size" "Compress each photo to a specific size (e.g. 1MB)" \
        "High Quality" "Quality 90, minimal loss" \
        "Balanced"     "Quality 80, good balance" \
        "Small File"   "Quality 65, small size" \
        "Custom"       "Enter your own quality (1-100)" \
        --extra-button="Back" \
        --width=550 --height=320)
    [ "$qopt" = "Back" ] && return 1
    [ -z "$qopt" ] && return 1
    MODE="quality"
    QUALITY=""
    CONVERT_JPG=""
    case "$qopt" in
        "Target file size")
            TARGET_MB=$(zenity --entry --title="$TITLE - Photos: Target Size" \
                --text="Target size in MB per photo:" --entry-text="1")
            [ -z "$TARGET_MB" ] && return 1
            TARGET_BYTES=$(( TARGET_MB * 1024 * 1024 ))
            MODE="target"
            if zenity --question --title="$TITLE - Photos: Target Size" \
                --text="Convert to JPEG?\n\nJPEG gives the smallest size and reliably hits the target.\nYour original is kept; a new .jpg file is created."; then
                CONVERT_JPG=1
            fi
            ;;
        "High Quality") QUALITY=90 ;;
        "Balanced") QUALITY=80 ;;
        "Small File") QUALITY=65 ;;
        "Custom")
            QUALITY=$(zenity --entry --title="$TITLE - Photos: Quality" \
                --text="Enter quality (1-100):" --entry-text="80")
            [ -z "$QUALITY" ] && return 1
            ;;
    esac

    sizeopt=$(zenity --list --title="$TITLE - Photos: Resize" \
        --text="Resize option (only shrinks if larger):" \
        --column="Option" --column="Description" \
        "Keep Size"   "Keep original dimensions" \
        "Max 2560px"  "Shrink only if larger than 2560px" \
        "Max 1920px"  "Shrink only if larger than 1920px" \
        "Max 1280px"  "Shrink only if larger than 1280px" \
        "Max 720px"   "Shrink only if larger than 720px" \
        --extra-button="Back" \
        --width=500 --height=300)
    [ "$sizeopt" = "Back" ] && return 1
    [ -z "$sizeopt" ] && return 1
    case "$sizeopt" in
        "Keep Size") RESIZE="" ;;
        "Max 2560px") RESIZE="-resize 2560x2560>" ;;
        "Max 1920px") RESIZE="-resize 1920x1920>" ;;
        "Max 1280px") RESIZE="-resize 1280x1280>" ;;
        "Max 720px") RESIZE="-resize 720x720>" ;;
    esac

    if ! command -v gm >/dev/null 2>&1; then
        zenity --error --text="GraphicsMagick (gm) is not installed.\nInstall it with: sudo pacman -S graphicsmagick"
        return 1
    fi

    total=${#PHOTOS[@]}
    rm -f "$TMPDIR/photo_err.log"
    (
        i=0
        for f in "${PHOTOS[@]}"; do
            i=$((i+1))
            if [ "$MODE" = "target" ] && [ "$CONVERT_JPG" = "1" ]; then
                out="${f%.*}-compressed.jpg"
            else
                out="${f%.*}-compressed.${f##*.}"
            fi
            pct=$(( i * 100 / total ))
            if [ "$MODE" = "target" ]; then
                if [ "$CONVERT_JPG" = "1" ]; then
                    tmp="$TMPDIR/photo_tmp.jpg"
                else
                    tmp="$TMPDIR/photo_tmp.${f##*.}"
                fi
                lo=1; hi=98; best_q=1; best_size=0
                small_q=1; small_size=999999999999
                for it in 1 2 3 4 5 6 7 8 9; do
                    mid=$(( (lo + hi) / 2 ))
                    if gm convert "$f" $RESIZE -quality "$mid" "$tmp" 2>>"$TMPDIR/photo_err.log"; then
                        sz=$(stat -c%s "$tmp" 2>/dev/null || echo 0)
                        if [ "$sz" -gt 0 ]; then
                            if [ "$sz" -lt "$small_size" ]; then
                                small_size=$sz; small_q=$mid
                            fi
                            if [ "$sz" -le "$TARGET_BYTES" ]; then
                                best_q=$mid; best_size=$sz
                                lo=$((mid + 1))
                            else
                                hi=$((mid - 1))
                            fi
                        fi
                    else
                        hi=$((mid - 1))
                    fi
                    echo "$pct"
                    echo "# $(basename "$f") testing quality $mid..."
                done
                if [ "$best_size" -gt 0 ]; then
                    USE_Q=$best_q
                else
                    USE_Q=$small_q
                fi
                if gm convert "$f" $RESIZE -quality "$USE_Q" "$out" 2>>"$TMPDIR/photo_err.log"; then
                    if [ "$best_size" -gt 0 ]; then
                        echo "$pct"
                        echo "# $(basename "$f") done (quality $USE_Q)"
                    else
                        echo "$pct"
                        echo "# $(basename "$f") saved, still above target"
                    fi
                else
                    echo "$pct"
                    echo "# FAILED: $(basename "$f")"
                fi
            else
                if gm convert "$f" $RESIZE -quality "$QUALITY" "$out" 2>>"$TMPDIR/photo_err.log"; then
                    echo "$pct"
                    echo "# $(basename "$f") done"
                else
                    echo "$pct"
                    echo "# FAILED: $(basename "$f")"
                fi
            fi
        done
        echo "100"
        echo "# Finished"
    ) | zenity --progress --title="$TITLE - Photos" --text="Processing photos..." --percentage=0 --auto-close 2>/dev/null

    if [ "${PIPESTATUS[1]}" -eq 1 ]; then
        notify "Cancelled" "Photo compression cancelled"
        return 1
    fi

    OK=0
    FAIL=0
    ORIG_TOTAL=0
    NEW_TOTAL=0
    for f in "${PHOTOS[@]}"; do
        if [ "$MODE" = "target" ] && [ "$CONVERT_JPG" = "1" ]; then
            out="${f%.*}-compressed.jpg"
        else
            out="${f%.*}-compressed.${f##*.}"
        fi
        if [ -f "$out" ] && [ -s "$out" ]; then
            OK=$((OK+1))
            ORIG_TOTAL=$(( ORIG_TOTAL + $(stat -c%s "$f") ))
            NEW_TOTAL=$(( NEW_TOTAL + $(stat -c%s "$out") ))
        else
            FAIL=$((FAIL+1))
        fi
    done

    notify "Done" "$OK photo(s) compressed${FAIL:+, $FAIL failed}"
    if [ "$FAIL" -gt 0 ]; then
        zenity --error --title="$TITLE" \
            --text="Compressed: $OK\nFailed: $FAIL\n\nError details:\n$(tail -5 "$TMPDIR/photo_err.log" 2>/dev/null)" \
            --width=450
    else
        zenity --info --title="$TITLE" \
            --text="Photos done!\n\nCompressed: $OK\nTotal size: $(numfmt --to=iec "$ORIG_TOTAL") -> $(numfmt --to=iec "$NEW_TOTAL")\n\nOutputs saved as: *-compressed.jpg/png" \
            --width=450
    fi

    return 0
}

while true; do
    choice=$(zenity --list --title="$TITLE" --text="Choose an action:" \
        --column="Action" "Compress a video" "Compress photos" \
        --width=400 --height=250)
    case "$choice" in
        "Compress photos") compress_photos; continue ;;
        "" ) exit 0 ;;
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
            --extra-button="Back" \
            --width=650 --height=420)
        [ "$preset" = "Back" ] && continue 2
        [ -z "$preset" ] && continue 2

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
                --extra-button="Back" \
                --width=500 --height=280)
            [ "$res_option" = "Back" ] && continue 2
            [ -z "$res_option" ] && continue 2

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
