# Time Thumb (g1-time-thumb)

Run: `godot --path game-off/2026/archive/g1-time-thumb`
Smoke test: add `--headless --quit-after 6000 -- --smoke`. It prints `SMOKE OK`.

Controls:
- Touch or mouse: press in the bottom 40 percent and drag. The hero moves at 2x the drag delta.
- Keyboard: arrow keys or WASD move the hero. Time flows while a key is held. Any key restarts after a loss.
- Tap anywhere after a loss to restart.

Feel for:
- Stop the thumb. Bullets must hang at once. Move a thumb at about 450 px/s for full time.
- The hero follows the thumb with no lag. Dodge between hanging bullets, then nudge to fire.
- Kill feedback: hit stop, camera punch, particle burst, fall pose.

Known gaps: no sound, no title screen, no tuning of difficulty past wave 3 (5 gunmen cap), untested on a real touch device.
