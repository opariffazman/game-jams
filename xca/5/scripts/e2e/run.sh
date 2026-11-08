#!/usr/bin/env bash
# Drives the exported web game with real multi-touch input in headless Chrome.
# Playwright lives in a scratch dir under /tmp so no dependency enters the repo.
# Set E2E_ONLY=joystick,pass to run only scenarios whose function name contains one of those words.
# Set E2E_SPEC=schemes to run game/tests/e2e/schemes.mjs instead of e2e.mjs.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
godot="${GODOT:-/home/ariff/claude-projects/game/tools/godot-4.6.3/Godot_v4.6.3-stable_linux.x86_64}"
port="${E2E_PORT:-8091}"
build_dir="$root/game/build/e2e"
out_dir="$root/game/tests/e2e/out"
scratch="${E2E_SCRATCH:-/tmp/e2e-pw}"

mkdir -p "$build_dir" "$out_dir"
[[ -z "${E2E_ONLY:-}" ]] && rm -f "$out_dir"/*.png "$out_dir"/report.json || true

# The visuals agent changes game files, so every run exports fresh.
"$godot" --headless --path "$root/game" --export-release Web "$build_dir/index.html" >"$out_dir/export.log" 2>&1 \
	|| { echo "error: web export failed, see $out_dir/export.log" >&2; tail -20 "$out_dir/export.log" >&2; exit 1; }

if [[ ! -d "$scratch/node_modules/playwright-core" ]]; then
	mkdir -p "$scratch"
	(cd "$scratch" && npm init -y >/dev/null && npm i playwright-core pngjs >/dev/null)
fi

python3 "$root/scripts/serve.py" "$build_dir" "$port" >"$out_dir/serve.log" 2>&1 &
server_pid=$!
trap 'kill "$server_pid" 2>/dev/null || true' EXIT INT TERM

for _ in $(seq 1 50); do
	curl -s -o /dev/null "http://127.0.0.1:$port/" && break
	sleep 0.1
done

E2E_URL="http://127.0.0.1:$port/" E2E_OUT="$out_dir" E2E_SCRATCH="$scratch" E2E_ONLY="${E2E_ONLY:-}" \
	node "$root/game/tests/e2e/${E2E_SPEC:-e2e}.mjs"
