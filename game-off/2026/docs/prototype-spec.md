> Historical: the brief the five core-loop prototypes were built from. Paths below use the old `prototypes/` layout. Hot Shift now lives in `game-off/2026/game`, and the retired four in `game-off/2026/archive`.

# Prototype spec (all five games)

Goal: a core-loop prototype the owner can play in a few minutes to judge the feel. Nothing else.

## Tools

- Godot binary: `/home/ariff/.local/share/mise/installs/godot/4.7.2-stable/godot`. Call it by this full path. The `godot` shim has no version set.
- Write code to the Godot 4.6 API. The binary is 4.7.2 and runs 4.6 code.
- Before writing any `.gd` file or shader, invoke the `godot-gdscript-style` skill. If the Skill tool is missing, read `/home/ariff/repo/game-off-2026/.claude/skills/godot-gdscript-style/SKILL.md` and the reference file for each topic you touch.
- Never create or modify `.uid` files, `.import` files, or the `.godot/` directory. Godot generates them.
- Do not run `git commit`. Do not touch files outside your own project directory.

## Project shape

- Create `prototypes/<slug>/` with its own `project.godot`, `main.tscn`, and `scripts/`.
- Renderer: `gl_compatibility`.
- Window: 540 x 960. Stretch mode `canvas_items`, aspect `keep`. Orientation portrait.
- Main scene opens straight into play. No title screen, no menu. Add a one-line hint `Label` at the start that fades after the first input.
- Tapping after a win or loss restarts in under 200 ms.

## Input

- Handle `InputEventMouseButton` and `InputEventMouseMotion` only. Godot emulates mouse from touch, so one code path serves phone and desktop.
- Keep a keyboard fallback for desktop testing and name it in the README.
- Every input must change the screen in the same frame. No input queue, no animation delay before the result starts.
- All input zones sit in the bottom 40 percent of the screen. Targets are at least 48 px.

## Assets and look

- Shapes only. Use `_draw()`, `Polygon2D`, `Line2D`, and `ColorRect`. No imported images, fonts, or audio files.
- Palette: background `#08080c`, magenta `#ff2e88`, cyan `#19e3ff`, amber `#ffb020`, ink `#f6f6f8`.
- Characters are stick-figure silhouettes: a circle head, line limbs, drawn in code. A new pose is a new set of line endpoints.
- Feel is the point. Add these, each in a few lines: hit stop of about 60 ms, a camera punch zoom on a kill, short bullet trails with `Line2D`, a small particle burst with `CPUParticles2D`.
- Flash-safe: never flash the full screen. Keep any flash small and under three per second.
- Sound is optional. If you add it, synthesize a short click or thump in code with `AudioStreamWAV`.

## Quality bar

- Static typing on every var, parameter, and return value. A `##` doc comment on every class, signal, enum, const, exported var, and public function.
- Keep the code small and readable. Prefer a few scripts of under 250 lines each.
- Run the project headless to check for parse errors and runtime errors:
  `/home/ariff/.local/share/mise/installs/godot/4.7.2-stable/godot --headless --path prototypes/<slug> --quit-after 300`
  The output must have no `ERROR` or `SCRIPT ERROR` lines. Fix every one.
- You cannot see the screen. Add one scripted self-play check that runs headless, feeds a few synthetic inputs through the real input path, and prints `SMOKE OK` when the loop completes (play, win or lose, restart). Gate it behind a `--smoke` user argument so it never runs in normal play.

## Deliverables

- `prototypes/<slug>/README.md` of at most 15 lines: run command, controls (touch and keyboard), what to feel for, known gaps.
- A final report of at most 10 lines: what works, the smoke test result, anything unfinished. State errors plainly.
