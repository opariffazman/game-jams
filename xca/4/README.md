# Home by Light

A post-apocalyptic lane runner for the web, made in Godot 4.6 for the Xsolla Halloween Game Jam on GamePix.
Flick, swipe or use hand tracking through the webcam to steer. Clean your weapon at the campfire and get home.

## Run it

- `GODOT=/path/to/godot scripts/build.sh` exports the Godot web build to `build/`.
- `python3 scripts/serve.py` serves it over HTTPS on port 8446. The camera needs HTTPS. Create a local certificate in `cert/` first.
- `scripts/package.sh` zips `build/` for GamePix, with `index.html` at the zip root.
- `?quality=low` or `?quality=high` forces a quality tier. `?debug` shows the debug panel.

## Camera

Hand tracking runs in the browser with MediaPipe. Nothing leaves the device.
A host that blocks camera access inside its iframe leaves touch and mouse control only.

## Licence

The game is released under CC0 1.0. See `LICENSE`.

## Credits

- 3D models and characters: Quaternius, CC0 (Zombie Apocalypse Kit, Survival Pack)
- UI icons: Kenney, CC0
- UI icons: Lorc, Delapouite, John Colburn and Sbed from game-icons.net, CC BY 3.0
- Music: made with Suno under a paid plan that includes commercial use
- Hand tracking: MediaPipe, Apache 2.0
- Font: Atkinson Hyperlegible Next, SIL OFL 1.1
