# Throw controls research

Question: which aim and throw scheme fits Baling Selipar on a phone?
Date: 2026-11-07. Review board: `docs/design/.lavish/throw-controls.html`.

## Answer

Use "Lock and fire". The right thumb holds one fixed fire button. A tap fires at a visible lock. A drag picks another target. Dragging back to the button cancels.

- A tap alone does every throw. Drag is optional. This meets WCAG 2.5.7 and the Game Accessibility Guidelines "simpler alternative" rule.
- The preview is drawn in the world, from the thrower to the target. The thumb never covers it.
- Attackers always lock the stack. Their skill is timing and ring position, not aim.

## What the current scheme does

All findings come from reading the code. No finding is confirmed with a second player.

| Finding | Evidence | Effect |
|---|---|---|
| The aim line starts at the thumb, not at the character | `game/ui/touch/throw_pad.gd:79` and `:88` | The line points across the screen and never touches the thrower. |
| The throw goes opposite to the drag | `throw_pad.gd:146` (`_start - _current`) | The player must reverse the drag in their head. |
| The drag can start anywhere in the right half | `zone_width_ratio` 0.5, `_in_zone` | No fixed anchor. The idle hint icon marks one spot, but any spot works. |
| The pad shows no target | `human_controller.gd` binds only `drag_released`. Nothing listens to `aiming`. | The player cannot see what the throw will hit. |
| A defender's pass or hit is chosen silently on release | `game/scripts/characters/character.gd:208-219`, cone 28 degrees (`tuning.gd:72`) | The same drag can pass, hit, or throw into empty space. The player learns the result after the sandal leaves. |
| Cancel exists but is invisible | `throw_pad.gd:128` emits `drag_cancelled` when the drag is under `dead_zone` (24 px) | Nothing on screen marks the cancel area. |

## Why free aim is hard in this game

Numbers use the Godot base size 1160x640 and `Tuning` defaults. The thumb jitter of 4 px is my assumption.

| Quantity | Value | Source |
|---|---|---|
| Stack hit window from the throw ring, end-on | about +-6 degrees | `throw_radius` 260, `sandal_radius` 14, thrown sandal radius 14 (collision shape sizes unconfirmed) |
| Stack hit window, side-on | about +-13 degrees | stack of 3 with `stack_gap` 2 is 88 px tall |
| Thumb error of 4 px at a 100 px drag | 2.3 degrees | arc tangent |
| Same error at a 60 px drag | 3.8 degrees | arc tangent |
| Character diameter on a phone | 22 to 29 px (scale 0.61 to 0.80) | stretch scale on 844x390 and 1026x514 |
| Defender speed on screen | 61 to 80 px/s | `orbit_radius` 100 at 1 rad/s |

Thumb error uses up a third to a half of the end-on window. Attackers have one target at one range. Aim is not the skill. Timing against the orbiting defenders is the skill.

## What shipped games do

