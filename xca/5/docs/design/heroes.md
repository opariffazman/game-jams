# Heroes and character select

Status: design only. Nothing here is built. The user replaced superpowers with heroes.

## Goal

- Each team has one hero. The human controls the hero of their team.
- The two other players on each team stay regular teammates.
- A hero has a different Kenney model and one power.
- The human picks a hero on a select screen after the start tap and before the coin flip.
- UI has no words. Icons only, from game-icons.net.

## Models

Source: `kenney_mini-characters.zip`, CC0. Extracted to a scratch directory, not into the repo.

All 29 character files share one rig and one 32-clip animation set. Clips used today: `idle`, `sprint`, `holding-both`, `attack-melee-right`. Clips free for heroes: `walk`, `crouch`, `emote-yes`, `emote-no`, `pick-up`, `interact-right`, `attack-kick-right`, `die`. No retargeting is needed between models.

| In the zip | Used in game now |
|---|---|
| `character-raider.glb` | Regular attacker |
| `character-knight.glb` | Regular defender |
| `character-alien`, `character-robot`, `character-soldier`, `character-worker`, `character-zombie` | Unused |
| `character-male-a` to `g`, `character-female-a` to `f` | Unused |

Hero models, picked for silhouette at small size. Each has a distinct head or hat shape.

| Hero model | Silhouette cue |
|---|---|
| `character-worker.glb` | Hard hat |
| `character-soldier.glb` | Peaked cap |
| `character-alien.glb` | Antennae |
| `character-robot.glb` | Boxy body, one antenna |
| `character-zombie.glb` | Hunched, hair tuft |

Limit: no Kenney model has kampong clothing. Kampong flavour comes from names, icons, sound and the scenery. The user can swap any hero to a `character-male-*` or `character-female-*` file without code changes, because the model path lives in `HeroDef`.

Readability rule: team colour must still read. Do not tint the body. Draw a team-coloured outline (blue friendly, red enemy) around the model with `scripts/view3d/outline.gdshader`. Add a team-coloured base disc under the hero, one size larger than a regular player, so a hero is findable by size. The human marker stays as it is.

## Roster

One power per hero. The power has an attack effect and a defence effect that share one icon, because roles swap every round. The button shows the same icon in both roles.

| Hero | Role in one line | Attack power | Defence power | Cooldown |
|---|---|---|---|---|
| Kilat | Sprinter | Lintas: two dashes in a row, both invulnerable | Sergah: speed x1.5 for 2 s | 8 s |
| Tukang | Builder | Cekap: build steps take half the time for 5 s | Sapu: kick radius x2 for 4 s, clears the build zone | 18 s |
| Perisai | Guard | Benteng: guard ring radius x1.6 for 4 s, block cooldown resets | Tapak Besi: absorbs one hit, 3 s | 16 s |
| Lontar | Thrower | Kembar: the next throw splits into a fan of three, 12 degrees apart | Angin: the next pass curves 25 degrees around a body | 12 s |
| Tangkap | Collector | Pulang: loose sandals within 140 px drift toward the build zone for 1.5 s | Jaring: pickup radius x2 for 4 s | 20 s |

Counters:

- Kilat: a defender who holds position inside the ring. A dash has a fixed length and stops at a body.
- Tukang: a defender hit on the builder still kills and cancels. Cekap only shortens the window.
- Perisai: the shield absorbs one hit, then the stun and the block cooldown apply. A second hit kills.
- Lontar: the fan has the same total momentum split three ways. A resting sandal still only nudges.
- Tangkap: Pulang moves loose sandals only. It never moves a placed sandal and never fills the zone by itself.

Rules every power must keep:

- Gather-all-three stays. No power builds without all three sandals in the zone and nobody carrying one.
- No power adds a sandal or removes one. The count stays three.
- Build time never drops under `build_step_seconds` times 0.5.
- No power makes the builder invulnerable.
- A power never blocks the round timeout.

