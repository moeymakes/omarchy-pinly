#!/bin/bash
# Copy literal text to the clipboard and paste it into the focused window.
# Usage: paste-literal.sh [--copy-only] <text>
. "$(dirname "$0")/paste-keys.sh"
copy_only=false
file=""
while [[ ${1:-} == --* ]]; do
  case $1 in
    --copy-only) copy_only=true; shift ;;
    --file) file=${2:-}; shift 2 ;;
    *) break ;;
  esac
done
paste_is_copy_only && copy_only=true
if [[ -n $file ]]; then
  [[ -s $file ]] || exit 0
  wl-copy < "$file"
  rm -f "$file"
else
  text=${1-}
  [[ -n $text ]] || exit 0
  printf '%s' "$text" | wl-copy
fi
[[ $copy_only == true ]] && exit 0
sleep 0.15
send_paste
