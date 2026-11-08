#!/usr/bin/env bash
# Rerenders the GamePix cover and icon. Usage: store/render.sh [frame], default run-5. Run store/shoot.mjs first for fresh frames.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
shot=${1:-run-5}
cp "$here/shots/$shot.png" "$here/cover/assets/shot.png"
cp "$here/shots/$shot.png" "$here/icon/assets/shot.png"
for n in cover icon; do ~/repo/graphics/gfx verify "$here/$n"; done
