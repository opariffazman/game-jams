#!/usr/bin/env bash
# Runs the headless match simulator (tests/sim/match_sim.gd) on the real game project.
# Each scenario runs in its own Godot process, all in parallel, so the suite takes about one scenario of wall time.
# Env: GODOT, SIM_SCENARIOS=bots,idle_seat0,idle_seat1,script_seat0,script_seat1,fuzz_seat0,fuzz_seat1,hero_bots,hero_fuzz_seat0,hero_fuzz_seat1  SIM_SEEDS=N|a-b
#      SIM_QUICK=1 (6 seeds)  SIM_TRACE=<seed> (single process, prints per-second bot states)  SIM_RULES=1
# Exit code is not zero on any violation, or on any engine or script error line.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
game="$(cd "$here/.." && pwd)"
godot="${GODOT:-godot}"
scenarios="${SIM_SCENARIOS:-bots,idle_seat0,idle_seat1,script_seat0,script_seat1,fuzz_seat0,fuzz_seat1,hero_bots,hero_fuzz_seat0,hero_fuzz_seat1}"

"$godot" --headless --path "$game" --import >/dev/null 2>&1 || true
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

pids=()
names=()
IFS=',' read -r -a list <<< "$scenarios"
for name in "${list[@]}"; do
	SIM_SCENARIOS="$name" "$godot" --headless --path "$game" --fixed-fps 60 --script res://tests/sim/match_sim.gd >"$work/$name.log" 2>&1 &
	pids+=("$!")
	names+=("$name")
done

status=0
for index in "${!pids[@]}"; do
	wait "${pids[$index]}" || status=1
done
for name in "${names[@]}"; do
	cat "$work/$name.log"
done
if grep -hE "SCRIPT ERROR|^ERROR:|Parse Error" "$work"/*.log >/dev/null; then
	echo "run_sim: engine or script error lines found above" >&2
	exit 1
fi
exit "$status"