| Game | Scheme | Lesson for this game | Source |
|---|---|---|---|
| Brawl Stars | Tap the attack button for an auto-aimed shot. Drag to aim and release to fire. Drag back to the centre to cancel. | Tap, drag and cancel in one control is a proven pattern. A tap that slides a few millimetres turns into a manual shot, so the slop radius matters. | [keymap.io](https://keymap.io/games/brawl-stars/), [Beginner's Guide](https://brawlstars.fandom.com/wiki/Beginner's_Guide), [noff.gg](https://www.noff.gg/brawl-stars/app/build/19201/brawl-stars-beginner%20%20%20s-guide). Community sources, not the developer. |
| Knockout City (console) | Winding up locks onto nearly anyone in view. Most balls curve toward the target. Passes charge automatically. | Lock-on makes throws and passes readable. It is a console game, so the input does not carry over. | [Apptrigger review](https://apptrigger.com/2021/06/26/knockout-city-review/), [Push Square guide](https://www.pushsquare.com/guides/knockout-city-tips-and-tricks-for-beginners) |
| Clash Royale (Merge Tactics mode) | A tap deploys at once. A drag places at an exact spot. | Offer the fast path and the exact path on one control. | [Supercell support](https://support.clashroyale.com/hc/en-us/articles/49484923863067-Merge-Tactics). The classic mode is described only in fan posts. |
| Angry Birds | Drag back to set angle and power. | Unconfirmed whether every version shows a dotted trajectory before launch. No usability study found. | Implementation notes only. |
| Golf Clash | Drag back and release to swing. | Unconfirmed. Sources are unofficial sites. The way the power meter stops is unknown. | None reliable. |
| Pocket Tanks | Angle, power, fire. | Unconfirmed touch mapping. The store listing names no gesture. | [App Store listing](https://apps.apple.com/us/app/pocket-tanks/id311544087) |
| Archero | Not researched. | No source found. | None. |

## Accessibility rules that apply

| Rule | Level | Requirement | Effect on this game | URL |
|---|---|---|---|---|
| WCAG 2.5.1 Pointer Gestures | A | Path-based and multipoint gestures need a single-pointer alternative without a path. | Does not apply. A drag in any direction is not path-based. | [W3C](https://www.w3.org/WAI/WCAG22/Understanding/pointer-gestures.html) |
| WCAG 2.5.7 Dragging Movements | AA | A function that uses dragging must work with a single pointer without dragging, unless dragging is required. | An aim stick with no tap path fails. A tap that fires at a lock passes. | [W3C](https://www.w3.org/WAI/WCAG22/Understanding/dragging-movements.html) |
| WCAG 2.5.8 Target Size (Minimum) | AA | Targets are at least 24 by 24 CSS px, or spaced so a 24 px circle on each does not touch another. | The fire and dash buttons must meet it. Characters are 22 to 29 px, so tapping them directly is a risk. | [W3C](https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum.html) |
| WCAG 2.5.5 Target Size (Enhanced) | AAA | 44 by 44 CSS px. | Cited by secondary sources. I did not fetch the W3C page. | unconfirmed |
| Game Accessibility Guidelines, Motor, Basic | Basic | Large, well spaced virtual controls. Adjustable sensitivity. Controls as simple as possible, or a simpler alternative. | The fire button is large. A tap is the simpler alternative. | [gameaccessibilityguidelines.com](https://gameaccessibilityguidelines.com/full-list/) |
| Game Accessibility Guidelines, Motor, Intermediate | Intermediate | Alternatives to holds. Gesture input only as a supplement. No required simultaneous actions. Interactive elements that need accuracy stay stationary. | The game never needs two fingers at once. Orbiting defenders are moving targets, which counts against tap-to-target. The guideline names menus, so applying it to game targets is my reading. | same |
| Game Accessibility Guidelines, General, Intermediate | Intermediate | Include assist modes such as auto-aim. | The default lock is an assist mode. | same |
| Xbox Accessibility Guideline 107 | n/a | Alternative inputs with the same function. No required multipoint or path gestures. Alternatives to long holds. | A tap and a drag reach the same result. | [Microsoft](https://learn.microsoft.com/en-us/xbox/accessibility/xbox-accessibility-guidelines/107) |
| Uncharted 4 example | n/a | Target lock plus camera assist let a player play with one stick. | Precedent for lock-on as an accessibility feature. | [GAG page](https://gameaccessibilityguidelines.com/uncharted-4-accessibility-settings/) |

## Candidates, ranked

Hours are my estimate and are unconfirmed. Access score is the rubric below, out of 5.

| Rank | Scheme | Attacker throw | Defender pass | Defender hit | GDD rules changed | Hours | Access | Top risk |
|---|---|---|---|---|---|---|---|---|
| 1 | D. Lock and fire | Tap fires at the stack lock. Drag does nothing in phase 1. | Drag toward a teammate moves the lock. Release fires. | Default lock on the best foe. Release fires at the lead point. | Input and Scatter phase: remove drag-length power, remove the silent cone, add a visible lock, add cancel. | 9 | 4.5 | Two roles in one control can confuse until the ghost hand teaches it. |
| 2 | C. Auto-aim with nudge | Always locks the stack. | Lock picks a teammate. A small nudge changes it. | Lock picks a foe. | Same as D, minus the explicit drag-to-pick rule. | 6 | 4.0 | Weak control over pass versus hit. |
| 3 | A. Aim stick with preview arc | Drag aims. The arc shows fixed range. | Drag toward a teammate. | Drag toward a foe. | Input: reverse the drag, add the arc and cancel. | 5 | 2.5 | Window is +-6 to +-13 degrees. No tap path, so it fails 2.5.7. |
| 4 | B. Tap to target | Tap the stack, hold briefly to confirm. | Tap a teammate. | Tap a foe. | Input and Scatter phase: tap replaces the drag. | 8 | 3.0 | Targets move and are 22 to 29 px wide. Stray taps fire. |

### Rubric

Each row scores 1 for pass, 0.5 for partial, 0 for fail.

| Criterion | A | B | C | D |
|---|---|---|---|---|
| Works with a single pointer and no drag (2.5.7) | 0 | 1 | 1 | 1 |
| Targets meet 24 px or spacing (2.5.8) | 1 | 0.5 | 1 | 1 |
| Simple, or a simpler alternative exists (GAG Basic) | 0.5 | 1 | 1 | 1 |
| No precision on moving or small targets (GAG Intermediate) | 0 | 0 | 0.5 | 0.5 |
| Cancel before commit | 1 | 0.5 | 0.5 | 1 |
| Total | 2.5 | 3.0 | 4.0 | 4.5 |

## Recommendation: Lock and fire

| Part | Specification |
|---|---|
| Control | One fixed fire button on the right, centred where the slingshot hint sits (0.78 by 0.66 of the screen). It replaces the whole right-half drag zone. |
| Size | At least 72 CSS px across. The dash button stays at least 56 CSS px. A gap of at least 24 CSS px separates them. The 72 px value is my choice and is unconfirmed on a device. |
| Tap | Touch down shows the lock. Release without moving fires at the lock. |
| Drag | Past a slop of 16 CSS px, the lock moves to the character nearest the drag bearing inside a cone of 40 degrees. The drag direction is not reversed. A new target needs to beat the old one by 8 degrees. If no character is inside the cone, the lock stays. |
| Attacker lock | Always the stack. Drag has no effect in phase 1. |
| Defender default lock | The foe carrying a sandal nearest to the stack spot. Then the nearest foe. If no foe lives, the button greys out and fires nothing. |
| Free throws | Removed for defenders. A defender always passes or hits. |
| Power | Fixed. A pass uses `pass_power`. A hit uses a new `hit_power`. |
| Cancel | Drag back inside the slop circle and release. The button then shows a cross icon and the lock fades. |
| Preview | A dashed line from the thrower to the lock, drawn in the world. A ring on the target. Friend ring is blue, foe ring is red, stack ring is sand. A hit shows a marker at the predicted lead point. A pass shows the bent path. A blocked attacker lane draws dotted with a cross icon, so colour is never the only cue. |
| Icons | Pass: throwing-ball. Hit: bullseye. Cancel: cross-mark. Stack: stack. All from game-icons.net. |
| Haptics | `Input.vibrate_handheld(10)` when the lock changes and `(25)` on fire. Supplement only. |
| First-time hint | A ghost hand icon taps the fire button, a ring appears on the target, and a sandal flies. For defenders a second pass drags to a teammate. It replays after 8 seconds of idle, up to 3 times, and stops after the first fired throw. |
| Desktop | Left click fires at the lock. Hold and move to pick a target. Right click or Escape cancels. Q and E cycle the lock and F fires, so the keyboard needs no pointer. Space stays dash. |
| Side colours | Friends are always blue and foes always red, as the user asked. Role shape stays: circle attacker, square defender. Red on the arena floor measures 5.77:1 for `#ff6b6b`. Blue measures 8.33:1. The two hues differ by only 1.44:1 in luminance, so shape must also carry the side. |

### Haptics facts

- Godot documents `Input.vibrate_handheld` as implemented on Web. Safari and Firefox for Android do not support it ([Godot docs](https://docs.godotengine.org/en/latest/classes/class_input.html)).
- Chrome for Android implements the Vibration API and needs a prior tap. WebKit does not implement it ([W3C report](https://w3c.github.io/vibration/reports/implementation.html)).
- The tap on TAP TO PLAY gives that activation. Whether the Godot web call works through the shell on a real phone is unconfirmed.

### GDD sections this changes

- Input: replace the slingshot paragraph with the fire button, lock, drag and cancel rules.
- Scatter phase: replace "aim assist snaps to the nearest teammate inside a cone" with the explicit lock rule.
- Topple phase: attackers fire at the stack lock. Drag does nothing.
- Tuning: add `lock_cone_degrees` 40, `lock_hysteresis_degrees` 8, `slop_px` 16, `hit_power`. Retire `pass_cone_degrees` and the drag-length power.

## Decisions for the user

1. Which scheme: D, C, A or B. The recommendation is D.
2. How much attacker aim skill: lock only, lock with a drag offset inside the stack width, or free aim. The recommendation is lock only. Timing against the orbit stays the skill.

## Unconfirmed

- Whether the 4 px thumb error and the +-6 to +-13 degree window match real play. Collision shape sizes were not read.
- The 72 px button size, the 16 px slop, and the 40 degree cone. Tune them on a phone.
- Build hours.
- Brawl Stars details come from community pages. The developer publishes no control spec that I found.
- Angry Birds preview, Golf Clash meter, Pocket Tanks gestures, and Archero.
- WCAG 2.5.5 wording.
- Haptics through the Godot web shell on Chrome Android.
- Whether the player's confusion comes from the causes listed above. Only one playtest note exists: "a bit unintuitive".