Balance gate: the sim runs every hero pair on both sides. Each hero must keep the attacker win rate between 35 and 65 percent over 30 seeds, and no hero wins above 60 percent across all pairings. Out-of-band values go to `Tuning`, not into code.

## Data model

All numbers live in `Tuning` or in the hero resource, so the user changes them without editing code.

`HeroDef` (a `Resource`, `scripts/heroes/hero_def.gd`, instances in `game/data/heroes/*.tres`):

| Field | Type | Meaning |
|---|---|---|
| `id` | `StringName` | `&"kilat"` and so on |
| `icon` | `Texture2D` | Portrait icon for the card |
| `power_icon` | `Texture2D` | Icon on the power button |
| `model_path` | `String` | `res://assets/kenney/characters/...glb` |
| `model_scale` | `float` | Scale against a regular player, default 1.15 |
| `power_id` | `StringName` | Key into the power registry |
| `cooldown_seconds` | `float` | Per hero |
| `stat_speed`, `stat_build`, `stat_guard`, `stat_throw` | `int` 1 to 5 | Pips on the card, also scale the matching `Tuning` value by a fixed table |
| `attack_params`, `defence_params` | `Dictionary` | Duration, radius, angle for the power |

`HeroPower` (base `RefCounted`, `scripts/heroes/hero_power.gd`, one subclass per hero):

- `can_activate(character: Character) -> bool`: the character is alive, not frozen, the cooldown is done, and the power has a valid use in the current role and phase.
- `activate(character: Character) -> void`: starts the effect. Effects use timers on the character, never physics hacks.
- `tick(character: Character, delta: float) -> void`: runs a timed effect.
- `bot_wants_to_activate(character: Character, world: Node) -> bool`: the bot hook. Each subclass states its own trigger, for example Lintas when an attacker carries a sandal with a defender within 120 px.
- `end(character: Character) -> void`: clears the effect on death, round end and role swap.

Plug-in points:

- `Character` gets `var hero: HeroDef`, `var power: HeroPower`, `var power_cooldown_left: float`, signal `power_used(character)` and `try_power() -> bool`. A character without a hero behaves as today.
- `BotController` calls `power.bot_wants_to_activate` once per decision tick and `try_power()` when it returns true. Bots on a hero team use the hero model and power. Regular bots have no hero.
- `RoundManager` assigns heroes at match start and keeps them across rounds. The hero stays on its team. The role (attack or defence) swaps as today. At round start it resets cooldowns.
- Both teams: the human picks the hero for their team. The enemy hero comes from a seeded `RandomNumberGenerator`, excluding nothing, so mirror matches can occur. The seed is printed at match start with the sim seed.
- The human controls the hero. If the human is not the hero seat today, the select screen decides the seat: the human's character becomes the hero.

Input: one power button, icon only, with a cooldown ring that fills and a pulse when ready.

- Place it above the dash button on the right thumb cluster. Do not move the existing tiles that e2e taps (`TILE_LOCK`, `TILE_AIM`, the cube tile, the gear). Check the new button against the build button and the QTE overlay at 844x390.
- Touch target at least 44 CSS px. Keyboard: `E`. The button shows the state by ring fill, not by colour alone.
- During the build QTE the power button hides.

## Select screen

Position in the boot sequence: start tap, then `HeroSelect`, then the coin flip, then the countdown. `HeroSelect` is a new scene owned by `ui/hero_select/`. The match does not exist until the player confirms.

Layout, landscape:

- 844x390: five portrait cards in one row along the bottom, each 64 px wide and 72 px tall. The preview fills the upper two thirds. The confirm icon sits at the lower right.
- 1160x640: the same arrangement with 96 px cards.
- Safe area: honour `ui_scale.gd` insets.

Selection display:

- A turntable of the 3D model turns 20 degrees per second, with the `idle` clip. In the 2D view the preview shows the 2D body shape and the portrait icon.
- Beside the preview: the power icon, then the cooldown as a ring with a number-free fill, then four stat pips.
- A card is selected when it has a thick outline and sits 6 px higher. Outline contrast against the background is at least 3:1.
- The enemy hero shows as a small card top right with a dice icon until the match starts.

