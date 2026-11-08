#!/usr/bin/env bash
# Plays every gesture clip through the real tracker at a small viewport, so software GL leaves the tracker near 12 fps.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
export VW=320 VH=180
for spec in "flick_r 16" "flick_l 16" "flick_d 16" "flick_u 16" "flick_r_quick_return 16" "rest 20" "drift 14" "walk 8"; do
  set -- $spec
  node "$here/gestures.mjs" "/tmp/gest/$1.y4m" "$2"
done
