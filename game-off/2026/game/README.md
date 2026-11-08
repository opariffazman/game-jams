# Hot Shift

Run: `godot --path game-off/2026/game` (Godot 4.6 API, GL Compatibility). Phone test: `game-off/2026/scripts/export.sh`, then `game-off/2026/scripts/serve.sh` (HTTPS on the LAN).
Smoke test: add `--headless -- --smoke`. It runs the pool, boss, rule, locker, save, and full-run checks and prints `SMOKE OK`.
Regenerate the pool: run `--import` once, then `--headless -- --gen` (about 2 min). It writes `data/pool.json` and prints the gate and gunman tables.
Demos: `-- --run-demo` (a floor 2 shield room, the doors, boss intro, boss bar, knife zone, Locker), `-- --replay-demo` (a shield block replay, then the death reel; add `--jam` for a jam clear).

Undo and dead ends: each room and each boss phase gives 1 UNDO (`undos_per_room` in `RunState`, so an upgrade can raise it). The UNDO button (bottom left, or key `U`) restores the room before the last shift and refunds it. After each shift `DeadEnd` checks whether the room can still be won in the shifts left, with a 20000-node cap (over the cap it shows nothing). If not, a NO WAY OUT banner gives the cause: every gunman shielded (or behind cover when cover is on), too few shifts, every shift fatal, or no winning line. UNDO lights up. With no undo left, RETRY (bottom right, or Enter) costs 1 heart and retries the room. `-- --deadend-table` prints dead ends by cause. `-- --deadend-demo` shows the banner.
Dead-end gate: the pool keeps each room's share of non-fatal first shifts that lead to a dead end under F1 0.30, F2 0.40, F3 0.55 (F4 and final have no cap, mean about 0.73). Cause table: rerun `--deadend-table` for the cover-free pool. No rule changed, because a lone survivor caused 5 of 332 dead ends.

Run: one night up 12 rooms, 4 floors of 3. Room 12 is the boss. Taps and keys 1 to 5 pick gunmen, doors, and cards. Any tap continues after a fail.
- Hearts: 3 (4 or 5 with Max Hearts). A shot, a stab, or an empty shift budget costs 1 heart and retries the room. Heart cap is start plus 2.
- Budget: par plus slack (F1 +2, F2 +1, F3 +1, F4 and boss +0), plus Spare Clip and Spare Slack. Par ignores boons.
- After a clear: 3D replay (tap skips), then two doors from HEART, MONEY, ELITE, BOON.
- Boons: Quick Draw, Spare Clip, Bulletproof Coat. `R` replays the last clear. `T` or `--daily` seeds with today's date.

Cover is off: `Rooms.COVER_ENABLED` is false until cover gets one consistent rule (the lone-gunman strike skipped the cover check, two or more were blocked). The generator, motifs, `RoomState.from_room`, and the pool loader drop all cover, so shields are the only blocker. The cover rules (`clip_to_cover`, `cover_fraction`, `COVER_MARGIN`, the swap blink, the wasted strike) stay and the unit tests build states with cover directly. Set the switch to true and run `--gen` to bring walls back (gate covers ranges are 0 to 0 now).
Gunmen: pistol fires at the hero's start-of-turn cell. Shield blocks its front 120 degrees. Knife has no gun.
Turn events: jam (marked gunman is silent), advance (all non-knife gunmen step), reinforcement (a pistol gunman appears).
Telegraph rule: every arrow and line aims at the hero's cell at the start of the turn, so the plan is true for any tap.
- Advance: survivors step one cell toward that cell. The shifted gunman does not step.
- Knife: it threatens every cell within 2 grid steps (a ring is drawn). The room fails if the hero ends the turn inside the ring of a living knife. Then the knife steps toward the start-of-turn cell.

Boss THE MANAGER: intro card (1 s, tap skips), boss bar with 3 pips, then 3 puzzles from the final pool. Phase 1 is plain, phase 2 reinforces on turn 1, phase 3 has jam and advance. A phase clear shows a stinger and removes a pip. A fail costs a heart and retries that phase. The replay plays after phase 3 only, and no door follows.

Locker: a tap after NIGHT OVER or JOB COMPLETE opens it. Tap a card (or keys 1 to 6) to buy or equip. CLOCK IN (tap or Enter) starts a tower.
| Upgrade | Cost | Effect |
|---|---|---|
| Max Hearts I / II | 40 / 90 | Start with 4 / 5 hearts (II needs I) |
| Spare Slack | 60 | +1 shift on floors 1 and 2 |
| Opening Choice | 80 | Pick 1 of 3 boons at the start |
| Cyan Coat / Amber Coat | 30 each | Hero color. The default hero is white. |
Money income: +3 per room, +15 per floor, +50 for the boss, +10 MONEY door, +25 elite. About 6 rooms and 2 floors gives 48 base money. A full win gives 146 base money. Doors add more.

Gates (cover-free pool): every earlier gate holds, none relaxed. F2 trap 0.38 (gate 0.34), F3 0.73 (gate 0.67), F4 and final 1.00. F1 and F2 are close in numbers (win rate 0.33 vs 0.29, best 1.00 vs 1.05).
Reels (3D, any tap skips): the clear replay, the death reel, and the best chain. All read the event timeline from `turn_events.gd`.
- Death reel: when the last heart goes, the last 3 shifts of the failed attempt play from the state they start in. Earlier shifts are fast-forwarded. It ends on a slow bullet (or a knife lunge) and a gentle fade to black, then the NIGHT OVER panel.
- Best chain: the shift with the most kills in one resolution (strike plus friendly fire), earliest wins a tie. It auto-plays on JOB COMPLETE. On NIGHT OVER the panel has WATCH BEST CHAIN.
- 3D cues: backdrop wall and horizon band, muzzle flash, jam cross, shield block ring, Bulletproof Coat ring, bodies fall away from the lens.
- Share: each tower has a code such as `HS-4F2K9A` (30-bit seed, shown on the end panel and the Locker footer). COPY LINK copies the page URL with `?seed=CODE` on web, or the code on desktop. If the clipboard is missing or refused, the link shows as selectable text. A web page opened with `?seed=CODE` starts the first tower from it. A bad code gives a random seed. `T` and `--daily` still use the daily seed.
- Clips: there is no in-game video capture. Players can screen-record the reel. In-browser recording is untested.
Known gaps: the knife ring ignores cover (when on). No sound, no touch device test. The web clipboard path is untested in a real browser. A shield next to the camera can fill the lens in the 3D reel. The falling-body drift is untested in a rendered frame. The first launch opens straight into play, the Locker comes after the first run.
