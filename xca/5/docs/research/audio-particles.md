# Audio and particles plan (Kenney CC0 packs)

Status: plan only. No file under `game/` was modified. Packs were extracted to `/tmp/kenney-audio/{impact,ui,voice,particles}` and read, never run.

All four packs are CC0 (their `License.txt` says Creative Commons Zero). Source: https://kenney.nl.

## Decisions

- Audio: ship 30 ogg files, about 235 KB. Budget is 3 MB.
- Voice-over: ship (user decision, 2026-11-08). Details in section 2.
- Particles: `CPUParticles2D` in one shared 2D overlay. About 8 sprites, resized to 128 px.
- One new autoload, `Audio`. Particles use a scene, `FxLayer`, with a static wrapper `FxRef`.

## 1. Inventory

All sound files are ogg Vorbis, 44.1 kHz stereo. Sizes are bytes from the extracted zips. Copy only the files below into `game/assets/audio/`. Never copy the zips.

| Pack | Files to use | Count | Size each | Total |
|---|---|---|---|---|
| Impact Sounds (`Audio/`) | `impactWood_medium_000..002.ogg`, `impactWood_heavy_000..001.ogg`, `impactPunch_medium_000..002.ogg`, `impactPunch_heavy_000..001.ogg`, `impactSoft_medium_000..001.ogg`, `impactSoft_heavy_000..001.ogg`, `impactPlank_medium_000..001.ogg`, `impactBell_heavy_004.ogg`, `impactMetal_light_000..001.ogg`, `footstep_grass_000..002.ogg` | 22 | 5.4 to 12 KB | about 190 KB |
| UI Audio (`Audio/`) | `click1.ogg`, `click2.ogg`, `click3.ogg`, `switch2.ogg`, `switch14.ogg`, `rollover1.ogg`, `mouseclick1.ogg`, `mouserelease1.ogg` | 8 | 4.5 to 6 KB | about 45 KB |
| Voice-over | `voice/Male/` base set | about 9 | about 9 KB each | about 80 KB |
| Particle Pack (`PNG (Transparent)/`) | see section 4 | 8 | 25 to 115 KB at 512 px | about 450 KB at 512 px, about 40 KB at 128 px |

Notes:

- The impact pack has no wav. Everything is ogg. Impact files are stereo, which doubles the decode memory. Optional step: downmix to mono in the import dialog or with `ffmpeg -ac 1` before copying.
- Skip `Preview*.ogg` files. `Preview (Female).ogg` is 586 KB and is not a game asset.
- Skip `footstep_*` other than grass unless the user wants footsteps. Footsteps are a cut candidate (see open questions).
- The particle PNGs are 512 x 512. Resize to 128 x 128 for the game. On screen the largest particle is under 64 px, and 128 px keeps it sharp on a 2x phone.

## 2. Event map

Volumes are `volume_db` at the player. Pitch is a random `pitch_scale` range. Cap is the number of simultaneous voices of that group. A group is one pooled player set (see section 3).

