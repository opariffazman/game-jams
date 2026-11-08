# Baling Selipar - game design spec

Source of truth for every agent. A rule here overrides any other doc. Decided by the user on the Lavish board and in chat.

## Platform

- Godot 4.6.3, GDScript, `gl_compatibility`, single-threaded web export.
- Web game for GamePix. Desktop and mobile. Landscape only. Mobile touch is the priority.
- Style rules: `/home/ariff/repo/skills/godot-gdscript-style/SKILL.md`. Practices: `docs/godot/cheatsheet.md`.
- Graphics: flat primitives only. Role sets the shape: attackers are circles, defenders are squares. Sandals use the game-icons sandal icon.
- Team colour is relative to the human and never changes between rounds. The human's team (friendly) is always blue. The other team (enemy) is always red. This applies to characters, thrown sandals, the pass sandal, HUD pips and role markers. Colour is never the only cue: shape, ring and icon repeat it. Both colours need at least 4.5:1 contrast on the arena floor, and must stay distinct under red-green colour blindness.
- The stack sandals stay neutral sand. They are the shared target.
- Friendly colour, enemy colour and neutral sand are tuning values: `friendly_color`, `enemy_color`, `neutral_sandal_color`.
- UI has no words. Use icons from game-icons.net only. Copy each used SVG into `game/assets/icons/` and list authors in `game/CREDITS.md` (CC BY 3.0).

## Teams and round

- 3 characters per team. Team size is one constant.
- One team defends, one attacks. Roles swap after every round.
- The human controls one character. The coin flip before round 1 sets the human's team role. Bots control every other character.
- One pyramid of 3 sandals sits at the arena centre spot: a teepee, standing on edge on a ring, tips leaning to one apex. The defenders own it.

## Topple phase

- Attackers throw one at a time, in a fixed queue order. Each attacker has exactly one throw. Each throw is one sandal.
- Attackers throw from a fixed distance. A throw ring of radius `throw_radius` surrounds the stack. An attacker in the throw queue stands on that ring, never closer or farther. The ring is drawn as a faint arc.
- The throw has a fixed range. The sandal travels `throw_radius` toward the aim direction. The drag sets direction only, and drag length does not set power.
- All 3 defenders circle the stack on an orbit ring of radius `orbit_radius`, which is smaller than `throw_radius`. No defender stands in the centre or holds a fixed block position.
- Orbiting defenders move at a steady `orbit_speed` and are moving obstacles. A sandal collides with them. Defenders do not throw in this phase.
- The human defender steers along the ring only: joystick left or right picks clockwise or counter-clockwise. Bots orbit automatically. All defenders circle, so the human has no advantage position.
- Sandals are physics bodies. A hit pushes them.
- The stack is down when any one stack sandal leaves its spot (moved more than a set distance).
- A missed throw stays on the field as a loose sandal. A later throw can hit it.
- The phase ends when the stack is down or when every attacker has thrown.
- Stack still up after the last throw: every attacker is mati. Defenders win the round. Roles swap.
- Slow-mo and a close camera play on the last throw of the round only.

## Scatter phase

- Starts when the stack is down. Loose attacker sandals are removed.
- One extra sandal appears in a defender's hand. It is the pass sandal. It has a distinct tint.
- Attackers run, dodge, collect the 3 sandals at the centre, and build the pyramid. See "Pyramid rebuild".
- Defenders pass the pass sandal. A defender who holds it stands still and can only pass or throw.
- A pass sandal in flight that touches an attacker makes that attacker mati. The pass sandal stops at the first kill. A rolling sandal on the ground does not.
- Mati has no respawn. A mati attacker stays out until the round ends and shows a tombstone.
- Attackers built the pyramid: attackers win the round. Roles swap.
- Every attacker mati: defenders win the round. Roles swap.
- The scatter phase has a time limit, `scatter_time_limit` (60 s). When it runs out the defenders win the round. Every round therefore ends.
- Match: the round winner scores 1. First team to 3 wins the match.

## Pyramid rebuild (user decision)

The pyramid is the main way attackers win. It cannot be built with fewer than 3 sandals, and building takes time.