Confirm gesture:

- One tap on a card selects it. A second tap on the same card, or a tap on the confirm icon, confirms.
- Keyboard: arrows move, `Enter` or `Space` confirms. A single-pointer path exists for every action, so no drag is needed.
- No timer in the first version. If the user wants a timer, set `hero_select_seconds` in `Tuning` (default 0 means none).

Audio:

- On enter: voice `choose_your_character` from the Fighter pack. Add the slot `voice_choose` to `AudioSet`.
- Selection change: `ui_tap` sfx. Confirm: `ui_confirm` sfx. There is no voice line for each hero name, so heroes get no spoken name.

Persistence: store `hero_id` in `settings.cfg` through `SettingsRef`. The screen opens on the last pick.

Test hook:

- Query string `?hero=kilat` skips the screen and starts with that hero. Set `SettingsRef` hero from it.
- Query string `?enemy_hero=tukang` fixes the enemy hero.
- Without a hook, e2e taps the same two card coordinates as a user.
- `HeroSelect.confirm(hero_id)` is a public function for headless tests.

Fallback: if the hero resources fail to load, skip the screen and play with no heroes. This keeps the start path alive.

## Work packages

Each package owns its files. No two packages edit the same file.

| Package | Owns | Depends on |
|---|---|---|
| A. Data and powers | `scripts/heroes/*`, `data/heroes/*.tres`, `Tuning` hero keys | Rules agent done (stack, tuning, round code) |
| B. Character and round plug-in | `character.gd` hero fields, `round_manager.gd` hero assignment | A |
| C. Bot support | `scripts/ai/*` trigger calls, per-hero bot hooks | A, B |
| D. Select screen UI | `ui/hero_select/*`, `hero_icons`, the boot flow in the main scene | A. Visuals agent done (ui, settings) |
| E. 3D models | hero visuals in `depth_visual.gd`, base disc, scale, 2D body variants in `primitive_visual.gd` | A. Visuals agent done (view3d) |
| F. Power button | `ui/touch/*` power button and cooldown ring | B. Visuals agent done (touch layout) |
| G. Tests | `tests/hero_test.gd`, `tests/sim/hero_pairings.gd`, e2e spec `tests/e2e/heroes.mjs` | A to F |

Order: A, then B, then C, D, E and F in parallel, then G. A can start with data only, before the rules agent finishes, if it touches no shared file.

What must wait:

- Rules agent (stack, bots, tuning, round code): A, B and C wait. They edit the same files.
- Visuals agent (view3d, ui, settings): D, E and F wait. The settings panel and touch layout are still moving.

Tests:

- `hero_test`: each power activates, ends, respects its cooldown, resets on role swap and death, and never breaks the three-sandal rule or the minimum build time.
- Sim: every hero pair on both sides, 30 seeds, checks the balance gate and the existing invariants. Add a metric per hero for how often the bot uses its power.
- e2e: select a hero, confirm, reach the match, fire the power button once, check it enters cooldown.
- Accessibility check: card and button contrast at least 3:1, targets at least 44 CSS px at 844x390.

Assets: add a row per new hero model to `ASSETS.md`. Add a credit to `CREDITS.md` for every new game-icons.net icon (CC BY 3.0). The Fighter voice is already credited.

## Open questions for the user

1. Does the hero seat replace your current character, or is the hero a fourth player on a team of three? This design replaces one regular player.
2. Do you want a timer on the select screen, or does it wait until you confirm?
3. Is the enemy hero hidden until the match starts, or shown on the select screen?
4. Are Kenney models without kampong clothing acceptable, or do you want a texture tint or accessory per hero?
5. Can both teams field the same hero in a mirror match?

## Decisions (user, 2026-11-08)

- The hero replaces the human's regular player. A team still has three bodies.
- The select screen has no timer.
- The enemy hero is shown before the match.
- Kenney models without kampong clothing are accepted. Team colour shows as an outline, never a tint.
- Both teams can pick the same hero.