| Event | Source file(s) (random pick) | Hook point | dB | Pitch | Cap |
|---|---|---|---|---|---|
| Throw release | `impactSoft_heavy_000..001` | `Character.throw_sandal` and `Character.throw_manual`, after `threw.emit(sandal)` (listen to `Character.threw`) | -6 | 0.95-1.10 | 3 |
| Sandal hits character (topple phase, blocked by defender) | `impactWood_medium_000..002` | `Sandal._check_character_hits`, on `hit_character` | -4 | 0.9-1.1 | 3 |
| Pass sandal kills attacker | `impactPunch_heavy_000..001` | `RoundManager._on_pass_hit`, next to the existing `hit_stop` call | -2 | 0.9-1.05 | 2 |
| Sandal hits sandal | `impactWood_heavy_000..001` | `Sandal` `body_entered` (needs `contact_monitor` and `max_contacts_reported`, unconfirmed), gated by relative speed above a `Tuning` value | -8 to -3 by speed | 0.9-1.15 | 3 |
| Stack topple | `impactPlank_medium_000..001` plus `impactWood_heavy_000` | `Stack._topple`, on `toppled` | -2 | 0.9-1.0 | 1 |
| Sandal pickup | `click2.ogg` | `Character.pick_up` (success branch) | -10 | 0.95-1.05 | 2 |
| Sandal place on stack | `impactWood_medium_000` | `Stack.place_sandal` | -8 | 1.0-1.15 (raise per `placed_count`) | 2 |
| Stack rebuilt | `impactBell_heavy_004` | `Stack.rebuilt` signal | -6 | 1.0 | 1 |
| Pass | `impactSoft_medium_000..001` | `Character.passed` signal | -8 | 1.0-1.15 | 2 |
| Catch (receiver takes pass sandal) | `impactSoft_heavy_000` | `Character.pick_up` when `sandal.is_pass_sandal` | -8 | 1.05-1.2 | 2 |
| Dash | `footstep_grass_000..002` at pitch 1.4-1.6 | `Character.dashed` signal | -8 | 1.4-1.6 | 1 |
| Death (mati) | `impactMetal_light_000..001` plus `impactPunch_medium_000` | `Character.died` signal | -4 | 0.85-1.0 | 2 |
| Round start | `switch14.ogg` | `RoundManager.phase_changed` to `TOPPLE` | -8 | 1.0 | 1 |
| Round end, human wins | `impactBell_heavy_004` at pitch 1.1 | `RoundManager.round_ended` where winner is the human team | -6 | 1.1 | 1 |
| Round end, human loses | `impactSoft_heavy_001` at pitch 0.7 | `RoundManager.round_ended` where winner is the other team | -6 | 0.7 | 1 |
| Coin flip | `click1.ogg` three times, 80 ms apart, then `switch2.ogg` | `RoundManager.phase_changed` to `COIN_FLIP` | -8 | 0.9, 1.0, 1.1 | 1 |
| Match end, win | `impactBell_heavy_004` x2 at 1.0 then 1.25 | `RoundManager.match_ended` | -4 | see left | 1 |
| Match end, loss | `impactSoft_heavy_001` at pitch 0.6 | `RoundManager.match_ended` | -4 | 0.6 | 1 |
| UI tap (gear, tiles, restart button) | `click1..3` | `SettingsLayer._activate`, `RestartButton` press | -10 | 0.97-1.03 | 2 |
| Toggle on or off (haptics, sound, scheme tile) | `switch2.ogg` on, `switch14.ogg` off | `Settings.haptics_changed`, `Settings.scheme_changed`, `Settings.sound_changed` | -10 | 1.0 | 1 |
| Restart hold progress | `rollover1.ogg` on hold start | `RestartButton` hold begin | -14 | 1.0 | 1 |
| Restart confirmed | `mouserelease1.ogg` | `RestartLayer` confirm | -8 | 1.0 | 1 |
| Virtual stick or fire button press | `mouseclick1.ogg` | `FireButton.pressed`, `AimStick.pressed` | -16 | 0.97-1.03 | 1 |

Rules:

- Every throw kind goes through one function, `Audio.play(slot)`. Slot names come from an `AudioSet` resource, as the GDD says.
- Slow-mo: `Engine.time_scale` also scales audio pitch only if the bus is pitched. Do not add a pitch shift effect. Sample playback on web does not support effects anyway.
- Hit stop sets `time_scale` to 0. Players use `PROCESS_MODE_ALWAYS` so a hit sound plays during the freeze.

### Voice-over

Decision (user, 2026-11-08): ship it. The tournament fight feel needs an announcer. The no-words rule covers UI text only. Voice is audio.