- Layout: a teepee. Three equal sandals stand on edge on a ring of radius `pyramid_base_radius`, 120 degrees apart. Slot 0 points up the screen and the others follow clockwise. Each sandal leans toward the centre by `pyramid_lean_degrees` (25), so the tips meet at one apex. There is no top sandal. `Stack.slot_positions` holds the feet (local), `Stack.slot_lean_directions` the unit vector toward the centre and `Stack.slot_lean_angle` the angle from vertical in radians. A placed `Sandal` has `stack_slot`, `lean_direction` (world) and `lean_angle`. All three keep their collision, so a throw can hit any of them. The topple rule is unchanged: any stack sandal moved more than `topple_distance` from its spot.
- No kick: character bodies never move a sandal. Only a thrown sandal moves sandals in the zone or the teepee. Characters still collide with each other and walls. Sandals still collide with each other.
- Build zone: a circle of radius `build_zone_radius` around the centre spot. A loose sandal inside it counts as delivered. A sandal sits loose until a build places it.
- Collect: an attacker carries one sandal at a time. A carrier that comes within `place_radius` of the centre spot drops the sandal there at once. No hold or tap is needed. Attackers never pick up a sandal that lies inside the build zone.
- Gate: building can start only when all 3 sandals are in the build zone or already placed, and nobody carries one. `Stack.can_build()` reports it.
- Build: an alive attacker inside the zone starts a build. Only one builder at a time. A build places 3 sandals in order: slot 0, slot 1, slot 2 around the ring. The third sandal locks the apex. Each step takes about `build_step_seconds` (1.2 s).
- The builder is not frozen and not invulnerable. A builder who leaves the zone, dies, or sees a sandal leave the zone ends the build. Sandals already placed stay placed, and the next builder continues from there.
- A defender sandal in flight that kills the builder ends the build. A defender sandal in flight at `knock_min_speed` (450 px/s) or more that touches a placed sandal knocks every placed sandal loose with `knock_impulse` (144). A slower touch does nothing. The count of placed sandals goes back to 0.
- Softer impacts: a resting sandal hit by a flying sandal keeps at most `rest_hit_speed_cap` (200 px/s), so it nudges and does not fly off.
- Win: all 3 placed and left alone for `build_stable_time` (0.5 s) is a built pyramid. The attackers win the round.
- Human build: the human attacker taps the build icon (or presses Enter or E) when inside the zone and all 3 sandals are there. Each step is a balance game: a sandal on its edge wobbles, the thumb (stick, right-half drag, arrows or taps) keeps the lean in the green band for `balance_hold_seconds`. A fall costs only `miss_penalty_seconds`. The build also starts alone after `balance_auto_start_seconds` of standing still in the zone. `build_balance_enabled` false brings back the tap and swipe prompts.
  - Tap prompt: a ring shrinks onto a target ring. A tap within `qte_window_seconds` (0.3 s) of the meeting time places the sandal.
  - Swipe prompt: an arrow shows a direction. A swipe of at least `qte_swipe_min_css_px` in that direction places the sandal. A single tap on the arrow does the same, so no prompt needs a gesture.
  - Keyboard: Space is a tap. An arrow key is a swipe in that direction. Space also answers a swipe prompt.
  - A miss, a wrong direction or a timeout costs `miss_penalty_seconds` (0.8 s) and then the same step prompts again. Placed sandals never come off for a miss.
  - Prompt directions come from a seeded random generator.
  - While the human builds, the camera zooms on the pyramid (`build_zoom`). The 3D view listens to `RoundManager.build_view_changed(active, focus_world_position)`.
  - The overlay shows 3 sandal icons, filled for sandals in the zone or placed. Touch targets are at least 44 CSS px. Prompts have no words and use light shapes on a dark disc for 4.5:1.
- Bot build: a bot attacker collects, drops, then builds. It has no prompt. Each step takes `build_step_seconds` times a skill factor from 1.25 (difficulty 0) to 1.0 (difficulty 1).
- Idle human: a human thrower who holds a sandal for `topple_throw_seconds` (6 s) gets an automatic throw at the stack. In scatter, an idle human attacker who holds a stack sandal for the same time drops it inside the build zone, so bots can build.
- Defender counterplay: throw at the builder (priority), then a half-built teepee, then open attackers and gathered sandals. No body kick exists. Defender bots keep `orbit_radius` spacing and never idle beside zone sandals.
- Guard block: an attacker who is not the builder and not carrying, standing in the guard ring (`guard_ring_width` 70 px beyond `build_zone_radius`), auto-blocks one defender sandal hit. The sandal ricochets with `block_bounce` (0.6) of its speed, the guard is stunned `guard_stun_seconds` (1.0) and cannot block again for `guard_block_cooldown` (4.0). A hit in the cooldown kills. The builder is never covered. Feedback is the `block` burst in `FxRef` (no icon). Attacker bots take guard ring slots on the pass holder side.

