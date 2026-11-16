#!/bin/bash
# Helper for the Screenshots tab. Never deletes a file permanently: "trash" moves to the system Trash.
#   shots.sh list <dir>...      files as path<TAB>size<TAB>mtime
#   shots.sh meta <path>...     one JSON line per file: path, hash (sha256, 32 chars), w, h
#   shots.sh thumbs             make missing thumbnails for records in the store (prints each hash done)
#   shots.sh ocr                run OCR on records that have none yet (one JSON line each: hash, text)
#   shots.sh watch <dir>...     print the path of every image written under the folders
#   shots.sh trash <path>       move to the system Trash
#   shots.sh restore <path>     restore from the Trash to the original location
STATE=${CLIPBOARD_PINS_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/omarchy}
STORE=$STATE/clipboard-shots.json
THUMBS=${XDG_CACHE_HOME:-$HOME/.cache}/omarchy/clipboard-thumbs
EXT='\.(png|jpe?g|webp)$'

expand() { local d=$1; [[ $d == "~"* ]] && d="$HOME${d:1}"; printf '%s' "$d"; }

make_thumb() {
  local h=${1%%$'\t'*} p=${1#*$'\t'}
  [[ -r $p ]] || return 0
  vipsthumbnail "$p" -s 360 -o "$THUMBS/$h.webp[Q=80]" 2>/dev/null && printf '%s\n' "$h"
}
export -f make_thumb
export THUMBS

cmd=${1:-}; shift || true
case $cmd in
  list)
    for d in "$@"; do
      d=$(expand "$d"); [[ -d $d ]] || continue
      # Names holding a newline or tab would split into several records, so they are skipped.
      find "$d" -type f ! -path $'*\n*' ! -path $'*\t*' \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \) -printf '%p\t%s\t%T@\n'
    done ;;
  meta)
    for p in "$@"; do
      [[ -r $p ]] || continue
      h=$(sha256sum "$p" | cut -c1-32)
      dims=$(magick identify -format '%w %h' "${p}[0]" 2>/dev/null) || dims="0 0"
      read -r w hh <<<"$dims"
      jq -nc --arg path "$p" --arg hash "$h" --argjson w "${w:-0}" --argjson h "${hh:-0}" '{path:$path,hash:$hash,w:$w,h:$h}'
    done ;;
  thumbs)
    mkdir -p "$THUMBS"; [[ -r $STORE ]] || exit 0
    jq -r '.records[]|select(.trashed!=true and .gone!=true)|[.hash,.path]|@tsv' "$STORE" |
      while IFS=$'\t' read -r h p; do [[ -e $THUMBS/$h.webp ]] || printf '%s\t%s\0' "$h" "$p"; done |
      xargs -0 -P4 -I{} bash -c 'make_thumb "$1"' _ {} ;;
  ocr)
    command -v tesseract >/dev/null || exit 0; [[ -r $STORE ]] || exit 0
    jq -r '.records[]|select(.trashed!=true and .gone!=true and .ocr==null)|[.hash,.path]|@tsv' "$STORE" |
      while IFS=$'\t' read -r h p; do
        [[ -r $p ]] || continue
        t=$(nice -n 15 tesseract "$p" - 2>/dev/null | tr -s '[:space:]' ' ' | cut -c1-4000)
        jq -nc --arg hash "$h" --arg text "$t" '{hash:$hash,text:$text}'
      done ;;
  watch)
    dirs=(); for d in "$@"; do d=$(expand "$d"); [[ -d $d ]] && dirs+=("$d"); done
    [[ ${#dirs[@]} -gt 0 ]] || exit 0
    # A file name with a newline would print a second line that looks like a path elsewhere,
    # so only lines under a watched folder, with no tab, are passed on.
    inotifywait -m -r -q -e close_write -e moved_to --format '%w%f' "${dirs[@]}" | grep -i -E --line-buffered "$EXT" |
      while IFS= read -r line; do
        [[ $line == *$'\t'* ]] && continue
        for d in "${dirs[@]}"; do [[ $line == "$d"/* ]] && { printf '%s\n' "$line"; break; }; done
      done ;;
  trash)
    [[ -e ${1:-} ]] || exit 1
    gio trash -- "$1" ;;
  restore)
    p=${1:-}; [[ -n $p ]] || exit 1
    # Several trashed files can share one original path; restore the most recently trashed one.
    best=""; best_date=""
    while IFS= read -r entry; do
      d=$(gio info -a trash::deletion-date "$entry" 2>/dev/null | awk -F': ' '/deletion-date/ {print $2}')
      if [[ -z $best || $d > $best_date ]]; then best=$entry; best_date=$d; fi
    done < <(gio trash --list 2>/dev/null | P="$p" awk -F'\t' '$2==ENVIRON["P"] {print $1}')
    [[ -n $best ]] || { echo "not in the Trash"; exit 1; }
    gio trash --restore "$best" ;;
  *) echo "usage: shots.sh list|meta|thumbs|ocr|watch|trash|restore" >&2; exit 2 ;;
esac