- Source: `voice/Male/`, English only, on the `Voice` bus. Mute follows the sound toggle.
- Round start: `round.ogg`, then `go.ogg`. Final round: `final_round.ogg`. Countdown: `3.ogg`, `2.ogg`, `1.ogg` on the coin flip.
- Match end: `you_win.ogg`, `you_lose.ogg`.
- Extra hype lines can be picked later: `war_target_destroyed.ogg` on a kill, `power_up.ogg` on a dash. Pick by playtest, one line per event, rate-limited to one voice at a time.
- Cost: about 80 KB for the base set.
- Risk: English only for a worldwide GamePix audience. The icons carry the meaning, so the voice is flavour and never required to play.

## 3. Audio architecture

### Bus layout

Create `game/default_bus_layout.tres` in Godot. Godot loads it by default from the project root.

| Bus | Send | Use |
|---|---|---|
| Master | output | Mute target. Volume 0 dB. |
| Sfx | Master | World sounds. |
| Ui | Master | Taps and toggles. Keep louder than Sfx by 2 dB so a tap is audible during a busy scatter. |
| Voice | Master | Empty for now. Reserved. |

No effects on any bus. Web sample playback ignores them.

### Audio autoload

File `game/autoload/audio.gd`, registered as `Audio="*res://autoload/audio.gd"` after `Settings`.

- `process_mode = PROCESS_MODE_ALWAYS`, same as `GameFeel`, so sounds play during hit stop and the settings pause.
- One `AudioSet` resource (`game/assets/audio/audio_set.tres`) maps slot `StringName` to an array of `AudioStream`, plus per-slot `volume_db`, `pitch_min`, `pitch_max`, `cap`.
- One pool per slot group: `cap` `AudioStreamPlayer` nodes, created in `_ready`. Never `instantiate` per sound. Use round robin, then `stop()` and `play()` on the oldest when all are busy. Do not use `max_polyphony` on the web: the polyphony docs say a new `play()` cuts the oldest voice, which is the same result but one node is harder to read in tests.
- Read `AudioStreamRandomizer` option: one `AudioStreamRandomizer` per slot gives random pick and pitch range in a resource, so `Audio.play` stays one line. Check it works under Sample playback on web before choosing it (unconfirmed). Fallback is the manual pick in code.
- Public API: `play(slot: StringName, volume_offset_db: float = 0.0)`, `set_muted(muted: bool)`. Mute sets `AudioServer.set_bus_mute(0, muted)`.
- Connect to game signals in one place. `Audio` listens to `RoundManager` and characters through a `bind_round(round_manager)` call made from `main.tscn` setup. Gameplay scripts do not call `Audio` directly, except `Stack` and `Sandal` which have no signal for placing and sandal-on-sandal contact. Add `placed` and `sandal_hit(speed)` signals there.
- Use `SettingsRef`-style static wrapper `AudioRef` (`scripts/core/audio_ref.gd`), same pattern as `settings_ref.gd`, so `--script` headless tests compile when the autoload is absent.

### Web rules

| Rule | Detail |
|---|---|
| Unlock | `web/shell.html` already has the TAP TO PLAY overlay and `onStart` on click (line 319). Engine starts inside that click, so the browser audio context is allowed to run. Add no extra unlock code. Check on Android Chrome that the first sound plays without a second tap. |
| Playback type | Godot 4.6 web exports use Sample playback by default. This gives low latency with `thread_support=false` (as in `export_presets.cfg`). Keep the default. Do not set Stream. |
| Sample limits | No audio effects, no reverb, no procedural audio. The plan uses none. Positional audio is unreliable, so use plain `AudioStreamPlayer`, never `AudioStreamPlayer2D`. |
| Latency | Project setting `audio/driver/output_latency.web` defaults to 50 ms. Keep 50. Lowering it risks crackle on mobile. Do not add the setting unless the default is wrong in the e2e run. |
| Sample rate | Mix rate is the browser rate. Files are 44.1 kHz. No resample action needed. |
| Import | Keep ogg. For short effects set Loop off. Optional: mono downmix to halve memory. |
| Pause | `SettingsLayer` pauses the tree. Players run in `ALWAYS` mode, so the settings click and toggle sound play. |

### Mute toggle

