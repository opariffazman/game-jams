# 48-hour jam checklist

Game: top-down team arena, bots, joystick plus slingshot throw. Web export for GamePix.
Details live in `cheatsheet.md`. Tick each gate before the next block.

## Hours 0-4: core loop

- [ ] Create the project: Godot 4.6.3, `gl_compatibility`, landscape, stretch `canvas_items`.
- [ ] Turn on "Emulate Touch From Mouse".
- [ ] Add `VirtualJoystick` and `ThrowControl` (cheatsheet section 6).
- [ ] Move a `Player` in a walled arena.
- [ ] Throw a `Sandal` that hits a dummy.
- [ ] Gate: one player throws and hits a target at 60 fps in the editor.

## Hours 4-10: web and phone smoke test

- [ ] Export for Web with Thread Support off.
- [ ] Serve over LAN and open on a real phone (cheatsheet section 12).
- [ ] Check touch: joystick and throw work with both thumbs at once.
- [ ] Add the tap-to-start screen (audio unlock, fullscreen).
- [ ] Gate: the loop plays on a phone. Record FPS.

## Hours 10-20: bots and match rules

- [ ] Bake a `NavigationRegion2D`.
- [ ] Add `Bot` with chase, aim, evade.
- [ ] Add teams, health, knockback, respawn.
- [ ] Add score and a round timer.
- [ ] Add win and lose screens with a restart button.
- [ ] Gate: a full 2v2 match finishes from start to result.

## Hours 20-30: tuning and feel

- [ ] Move all numbers into `MoveTuning`, `ThrowTuning`, `BotTuning` resources.
- [ ] Tune on the phone, not the desktop.
- [ ] Add hit stop, screen shake, and squash.
- [ ] Add sounds: throw, hit, win. Use short Ogg files.
- [ ] Make two bot difficulties from two `BotTuning` files.
- [ ] Gate: three testers play a match and want a second one.

## Hours 30-38: content and polish

- [ ] Replace placeholder art. Use one shared atlas.
- [ ] Add a title screen and a how-to-play hint for both controls.
- [ ] Add one arena variation or one power-up. Pick one.
- [ ] Check text contrast and touch target size (at least 48 px).
- [ ] Add a mute button.
- [ ] Gate: art and audio are final or cut.

## Hours 38-44: freeze and harden

- [ ] Feature freeze at hour 38. No new content after it.
- [ ] Fix every crash and every stuck state.
- [ ] Check app-focus loss: tab switch must release both fingers.
- [ ] Check a 10 minute session for slowdown.
- [ ] Check the export size against the GamePix limit (unconfirmed, read the GamePix rules).
- [ ] Test on one Android and one iOS phone.
- [ ] Gate: no known crash.

## Hours 44-48: ship

- [ ] Export the final build. Keep Thread Support off.
- [ ] Open the exported build from a clean browser profile.
- [ ] Write the submission text and take screenshots.
- [ ] Upload at hour 46. Keep 2 hours as buffer.
- [ ] Tag the release commit.
- [ ] Gate: the uploaded build loads and plays from the public URL.

## Cut line

Cut from the bottom first. Never cut an item above the line.

Must keep:
- Joystick, throw, hit, bot, score, restart.
- Phone-tested web build.
- Tap-to-start audio unlock.

Cut in this order when behind:
1. Second arena or power-up.
2. Second bot difficulty.
3. Custom shaders and particles.
4. Squash and screen shake. Keep hit stop and one sound.
5. Title screen polish. Keep a single start button.
6. 3v3 mode. Keep 2v2.
7. Bot evade state. Keep chase and aim.
8. Music. Keep hit and throw sounds.

## Hard rules

- Test on a phone every 4 hours.
- Never start a new feature in the last 10 hours.
- Commit at each gate.