## Human control

- The human controls one fixed character per round.
- When the human is a defender, control follows the pass sandal. A pass switches the human to the receiver. The ring on the board marks the controlled character.
- Bots fill every other seat. Bot difficulty is medium. Make it one tuning value.

## Input

- Mobile: left virtual joystick moves. Right thumb drag-back-and-release throws (slingshot). The throw direction is opposite to the drag. Attacker throws have fixed range, so drag length shows an aim line only. Defender passes and hits keep drag length as power.
- The same gesture does an attacker throw, a defender pass, and a defender hit.
- Defender pass: aim assist snaps to the nearest teammate inside a cone, and the pass curves over an attacker.
- Defender hit: the throw leads a moving attacker toward the point where they will be.
- Each finger controls one thing. Track touch by finger index.
- Desktop: WASD or arrows move. Mouse drag-back-and-release throws.
- Portrait shows a rotate overlay. Keep the existing overlay.

## Throw control schemes (user decision)

The game ships two throw schemes, and a settings screen switches between them. Full spec for both is in `docs/research/throw-controls.md` (scheme A and scheme D, with their tables). Scheme D is the default.

- Scheme D, Lock and fire: one fixed fire button on the right. A tap fires at the visible lock. A drag moves the lock to the character nearest the drag bearing inside a 40 degree cone, with an 8 degree hysteresis. Dragging back inside the slop circle and releasing cancels. Attackers always lock the stack. Defenders default-lock the best foe or teammate. Throws use fixed power: `pass_power` and `hit_power`.
- Scheme A, Aim stick with preview arc: the right thumb drags to aim. The arc shows the fixed range and the thrower-to-target line. The drag direction is NOT reversed, so the aim points where the thumb points. Release fires. Dragging back to the stick centre and releasing cancels. The defender pass and hit use the same drag, picking the target nearest the aim bearing, and the arc shows which target is picked before release.
- Both schemes draw the same world preview (dashed line, target ring in friend blue, foe red or stack sand, lead-point marker for a hit, bent path for a pass, dotted blocked lane with a cross icon).
- Scheme D keeps fixed throw range for attackers and fixed power for passes and hits. Scheme A no longer follows this line: see "Manual throw" below.
- Settings: a gear icon opens an icon-only panel. The first setting is the throw scheme, two large icon tiles (lock icon for D, aim-arrow icon for A) with the active one ringed. The choice is saved to `user://settings.cfg` (the web build keeps this in the browser's IndexedDB) and applies at once, with no restart. Desktop: Esc opens settings.
- Other settings that ship with the panel: a haptics on or off toggle (Android Chrome only), and a master sound on or off toggle if sound exists. Nothing else.

## Manual throw (scheme A, FIFA style) - user decision, replaces the snap in scheme A

Playtest feedback: scheme A had no strength control, the defender aim snapped to foes and teammates, and the human attacker could not topple the stack. The user wants full manual control, with one assisted shortcut, like FIFA: tap passes to the nearest player, and a manual shot has its own direction and power. Scheme D stays the assisted scheme.

- Tap on the aim stick (touch that never leaves the slop radius) is the quick action:
  - Defender: pass to the nearest living teammate. This is the existing assisted bent pass with homing.
  - Attacker: throw at the stack at full power along the clear line.
- Drag is the manual throw. The direction is where the thumb points. The power is the drag length: 0 at the slop radius and 1 at the stick edge, clamped. There is no lock, no cone and no snap to any target.
- Release fires. Dragging back inside the slop radius and releasing cancels.
- Power sets the range and the speed. Range is power times `max_throw_range` (340 px, longer than the 260 px throw ring, so a full-power throw at the stack passes through it). Speed is the larger of power and `min_throw_power` (0.2) times `throw_speed_max`. The sandal flies at constant speed and stops at the exact range, as `launch_ranged` does.
- A manual throw has no homing. A sandal in flight kills any foe it touches and stops at the first kill. A manual defender throw is a normal throw, so a teammate it touches does not catch it. Only a tap pass is caught.
- Preview, drawn in the world while the thumb is down: a line from the thrower of exactly the throw length, a landing ring at its end, and for attackers a tick on the line where the stack stands. The line stops at the first character it would touch, and a ring marks that character in its team colour. This is a precision aid and never moves the aim. A power fill on the stick shows the drag length. Icons only, no words.
- Both bots and scheme D keep calling `throw_sandal`, `pass_to` and `hit` as today. Bots throw at full power.

## Restart

- A restart icon button sits at the top right, away from the dash button and throw pad. It needs a hold-to-confirm (a ring fills while held), so a stray tap cannot reset the match.
- Restart resets the whole match: scores, roles, coin flip, loose sandals, stack. It does not reload the web page, so the fullscreen state and the loaded engine stay.
- At match end an icon-only overlay shows the result (trophy for a human win, tombstone for a loss) and one large restart button. No text.
- Desktop: hold R to restart.

## Phase 1 scope (build now)

1. Arena, stack, sandal physics, topple detection.
2. Round state machine, roles swap, score to 3, coin flip.
3. Joystick, drag-to-throw, desktop input.
4. Attacker: flat throw, carry and stack, dash with a short invulnerable window and a cooldown.
5. Defender: orbit the stack in the topple phase (no body-block position), pass with aim assist, hit with lead aim, control follows the sandal, pick up loose sandals (no kick).
6. Bots for both roles at medium difficulty.
7. Icon-only HUD: score, round role, throws left, stack progress ring, mati markers.
8. Hit stop, screen shake on topple, slow-mo on the last throw.

## Phase 2 scope (later)

- Lob and curve throws, near-miss meter, superpowers (attacker: dash boost, decoy, shield, magnet. Defender: mud, net), pass chain speed-up up to three passes.

## Cut line

- Wall bounce, pressure ramp, warp pass, boomerang, pass-lane steal.

## Code contract

Every agent writes against these names. Do not rename them. The owner of a file is the only writer.

| Class (path) | Owner | Public API |
|---|---|---|
| `Tuning` (`scripts/core/tuning.gd`, Resource) | world | Every number the design names. `team_size`, `throws_per_attacker`, `topple_distance`, `mati_respawn` is absent. |
| `Sandal` (`scripts/world/sandal.gd`) | world | `RigidBody2D`. `launch(direction: Vector2, power: float)`. `var in_flight: bool`. `var is_pass_sandal: bool`. `var stack_slot: int` (-1 while loose), `var lean_direction: Vector2` (world, toward the centre), `var lean_angle: float` (radians from vertical). Signal `hit_character(character: Character)`. |
| `Stack` (`scripts/world/stack.gd`) | world | `var is_down: bool`. `var is_built: bool` (true while a complete pyramid stands, also at round start). `var placed_count: int` (sandals in the pyramid, 3 at round start, 0 after a topple). `var standing_sandals: Array[Sandal]` (the sandals in the pyramid). `var slot_positions: Array[Vector2]` (local feet, ring of `pyramid_base_radius`), `var slot_lean_directions: Array[Vector2]` and `var slot_lean_angle: float`. `var builder: Character`. `can_build()`, `begin_build(character)`, `end_build(character)`, `place_sandal()`, `zone_sandals()`, `is_in_zone(point)`, `cancel_build()`. Signals `toppled`, `rebuilt`, `placed_count_changed(count)`, `build_started(builder)`, `build_ended(builder, completed)`, `pyramid_knocked`. |
| `Arena` (`scripts/world/arena.gd`) | world | `centre_spot: Vector2`. `get_characters(team: int) -> Array`. `get_loose_sandals() -> Array`. |
| `RoundManager` (`scripts/round/round_manager.gd`) | world | States `COIN_FLIP, TOPPLE, SCATTER, ROUND_END, MATCH_END`. Signal `phase_changed(phase)`. Signal `round_ended(winner_team)`. Signal `build_view_changed(active: bool, focus_world_position: Vector2)`, emitted when the human starts or ends a build. `var attacking_team: int`. `var throws_left: int`. `var scatter_time_left: float`. |
| `Character` (`scripts/characters/character.gd`) | characters | `CharacterBody2D`. `var team: int`. `var role` (`ATTACKER` or `DEFENDER`). `var alive: bool`. `var carried: Sandal`. `var move_intent: Vector2`. `throw_sandal(direction: Vector2, power: float)`. `pass_to(target: Character)`. `dash()`. `die()`. `drop_carried(world_position: Vector2)`. `pick_up(sandal: Sandal)`. `start_building() -> bool`, `stop_building()`, `complete_build_step() -> bool`, `is_building() -> bool`. Signal `died`. |
| `BuildOverlay`, `BuildQte` (`ui/build/`) | world | `BuildOverlay` is the human's build button, sandal pips and prompt drawing. `BuildQte` is the prompt logic with no drawing, so tests run it alone. |
| `Controller` (`scripts/characters/controller.gd`) | characters | Base class. A controller sets `character.move_intent` and calls the throw, pass and dash methods. `HumanController` and `BotController` extend it. |
| `HumanController` (`scripts/input/human_controller.gd`) | characters | Reads `VirtualJoystick` and owns the active `ThrowScheme`. Swaps it live when `Settings.scheme_changed` fires. |
| `VirtualJoystick`, `FireButton`, `AimStick`, `DashButton` (`ui/touch/`) | characters | Control nodes. `VirtualJoystick` has signal `moved(vector)`. `FireButton` has `pressed`, `dragged(bearing)`, `released`, `cancelled`. `AimStick` has `pressed`, `aimed(bearing, length_ratio)`, `released(bearing)`, `cancelled`. |
| `ThrowScheme`, `LockFireScheme`, `AimStickScheme` (`scripts/input/`) | characters | `ThrowScheme` holds targets, the lock (`steer_lock`, `default_target`, `reset_lock`), the world preview and `fire()`. `LockFireScheme` is scheme D. `AimStickScheme` is scheme A. Bots never use a scheme. |
| `Settings` (`autoload/settings.gd`) | characters | Autoload. `scheme`, `haptics_enabled`, `set_scheme`, `set_haptics`, `vibrate`, signals `scheme_changed`, `haptics_changed`. Saves to `user://settings.cfg`. Scripts read it through `SettingsRef`, so they compile in a `--script` run. |
| `SettingsLayer` (`ui/settings/settings_layer.gd`) | characters | Gear button and the icon-only panel. Pauses the game tree while open. Esc toggles it. |
| `BotController` (`scripts/ai/bot_controller.gd`) | bots | Extends `Controller`. Uses `Arena` and `RoundManager` read-only. Attacker bots collect, drop and build through `Character.start_building` and `Character.complete_build_step`. |

Rule for bots: a bot only sets `move_intent` and calls `throw_sandal`, `pass_to`, `dash`, `pick_up`. A bot never writes another node's state.

## Visual contract (swappable 2D or 3D assets)

Gameplay is always 2D physics. Art is a separate layer that never affects gameplay.

- Logic nodes (`Character`, `Sandal`, `Stack`, `Arena`) contain no drawing code. Each one has a `Visual` child, created from a scene named in a `VisualSet`.
- `VisualSet` (`scripts/core/visual_set.gd`, Resource, owner world). One field per art slot: `attacker`, `defender`, `sandal`, `pass_sandal`, `stack_marker`, `arena`, `tombstone`, `hit_effect`, `topple_effect`. Each field is a `PackedScene`. It also holds `visual_scale` per slot, so art size never changes hitboxes.
- `EntityVisual` (`scripts/core/entity_visual.gd`, base class, owner world). Public API: `play(state: StringName)` with states `idle`, `run`, `carry`, `throw`, `dash`, `die`, `hit`. `set_facing(angle: float)`. `set_team_color(color: Color)`. A visual that lacks an animation ignores the state.
- The active set is one file: `res://assets/skins/active.tres`. The default set `res://assets/skins/primitives.tres` uses the flat shapes. A swap changes that one reference.
- Hitboxes, radii and speeds come from `Tuning`, never from the art.
- A 2D skin uses `Node2D` visuals (`Sprite2D`, `AnimatedSprite2D`).
- A 3D skin keeps the 2D logic. A `World3DView` node (later task) owns a `SubViewport` with an orthographic top-down `Camera3D`. Each 3D visual is a `Node3D` placed at (x, 0, y) of its logic node every frame. The viewport texture draws under the HUD.
- Audio uses the same pattern: an `AudioSet` resource names the streams. Code plays sounds by slot name.
- Every external asset gets one row in `game/assets/ASSETS.md`: file, source, author, license, date. CC0 needs no credit, but the row stays. game-icons.net icons are CC BY 3.0 and need credit in `game/CREDITS.md`.

## Open items

- Phase 2 powers are replaced by heroes and a select screen. See `docs/design/heroes.md`. Do not build them yet.
- Exact tuning numbers are unconfirmed. Put every number in `Tuning` so the user can change them without editing code.
