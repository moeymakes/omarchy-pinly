#!/bin/bash
# Paste several texts one after another, optionally pressing Tab or Enter between them.
# Usage: paste-queue.sh <tab|newline|none> <text>...
. "$(dirname "$0")/paste-keys.sh"
# A queue only makes sense when something is actually pasted.
[[ ${CLIPBOARD_PASTE_MODE:-} == "copy" ]] && CLIPBOARD_PASTE_MODE=shift-insert
sep=${1:-none}; shift
sleep 0.25
count=$#
i=0
for t in "$@"; do
  i=$((i + 1))
  printf '%s' "$t" | wl-copy
  sleep 0.12
  send_paste
  sleep 0.12
  if (( i < count )); then
    case $sep in
      tab) wtype -k Tab 2>/dev/null || true ;;
      newline) wtype -k Return 2>/dev/null || true ;;
    esac
    sleep 0.08
  fi
done
