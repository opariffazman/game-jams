#!/usr/bin/env bash
# Exports the Godot project and adds the tracker page code and MediaPipe files to build/.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
camera="$here/../camera"
godot="$here/../../tools/godot-4.6.3/Godot_v4.6.3-stable_linux.x86_64"
mkdir -p "$here/build"
"$godot" --headless --path "$here/godot" --export-release Web "$here/build/index.html"
mkdir -p "$here/build/js" "$here/build/vendor" "$here/build/models"
cp "$camera/js/filters.js" "$camera/js/models.js" "$camera/js/camera.js" "$here/build/js/"
# Chrome always has SIMD, so the nosimd and module wasm builds never load.
rm -rf "$here/build/vendor"
mkdir -p "$here/build/vendor/wasm"
cp "$camera/vendor/wasm/vision_wasm_internal.js" "$camera/vendor/wasm/vision_wasm_internal.wasm" "$here/build/vendor/wasm/"
cp "$camera/models/gesture_recognizer.task" "$here/build/models/"
cp "$camera/node_modules/@mediapipe/tasks-vision/vision_bundle.js" "$here/build/vendor/vision_bundle_classic.js"
cp "$here/web/tracker.js" "$here/build/tracker.js"
cp "$here/web/hand_worker.js" "$here/build/hand_worker.js"
cp "$here/web/gestures.js" "$here/web/hologram.js" "$here/build/"
cp "$here/web/bench.html" "$here/web/bench.js" "$here/web/hand3d.js" "$here/web/lab.js" "$here/build/"
python3 -I "$here/web/inject.py" "$here/build/index.html"
cp "$here/web/sw.js" "$here/build/sw.js"
# The version hashes names and sizes, so any changed file gives a new cache and replaces the old one.
cd "$here/build"
files="$(find . -type f ! -name sw.js ! -name '*.map' | LC_ALL=C sort | sed 's#^\./##')"
version="$(for f in $files; do printf '%s %s\n' "$f" "$(stat -c %s "$f")"; done | sha256sum | cut -c1-12)"
list="$(printf '%s\n' $files | python3 -I -c 'import json,sys; print(json.dumps(["./"]+[l.strip() for l in sys.stdin if l.strip()]))')"
sed -i "s#__VERSION__#$version#; s#__FILES__#$list#" sw.js
