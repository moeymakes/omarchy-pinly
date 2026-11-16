#!/bin/bash
# Open an image in Omarchy's screenshot editor: omasnap on current Omarchy, tensaku-edit on older installs.
# Usage: annotate.sh <image-path>
path=${1:-}
[[ -r $path ]] || exit 1
if command -v omasnap >/dev/null 2>&1; then
  exec omasnap --notify "$path"
elif command -v tensaku-edit >/dev/null 2>&1; then
  exec tensaku-edit "$path"
fi
echo "No screenshot editor found (omasnap or tensaku-edit)" >&2
exit 1
