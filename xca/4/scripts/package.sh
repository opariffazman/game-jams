#!/usr/bin/env bash
# Zips the existing build/ for GamePix with index.html at the zip root. Run build.sh first.
# The dev pages stay in build/ for the tests, but the zip omits them because nothing in the game loads them.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out=/tmp/home-by-light.zip
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
[ -f "$here/build/index.html" ] || { echo "error: build/index.html is missing, run build.sh first" >&2; exit 1; }
cp -r "$here/build/." "$stage/"
cd "$stage"
dev_pages=(bench.html bench.js hand3d.js lab.js)
rm -f "${dev_pages[@]}"
# The service worker precaches its file list, so a removed file there would fail the install.
python3 -I - "$stage/sw.js" "${dev_pages[@]}" <<'PY'
import re, sys
path, dev = sys.argv[1], set(sys.argv[2:])
text = open(path).read()
match = re.search(r'const FILES = (\[.*?\]);', text)
import json
files = [f for f in json.loads(match.group(1)) if f not in dev]
open(path, 'w').write(text.replace(match.group(0), 'const FILES = ' + json.dumps(files) + ';'))
PY
rm -f "$out"
zip -qr -X "$out" . -x '*.map'
unzip -l "$out" | grep -q ' index.html$' || { echo "error: index.html is not at the zip root" >&2; exit 1; }
ls -l "$out" | awk '{print "zip bytes: " $5}'
unzip -Z1 "$out" | grep -v / | tr '\n' ' '; echo