- Add `sound_enabled: bool = true` and `set_sound(enabled)` to `autoload/settings.gd`. Add signal `sound_changed(enabled)`. Persist key `"sound"` in the same `controls` section, next to `haptics`. Follow the exact shape of `haptics_enabled`.
- The GDD already lists "master sound on or off toggle if sound exists".
- Settings panel: one more round tile beside the haptics tile in `ui/settings/settings_layer.gd`. Icons from game-icons.net, copy into `game/assets/icons/`, and add rows to `CREDITS.md` (CC BY 3.0):
  - On: `delapouite/speaker` (or `lorc/sound-on`). Name: `sound_on.svg`.
  - Off: `delapouite/speaker-off` (or `lorc/sound-off`). Name: `sound_off.svg`.
  - Confirm exact slugs on game-icons.net before copying (unconfirmed).
- The tile switches icon and keeps the ring style of the active tiles. No words.
- `Audio` reads `Settings.sound_enabled` in `_ready` and listens to `sound_changed`. The toggle click plays before mute turns on and not after, so an "off" tap is still heard once.

### Haptics interplay

- `Settings.vibrate` stays separate. A mute does not change haptics, and haptics off does not change sound.
- Pair events: throw release, topple, death and pass kill already match haptic calls (`haptic_fire_ms` and others in `Tuning`). Call `Audio.play` and `SettingsRef.vibrate` from the same signal handler so they stay in step.
- Android Chrome silent-switch: a muted phone still vibrates. Good. Nothing to add.
- Desktop and iOS: `vibrate` is a no-op, sound is the only feedback. Keep sound loud enough alone.

## 4. Particles

### Technique

Use `CPUParticles2D`. Reasons:

- `gl_compatibility` on web (WebGL 2) runs `GPUParticles2D`, but the particle pass costs a transform feedback step and one-shot GPU particles have known first-frame delays and no sub-emitters on this backend. For bursts under 20 particles the CPU cost is negligible.
- `CPUParticles2D` works the same in headless tests, so the orphan-node test can run them. `GPUParticles2D` does not simulate headless.
- Single-threaded web: no benefit from GPU offload for small counts, and one fewer shader to compile on first use (shader compile stalls show on mobile).

Rules:

- One-shot, `emitting` set by `restart()`, `one_shot = true`, `explosiveness` 0.9.
- Pool 6 emitters, reuse them. Never `queue_free` per burst.
- `texture` set to a 128 px atlas-free PNG per effect. Use a `CanvasItemMaterial` with `blend_mode = BLEND_MODE_ADD` for sparks only. Use normal blend for smoke and dust.
- Colour comes from a gradient ramp that fades alpha to 0. Tint with team colour for hits so colour is repeated by shape and ring as the GDD rule says.
- Cap: 40 live particles in total. A new burst when over the cap skips its smoke layer first.

### Effects

| Event | Sprite (from `PNG (Transparent)/`) | Count | Lifetime | Notes |
|---|---|---|---|---|
| Sandal hit on character | `spark_05.png` plus `star_04.png` | 8 + 3 | 0.25 s | Radial burst, speed 140-220 px/s, team colour tint. |
| Pass kill | `star_01.png` plus `circle_05.png` ring (scale grows, 1 particle) | 10 + 1 | 0.4 s | Bigger burst than a plain hit. |
| Stack topple dust | `smoke_05.png` plus `dirt_02.png` | 8 + 6 | 0.6 s | Neutral sand colour. Spawn at stack position. |
| Dash trail | `trace_01.png` | 1 per 40 ms, 5 live max | 0.2 s | Emitter child of the character, `local_coords = false`, only while dashing (about 0.2 s). |
| Pickup | `star_04.png` | 4 | 0.3 s | Small, neutral. |
| Place on stack | `dirt_01.png` | 4 | 0.3 s | Small. |
| Death | `smoke_01.png` plus `dirt_03.png` | 6 + 4 | 0.7 s | Grey. Ends as the tombstone appears. |
| Stack rebuilt | `light_01.png` | 1 | 0.5 s | Soft flash, additive. |

