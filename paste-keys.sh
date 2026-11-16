#!/bin/bash
# Shared by the paste scripts. CLIPBOARD_PASTE_MODE: shift-insert (default), ctrl-v, ctrl-shift-v, copy.

# True when the mode means "only put it on the clipboard".
paste_is_copy_only() { [[ ${CLIPBOARD_PASTE_MODE:-shift-insert} == "copy" ]]; }

# Sends the paste shortcut for the chosen mode.
send_paste() {
  case "${CLIPBOARD_PASTE_MODE:-shift-insert}" in
    ctrl-v) wtype -M ctrl -k v -m ctrl 2>/dev/null || true ;;
    ctrl-shift-v) wtype -M ctrl -M shift -k v -m shift -m ctrl 2>/dev/null || true ;;
    copy) ;;
    *) wtype -M shift -k Insert -m shift 2>/dev/null || true ;;
  esac
}
