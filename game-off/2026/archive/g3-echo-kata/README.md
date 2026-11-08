# Echo Kata (g3-echo-kata)

Record three 6 s takes. Earlier takes replay as ghosts. Then the Director Cut plays all three together.

Run: `godot --path game-off/2026/archive/g3-echo-kata`
Smoke test: add `-- --smoke` after `--path ...` with `--headless`. It prints `SMOKE OK`.

Controls:
- Touch or mouse: drag in the bottom 40 percent to move the hero (2x relative). Tap there to strike.
- Keyboard: arrows or WASD move, space strikes. Any tap or key restarts after the result.

Feel for: no lag on drag, identical ghost replays, slow-mo ramp plus hit stop plus punch zoom on each Director Cut kill.
Ghosts differ by trail, not color alone: take 1 solid trail and one dot, take 2 dotted trail and two dots.

Known gaps: no sound, strike fires on release (tap detection), smoke check runs at 480 ticks per second.
