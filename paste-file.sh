#!/bin/bash
# Copy an image file to the clipboard and paste it (derived from Omarchy's omarchy-clipboard-paste-file).
# Usage: paste-file.sh [--copy-only] <mime-type> <path>
. "$(dirname "$0")/paste-keys.sh"
copy_only=false
if [[ ${1:-} == "--copy-only" ]]; then copy_only=true; shift; fi
paste_is_copy_only && copy_only=true
mime=${1:-}
path=${2:-}
if [[ -z $mime || -z $path ]]; then echo "Usage: paste-file.sh [--copy-only] <mime-type> <path>" >&2; exit 1; fi
[[ -r $path ]] || exit 1
wl-copy --type "$mime" < "$path"
[[ $copy_only == true ]] && exit 0
sleep 0.15
send_paste
