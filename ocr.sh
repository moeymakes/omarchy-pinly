#!/bin/bash
# Copy the text found in an image to the clipboard.
# Usage: ocr.sh <image-path>
img=${1:-}
note() { notify-send -a Clipboard -t 3000 "$1" "${2:-}" 2>/dev/null || true; }
[[ -r $img ]] || { note "Text from image" "Image file not found"; exit 1; }
command -v tesseract >/dev/null || { note "Text from image" "Install tesseract to use this"; exit 1; }
text=$(tesseract "$img" - 2>/dev/null | sed -e 's/[[:space:]]*$//')
text=${text%%$'\n'}
if [[ -z ${text//[[:space:]]/} ]]; then note "Text from image" "No text found"; exit 0; fi
printf '%s' "$text" | wl-copy
note "Text copied from image" "${#text} characters"