Not used: fire, flame, muzzle, scorch, window, magic, twirl, slash. They do not fit a sandal game.

### Mapping into the 3D view

- Gameplay stays 2D. Particles live in one `CanvasLayer` named `FxLayer` above the `SubViewport` texture and under the HUD. This layer holds the pooled emitters.
- The 3D view shows the world through an orthographic top-down camera. Convert a 2D logic position to screen with the same transform the `World3DView` uses for its camera (same function as the aim preview, if one exists). Spawn the burst at that screen point. Do not parent particles to `Node3D` visuals.
- With the 2D view (default skin), the same layer works if it has `follow_viewport_enabled = true` so shake and the last-throw camera zoom move particles with the world. With the 3D view, no follow: use screen coordinates and apply the camera zoom factor to the particle scale.
- `FxLayer` goes through one API: `FxRef.burst(kind: StringName, world_position: Vector2, tint: Color)`. The `hit_effect` and `topple_effect` slots in `VisualSet` can point to a small scene that calls `FxRef.burst`, so skins stay swappable. This reuses `_on_pass_hit` and `Stack._topple`, which already call `skin.make(...)`.

## 5. Wiring order

1. Copy files and import. Create `assets/audio/` and `assets/particles/`. Add rows to `ASSETS.md` and `CREDITS.md`.
2. Add `default_bus_layout.tres`.
3. `Settings`: add `sound_enabled`, `set_sound`, `sound_changed`, persist. Add the unit test for persistence first.
4. `Audio` autoload, `AudioSet`, `AudioRef`. Wire the UI taps and toggles first (no gameplay dependency).
5. Wire gameplay events: round, stack, character signals. Add `Stack.placed` and `Sandal.sandal_hit` signals.
6. Add the sound tile and icons to `SettingsLayer`.
7. Add `FxLayer` and `FxRef.burst`. Wire the same signals.
8. Run all headless tests, then the browser e2e on a web export.

### Files to add

| Path | Purpose |
|---|---|
| `game/autoload/audio.gd` | Pools, mute, signal binding. |
| `game/scripts/core/audio_ref.gd` | Static wrapper for tests. |
| `game/scripts/core/audio_set.gd` | Resource: slot to streams and levels. |
| `game/assets/audio/audio_set.tres` | The one active set. |
| `game/assets/audio/*.ogg` | The 30 files in section 1. |
| `game/default_bus_layout.tres` | Master, Sfx, Ui, Voice. |
| `game/scripts/fx/fx_layer.gd` and `game/scenes/fx_layer.tscn` | Pooled `CPUParticles2D`. |
| `game/scripts/fx/fx_ref.gd` | Static wrapper. |
| `game/assets/particles/*.png` | 8 sprites at 128 px. |
| `game/assets/icons/sound_on.svg`, `sound_off.svg` | Toggle icons, CC BY 3.0. |
| `game/tests/audio_test.gd`, `game/tests/run_audio_test.sh` | Headless checks. |

Files to modify: `project.godot` (autoload, bus layout), `autoload/settings.gd`, `ui/settings/settings_layer.gd`, `scripts/world/stack.gd`, `scripts/world/sandal.gd`, `scripts/round/round_manager.gd` (bind only), `assets/ASSETS.md`, `CREDITS.md`. Another agent is editing `ASSETS.md`, `CREDITS.md` and the 3D view now, so do this after that agent finishes.

### Tests

