#!/bin/bash
# Merge clipboard pins and groups with the other machine over SSH.
# Union by content: nothing is deleted on either side, so an entry unpinned on one
# machine comes back from the other. Image pins are never sent or accepted (their paths are local).
# Usage: sync.sh [--dry-run]     Peer alias: $CLIPBOARD_SYNC_PEER (set in the plugin settings)
#
# Everything the peer sends is untrusted: only plain text pins and well-formed groups are taken.
# Documents are passed to jq as files (--slurpfile), never as arguments, so a large pins file
# cannot hit the kernel's argument-size limit and half-write the other machine.
set -euo pipefail

PEER=${CLIPBOARD_SYNC_PEER:-}
[[ -n $PEER ]] || { echo "Set an SSH peer in settings first"; exit 1; }
# A leading "-" would be read by ssh as an option (for example -oProxyCommand=...).
[[ $PEER =~ ^[A-Za-z0-9_][A-Za-z0-9._@:%-]*$ ]] || { echo "Sync failed: the SSH peer name is not valid"; exit 1; }

DIR=${CLIPBOARD_PINS_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/omarchy}
PINS=$DIR/clipboard-pins.json
CFG=$DIR/clipboard-pins-settings.json
dry=false; [[ ${1:-} == "--dry-run" ]] && dry=true

r() { ssh -o BatchMode=yes -o ConnectTimeout=6 -- "$PEER" "$@"; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail() { echo "Sync failed: $1"; exit 1; }

r true 2>/dev/null || fail "$PEER is offline or unreachable"

r 'cat ~/.local/state/omarchy/clipboard-pins.json 2>/dev/null || echo "[]"' > "$tmp/rpins.json" || fail "could not read pins from $PEER"
r 'cat ~/.local/state/omarchy/clipboard-pins-settings.json 2>/dev/null || echo "{}"' > "$tmp/rcfg.json" || fail "could not read settings from $PEER"
if [[ -f $PINS ]]; then cp "$PINS" "$tmp/lpins.json"; else echo '[]' > "$tmp/lpins.json"; fi
if [[ -f $CFG ]]; then cp "$CFG" "$tmp/lcfg.json"; else echo '{}' > "$tmp/lcfg.json"; fi

for f in rpins lpins; do
  jq -e 'type=="array"' "$tmp/$f.json" >/dev/null 2>&1 || fail "pins file is not valid JSON ($f)"
done
for f in rcfg lcfg; do
  jq -e 'type=="object"' "$tmp/$f.json" >/dev/null 2>&1 || fail "settings file is not valid JSON ($f)"
done

# What we accept from either side: text pins only. The overlay also reads "kind" as a type
# alias, so both fields are checked; anything else (images, odd shapes) is ignored.
jq 'map(select(type == "object" and (.type // .kind) == "text" and (.text | type) == "string"))' "$tmp/rpins.json" > "$tmp/rtext.json"
jq 'map(select(type == "object" and (.type // .kind) == "image"))' "$tmp/rpins.json" > "$tmp/rimages.json"

jq -n --slurpfile l "$tmp/lpins.json" --slurpfile r "$tmp/rtext.json" '
  def key: "text:" + (.text // "");
  ($l[0] + $r[0]) as $all
  | reduce $all[] as $e ([]; if any(.[]; key == ($e | key)) then . else . + [$e] end)' > "$tmp/merged.json" || fail "merge error"

jq -n --slurpfile l "$tmp/lcfg.json" --slurpfile r "$tmp/rcfg.json" '
  def ok: select(type == "object" and (.id | type) == "string" and (.name | type) == "string");
  ((($l[0].groups // []) | map(ok)) + (($r[0].groups // []) | map(ok))) as $all
  | reduce $all[] as $g ([]; if any(.[]; .id == $g.id) then . else . + [$g] end)' > "$tmp/groups.json" || fail "group merge error"

# The peer keeps its own image pins untouched; it gets our merged text pins.
jq -s '(.[0] | map(select((.type // .kind) != "image"))) + .[1]' "$tmp/merged.json" "$tmp/rimages.json" > "$tmp/remote_new.json" || fail "merge error"
jq -n --slurpfile r "$tmp/rcfg.json" --slurpfile g "$tmp/groups.json" '$r[0] | .groups = $g[0] | .lastGroup = (.lastGroup // "")' > "$tmp/rcfg_new.json" || fail "settings merge error"

here=$(( $(jq length "$tmp/merged.json") - $(jq length "$tmp/lpins.json") ))
there=$(( $(jq length "$tmp/remote_new.json") - $(jq length "$tmp/rpins.json") ))

if [[ $dry == true ]]; then echo "Dry run: +$here here, +$there on $PEER, $(jq length "$tmp/groups.json") groups"; exit 0; fi

# Refuse to write an empty or non-array result over anyone's pins.
for f in merged remote_new; do
  jq -e 'type=="array"' "$tmp/$f.json" >/dev/null 2>&1 || fail "internal error: $f is not a list"
done
jq -e 'type=="object"' "$tmp/rcfg_new.json" >/dev/null 2>&1 || fail "internal error: merged settings are not an object"

umask 077
cp "$tmp/merged.json" "$PINS.tmp" && mv "$PINS.tmp" "$PINS"
if [[ -f $CFG ]]; then
  jq --slurpfile g "$tmp/groups.json" '.groups = $g[0]' "$CFG" > "$CFG.tmp" && mv "$CFG.tmp" "$CFG"
fi

r 'umask 077; mkdir -p ~/.local/state/omarchy && cat > ~/.local/state/omarchy/clipboard-pins.json.tmp && mv ~/.local/state/omarchy/clipboard-pins.json.tmp ~/.local/state/omarchy/clipboard-pins.json' < "$tmp/remote_new.json" || fail "while writing to $PEER"
r 'umask 077; cat > ~/.local/state/omarchy/clipboard-pins-settings.json.tmp && mv ~/.local/state/omarchy/clipboard-pins-settings.json.tmp ~/.local/state/omarchy/clipboard-pins-settings.json' < "$tmp/rcfg_new.json" || fail "while writing settings to $PEER"
echo "Synced: +$here here, +$there on $PEER"
