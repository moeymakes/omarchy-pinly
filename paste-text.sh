#!/bin/bash

# omarchy:summary=Copy text to the clipboard and type or paste it
# omarchy:group=clipboard
# omarchy:args=[--shift-insert] [--copy-only] [--history-index <index> [--expect <hash>]]
# omarchy:examples=omarchy clipboard paste text "hello" | omarchy clipboard paste text --shift-insert "hello"
# omarchy:hidden=true

. "$(dirname "$0")/paste-keys.sh"
use_shift_insert=false
copy_only=false
history_index=""
expect=""
text=""

while (( $# > 0 )); do
  case "$1" in
    --shift-insert)
      use_shift_insert=true
      shift
      ;;
    --copy-only)
      copy_only=true
      shift
      ;;
    --history-index)
      history_index="${2:-}"
      shift 2
      ;;
    --expect)
      expect="${2:-}"
      shift 2
      ;;
    *)
      break
      ;;
  esac
done

copy_history_entry() {
  local history_path="${CLIPBOARD_HISTORY_PATH:-$HOME/.local/state/omarchy/clipboard-history.json}"

  [[ $history_index =~ ^[0-9]+$ ]] || exit
  jq -e --argjson index "$history_index" '.[$index].type == "text" and (.[$index].text | type == "string")' "$history_path" >/dev/null || exit
  # The caller names the entry it means by the hash of its key. If the file has shifted since the
  # overlay read it (a sync, a write in flight), refuse instead of pasting a different entry.
  if [[ -n $expect ]]; then
    local got
    got=$({ printf 'text:'; jq -j --argjson index "$history_index" '.[$index].text' "$history_path"; } | sha256sum | cut -c1-32)
    [[ $got == "$expect" ]] || exit 1
  fi
  jq -j --argjson index "$history_index" '.[$index].text' "$history_path" | wl-copy
}

paste_is_copy_only && copy_only=true

if [[ -n $history_index ]]; then
  copy_history_entry
  if [[ $copy_only != "true" ]]; then
    use_shift_insert=true
  fi
else
  exit
fi

if [[ $copy_only == "true" ]]; then
  exit
fi

sleep 0.15

send_paste
