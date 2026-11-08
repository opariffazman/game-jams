# Kata Beat (g4-kata-beat)

Portrait one-thumb rhythm gun-fu. Theme SHIFT: each lane is a different move.

Run: `godot --path game-off/2026/archive/g4-kata-beat`
Smoke test: add `--headless -- --smoke`. It prints `SMOKE OK`.

Controls: tap the three big pads (PUNCH cyan circle, KICK magenta square, SHOOT amber triangle). Keyboard: A S D or J K L.

Feel for: taps locked to the kick, same-frame pose and pad flash, 30 ms hit stop, finishers at combo 8, 16 and 24.
Tune timing with `LATENCY_OFFSET_MS` in `scripts/main.gd`. Good verdicts show early or late to guide it.

Known gaps: audio sync is untested on a real browser or phone. Output latency on web can need a manual offset. One 32 s song, no difficulty levels. A tap within 110 to 200 ms of a note is a miss, farther away is a free tap.
