#!/usr/bin/env bash
# Runs audio_test.gd on the real game project. Fails on a failed check or any engine or script error line.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
game="$(cd "$here/.." && pwd)"
godot="${GODOT:-godot}"

"$godot" --headless --path "$game" --import >/dev/null 2>&1 || true
log="$(mktemp)"
trap 'rm -f "$log"' EXIT
"$godot" --headless --path "$game" --script res://tests/audio_test.gd 2>&1 | tee "$log"
status="${PIPESTATUS[0]}"
if grep -E "SCRIPT ERROR|^ERROR: (Node|Can't|Invalid)|Parse Error" "$log" >/dev/null; then
	echo "audio_test: engine or script error lines found above" >&2
	exit 1
fi
exit "$status"