| Test | Check |
|---|---|
| Resource load | Every path in `audio_set.tres` and the particle table loads with `load()` and is not null. Walk `res://assets/audio/` and `res://assets/particles/` and fail on any file that the set does not reference (orphan asset). |
| Slot coverage | Every slot name used in code exists in the `AudioSet`. Grep `Audio.play(&"...")` in the test. |
| Mute persists | Point `Settings.path` to a scratch file. Call `set_sound(false)`. Create a new `Settings` instance, call `load_settings()`. Expect `sound_enabled == false`. Expect `AudioServer.is_bus_muted(0)` after `Audio` reads it. |
| Default | A missing config file gives `sound_enabled == true`. |
| Pool cap | Call `Audio.play` 10 times in one frame on a cap-2 slot. Expect at most 2 players with `playing == true`. |
| No orphans | Run a round with `FxLayer`. Call `FxRef.burst` 50 times. After 1 s of simulated time, `Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)` equals the count before. Live emitter count stays at or below the pool size. |
| Headless audio | Godot headless uses the dummy audio driver. Tests check state (`playing`, bus mute), never sound output. |
| Event hooks | Fake round: emit `Stack.toppled` and expect `Audio` to have started the topple slot. Use a fake `Audio` recorder in `tests/fakes/`. |
| Browser e2e | In `tests/e2e/e2e.mjs`: after TAP TO PLAY, expect an `AudioContext` with state `running` (inject a spy on `AudioContext` before load). Toggle mute, reload, and expect the saved state. |
| Bundle size | Script fails if `assets/audio/` exceeds 1 MB. |

### Licence rows

Add to `game/assets/ASSETS.md`. Date is the day of the copy. The date below is a placeholder.

| File | Source | Author | License | Date |
|---|---|---|---|---|
| assets/audio/impact*.ogg, assets/audio/footstep_grass_*.ogg | https://kenney.nl/assets/impact-sounds (kenney_impact-sounds.zip) | Kenney | CC0 | YYYY-MM-DD |
| assets/audio/click*.ogg, assets/audio/switch*.ogg, assets/audio/rollover1.ogg, assets/audio/mouse*.ogg | https://kenney.nl/assets/ui-audio (kenney_ui-audio.zip) | Kenney | CC0 | YYYY-MM-DD |
| assets/particles/*.png (resized to 128 px) | https://kenney.nl/assets/particle-pack (kenney_particle-pack.zip) | Kenney | CC0 | YYYY-MM-DD |
| Voice pack (not shipped) | https://kenney.nl/assets/voiceover-pack | Kenney | CC0 | not used |

Add to `game/CREDITS.md` as a thanks line, with no obligation:

- Sound effects and particle sprites by Kenney (https://kenney.nl), CC0. Credit is not required. Listing it is a courtesy.
- New icons `sound_on.svg` and `sound_off.svg`: author and slug from game-icons.net, CC BY 3.0. This credit is required.

## Risks

| Risk | Mitigation |
|---|---|
| Sandal-on-sandal sound floods during a pile-up | Speed gate, cap 3, minimum 60 ms between plays per slot. |
| Sample playback pitch change on web | Pitch is set per play call and works. Test on a real Android Chrome device (unconfirmed). |
| First sound delayed on web | The start tap already unlocks audio. The first play may still compile a sample. Play a silent preload on `Audio._ready` (unconfirmed need). |
| Hit stop freezes `time_scale` to 0 | Players use `ALWAYS`. Sound does not depend on `time_scale`. |
| Slow-mo | Sample playback is not pitched by `time_scale` (unconfirmed). Accept either result. |
| Particle count on low-end phones | 40 live cap, 128 px sprites, one pool, no GPU path. |
| Merge conflict with the 3D view agent | Do wiring after that agent lands. Steps 1 to 4 do not touch its files. |
| Mono vs stereo memory | Optional mono downmix. Whole set is under 1 MB decoded at 44.1 kHz either way. |
| Voice pack misread as free to ship in a no-words game | Not shipped. |

## 6. Open questions

- Ship voice-over (numbers and "go", "you win") despite the no-words rule? Default in this plan: no.
- Add footsteps while running? Default: no, only the dash uses a footstep sample. Footsteps from 6 characters add noise and cost.
- Sound tile icon pair: `speaker` and `speaker-off` from game-icons.net, or two other icons you prefer?
- Music: no music pack was supplied. Confirm there is no music in scope.
