# Game jams

One directory per jam entry, under the jam series folder.

| Path | Game | Engine |
|---|---|---|
| `xca/4` | Home by Light | Godot 4.6, web |
| `xca/5` | Baling Selipar | Godot 4.6.3, web |

## Layout for a new entry

- `game/` holds the engine project.
- `scripts/` holds `export.sh`, `serve.sh` and the end-to-end runner.
- `docs/` holds the design, research and engine notes.
- `store/` holds the cover and icon for the portal.
- `GAMEPIX.md` holds the portal checklist.

Both entries use this layout. `xca/4` also keeps `tests/`, `tools/` and `web/`.
`xca/4/scripts/build.sh` and `xca/4/tests/gestures_unit.mjs` read `xca/camera`, which is not in this repo. They do not run until it is moved in.
`xca/4/scripts/deploy-pages.sh` force-pushes a `gh-pages` branch. Do not use it while Pages deploys from Actions.

## Publishing

`.github/workflows/pages.yml` deploys one site to GitHub Pages. `site/` is the landing page and `site/games.json` lists the games.
Each game is built into its own folder, for example `xca/5` into `baling-selipar/`.
To add a game, add a row to `site/games.json` and a build and copy step to the workflow.
Home by Light (`xca/4`) is not listed yet, because its build needs `xca/camera`.
Set Settings > Pages > Source to GitHub Actions once.
Downloaded asset packs (`*.zip`) are not committed. Their extracted files live in `game/assets`.
