#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
godot_bin="${GODOT:-godot}"

if ! command -v "$godot_bin" >/dev/null 2>&1; then
	echo "error: Godot binary '$godot_bin' not found. Put godot on PATH or set GODOT=/path/to/godot." >&2
	exit 1
fi

mkdir -p "$root/game/build/web"
log="$(mktemp)"
trap 'rm -f "$log"' EXIT

if ! "$godot_bin" --headless --path "$root/game" --export-release Web build/web/index.html >"$log" 2>&1; then
	cat "$log" >&2
	echo "error: Godot export failed (see output above)." >&2
	exit 1
fi
cat "$log"

if grep -qE '^(ERROR|SCRIPT ERROR|WARNING)' "$log"; then
	echo "error: Godot export logged errors or warnings (see output above)." >&2
	exit 1
fi

if [[ ! -s "$root/game/build/web/index.html" ]]; then
	echo "error: export produced no game/build/web/index.html." >&2
	exit 1
fi
echo "exported: $root/game/build/web/index.html"
