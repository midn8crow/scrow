#!/bin/bash

region=$(slurp 2>/dev/null) || exit 1
text=$(grim -g "$region" -t png - 2>/dev/null | tesseract stdin stdout -l eng+ben --psm 6 2>/dev/null)

if [[ -z "$text" ]]; then
    notify-send "OCR" "No text detected"
    exit 1
fi

echo "$text" | wl-copy
notify-send "OCR" "Text copied to clipboard"
