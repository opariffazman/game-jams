#!/usr/bin/env bash
# Publishes the packaged build to the gh-pages branch of origin, so GitHub Pages serves it at the top level where the camera prompt works.
# Run build.sh and package.sh first. main stays source only.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
zip=/tmp/home-by-light.zip
[ -f "$zip" ] || { echo "error: $zip is missing, run package.sh first" >&2; exit 1; }
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
unzip -q "$zip" -d "$stage"
touch "$stage/.nojekyll"
remote="$(git -C "$here" remote get-url origin)"
cd "$stage"
git init -q -b gh-pages
git add -A
git commit -q -m "Deploy build $(date -u +%Y-%m-%dT%H:%M:%SZ)"
git push -q --force "$remote" gh-pages
echo "pushed gh-pages"
