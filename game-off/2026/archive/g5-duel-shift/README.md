# Duel Shift (g5-duel-shift)

Portrait one-thumb boss duel. Theme: SHIFT.

- Run: `godot --path game-off/2026/archive/g5-duel-shift`
- First run in a fresh clone: add `--import` once (headless) so Godot builds the class cache.
- Smoke test: `godot --headless --path game-off/2026/archive/g5-duel-shift --quit-after 6000 -- --smoke` prints `SMOKE OK`.
- Touch or mouse: tap the LEFT, DUCK, RIGHT pads. Tap the active pad to return to CENTER. Dragging across pads also shifts. Tap after win or loss to restart.
- Keyboard: A = LEFT, S = DUCK, D = RIGHT.
- Rules: LEFT and RIGHT shots hit that stance. CENTER shot hits CENTER (duck dodges). HIGH shot hits everything except DUCK.
- Feel for: instant shift, tell readable at a glance (dashed line + icon + word + shrinking bar), the counter on the third focus pip.
- Known gaps: no sound, no difficulty beyond tell time (0.7 s to 0.4 s by round 6), lane bullets pass through a ducking hero on screen, `main.gd` is about 360 lines.
