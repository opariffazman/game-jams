#!/usr/bin/env bash
# Runs the bug 1 touch test against a build in game/build/diagnose served on port 8098.
# Usage: E2E_SCHEME=A E2E_TRIES=20 bash game/tests/e2e/diagnose/run_bug1.sh
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
godot="${GODOT:-/home/ariff/claude-projects/game/tools/godot-4.6.3/Godot_v4.6.3-stable_linux.x86_64}"
port="${E2E_PORT:-8098}"
build_dir="$root/game/build/diagnose"
out_dir="$root/game/tests/e2e/diagnose/out"
scratch="${E2E_SCRATCH:-/tmp/e2e-pw}"

mkdir -p "$build_dir" "$out_dir"
if [[ -z "${E2E_SKIP_EXPORT:-}" ]]; then
	"$godot" --headless --path "$root/game" --export-release Web "$build_dir/index.html" >"$out_dir/export.log" 2>&1 \
		|| { echo "error: web export failed, see $out_dir/export.log" >&2; tail -20 "$out_dir/export.log" >&2; exit 1; }
fi

python3 "$root/scripts/serve.py" "$build_dir" "$port" >"$out_dir/serve.log" 2>&1 &
server_pid=$!
trap 'kill "$server_pid" 2>/dev/null || true' EXIT INT TERM
for _ in $(seq 1 50); do
	curl -s -o /dev/null "http://127.0.0.1:$port/" && break
	sleep 0.1
done

E2E_URL="http://127.0.0.1:$port/" E2E_OUT="$out_dir" E2E_SCRATCH="$scratch" \
	node "$root/game/tests/e2e/diagnose/bug1_touch.mjs"
