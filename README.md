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

`xca/5` is the reference layout. `xca/4` predates it and still uses its own flat layout.
`xca/4/build.sh` reads `../camera` and `../../tools`, which are not in this repo. It does not run until they are moved in.

## Publishing

`.github/workflows/pages.yml` builds `xca/5` and deploys it to GitHub Pages.
Set Settings > Pages > Source to GitHub Actions once.
Downloaded asset packs (`*.zip`) are not committed. Their extracted files live in `game/assets`.
