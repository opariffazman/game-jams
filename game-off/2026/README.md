# Game Off 2026: Hot Shift

Theme: SHIFT. Godot 4 (4.6 API, GL Compatibility), web export, portrait, one thumb.

Tap a gunman to shift places with him. The hero strikes the nearest gunman, and the others fire at the spot you left, so a good shift turns the room on itself. A night is 12 generated rooms (4 floors of 3, then a 3-phase boss). A failed room costs a heart and retries the same room. Zero hearts ends the night. Money buys upgrades in the Locker.

| Path | Holds |
|---|---|
| `game/` | The Godot project. `game/README.md` lists rules, keys, demos, and the pool generator. |
| `scripts/` | `export.sh` (web export), `serve.sh` and `serve.py` (HTTPS on the LAN for phone tests). |
| `docs/brief/` | The jam brief. |
| `docs/design/` | The Lavish boards: five-game proposals, the gun-fu round, and the roguelite run direction. |
| `docs/prototype-spec.md` | The shared brief the five core-loop prototypes followed. |
| `archive/` | Four retired prototypes (Time Thumb, Echo Kata, Kata Beat, Duel Shift). Each is its own Godot project. |

## Run

- Play: `godot --path game-off/2026/game`.
- Check: `godot --headless --path game-off/2026/game -- --smoke` prints `SMOKE OK`. Run `--import` once on a fresh clone.
- Phone: `GODOT=/path/to/godot game-off/2026/scripts/export.sh`, then `game-off/2026/scripts/serve.sh`. Open the printed `https://` link and accept the certificate warning.
- Rooms: `data/pool.json` holds the generated rooms. Regenerate with `-- --gen` (about 3 minutes).

## Status

- Built and smoke-tested: the run, boss, Locker, boons, shield and knife gunmen, turn events, undo, dead-end banner, and the 3D replay, death reel, and best-chain recap.
- Cover blocks are off (`Rooms.COVER_ENABLED`) until they get one consistent rule.
- Godot 4.6.3 (the CI version): import, a headless run, and `--smoke` pass on a fresh copy. The game was built on 4.7.2.
- Not tried: play on a real phone, the web clipboard and `?seed=` start, and the web export with the 4.6.3 templates (needs a CI run).
- Not built: heat, barrel, shotgun, ricochet, assist mode, the itch.io page.
- Floors 1 and 2 measure close in difficulty (random-tap win rate 0.33 and 0.29).
