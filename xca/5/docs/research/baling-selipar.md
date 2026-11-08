# Baling Selipar - research and gamification notes

Board: `docs/research/.lavish/baling-selipar-board.html`

## 1. Traditional rules

Sources are mostly school projects and blogs. Rules differ by group. Treat every number as a local convention.

| Topic | Finding | Confidence |
|---|---|---|
| Names | Baling selipar, tuju selipar, susun selipar. Sabah version is reported with sandals. | Medium |
| Equipment | 3 slippers stood upright in a triangle or pyramid. 1-2 extra slippers to throw. One Scribd variant uses 7 slippers. | High for 3 |
| Teams | Two sides: thrower team and defender or guard team. Size varies, 4-6 per side in student write-ups. | Medium |
| Turn | Each thrower gets up to 3 throws at the stack. A miss passes the turn to the other side. | High |
| After a knock-down | Throwers now throw at the defenders. A defender hit is "mati" (out). Defenders try to rebuild the stack. | High |
| Win | Variants: defenders win a round by rebuilding the triangle and stepping over it. Other: most rebuilds wins. Other: play until one side is out. | Low, conflicting |
| Distance | No standard. One student case study uses 3 m, raised to 4 m. | Low |
| Fouls | No throwing past the marked line. No body contact. Guard may not chase while holding a slipper. Guard may not knock down the rebuilt stack. | Medium |
| Safety | Use soft, thin slippers. | High |
| Space | Small. No pitch needed. Village yard, school field, road, corridor. | High |
| Culture | Remembered as kampung childhood play. Revived at traditional-games events and university culture days. | Medium |

## 2. Related games and usable mechanics

- Baling tin (tuju tin): same shape, with a ball and a stack of about 15 tins (rows 4-3-2-1 or 5-4-3-2-1). Rebuild gives 1 point. A hit defender is out. Source of the "rebuild under fire" scoring.
- Batu seremban: five stones, levels (buah) of rising difficulty. Usable idea: tiered upgrades, a foul ends the turn. Not a core mechanic.
- Lastik (rubber band flick) was not researched. No source found. Drop it.

## 3. What must stay (recognition)

- Sandals are the only projectile.
- A stack of 3 upright sandals is the objective, stood in a triangle.
- Knock the stack down, then the roles flip.
- Rebuild the stack under fire.
- A hit player is "mati".
- Three throws per turn. Use it as a 3-sandal ammo belt.
- Kampung look: dirt yard, chalk line, malay words (Mati, Susun, Baling).
- Chalk throw line that you cannot cross.

## 4. Concepts

### A. Susun Tumbang (stack siege) - recommended
- Loop: each team guards a 3-sandal stack at its base. Throw sandals to topple the enemy stack. A toppled stack scores a point and the owner must rebuild it. Hits on rebuilders mark them mati for a respawn delay.
- Round: 3 min. 3v3. Each player holds 3 sandals. Sandals land on the field and are picked up by walking over them.
- Win: most topples at the buzzer. First to 5 ends early. Tie goes to sudden death.
- Powers (cooldown): Angin Kencang, a curved throw (10 s). Selipar Kembar, 3 sandals in a fan (14 s). Tapak Besi, a shield that blocks one hit (18 s). Larian Kilat, a sprint (8 s). Pulang, recalls all your sandals to hand (20 s). Tin Palsu, a decoy stack (25 s).
- AI: roles of striker, guard, rebuilder. Striker picks a stack or an open enemy and aims with random error and a reaction delay. Guard stays near the stack and dodges. Rebuilder runs to a fallen stack. Easy, normal, hard are error and delay values.
- Mobile feel: drag back from the right thumb. A dotted line shows the reverse aim and length shows power. Release flings. A small haptic tick and a squash on the sandal sell the pull.
- First 30 s: you throw at once, a stack topples with a clack, and a bot runs to rebuild it.
- Risks: toppling a stack must be easy and physical but cheap in code. Rebuild timing can feel slow.

### B. Pasar Malam Mati (tag-out brawl)
- Loop: no stack. Hit enemies to mark them mati. Mid-field ammo piles respawn.
- Round: 2 min, 2v2. Team with most mati hits wins.
- Powers: same pool as A.
- AI: chase nearest, throw when in range.
- Fun: instant. Risk: loses the signature stack, so Malaysian players may not recognise it. Looks like generic dodgeball.

### C. Tendang Tin (stylized soccer)
- Loop: a heavy tin sits mid-field. Sandal hits push it. Push the tin into the enemy gate.
- Round: 3 min, 3v3. Goals win.
- Powers: same pool plus magnet.
- AI: pushes the tin toward the gate and defends the gate.
- Fun: soccer is readable. Risk: needs tin physics tuned for web, and sandals become a pusher not a game of knock-down.

## 5. Recommendation

Pick A, with the mati rule from the traditional game. It keeps the stack, the three throws, the rebuild and the mati rule. It also fits 3v3 and short rounds.

Feasibility for 48 h: 7 of 10. Rules are simple. The risk is touch input polish and AI.

Build first (core loop):
1. Top-down arena with chalk line, 2 stacks of 3 sandal bodies.
2. Move with joystick or WASD.
3. Drag-back-and-release throw with aim line.
4. Sandals as RigidBody2D or simple kinematic bodies. Topple check on hit.
5. Score, timer, win screen.
6. One bot type that throws and one that rebuilds.
7. Pickup and 3-sandal ammo belt.

Cut: powers beyond 2, online play, extra maps, custom art, music beyond one loop, skins, tutorial beyond one text card, 2v2 vs 3v3 toggle.

Technical risks, Godot 4.6 web on mobile:
- Touch: multitouch for joystick plus drag at the same time. Test `InputEventScreenTouch` and `InputEventScreenDrag` with `index` per finger. Do not rely on mouse emulation.
- Browser audio needs a user gesture before the first sound.
- Single-thread web export is the safe choice for GamePix. Threads need cross-origin isolation headers that an iframe host may not send. Unconfirmed for GamePix. Check.
- Physics cost on low-end phones. Keep under 30 bodies. Use simple circles.
- Landscape lock and safe areas. Set the stretch mode to `canvas_items` and `expand` aspect.
- Build size. Keep assets zero. Disable unused modules.
- Page scroll and pinch zoom during drag. Use `touch-action: none` in the HTML shell.

## 6. Open questions

1. Does the stack topple by physics, or by a simple hit count (for example one hit)?
2. Does a hit player drop their sandals?
3. Is mati a respawn timer (about 4 s) or out for the round?
4. Is Malay text in UI (Baling, Mati, Susun) acceptable, with English subtitles?
5. Is the arena a kampung yard theme, or neutral?
6. Does GamePix need the single-thread export? Check their submission rules.

## Sources

- https://ms.wikipedia.org/wiki/Baling_selipar
- https://permainantradisionalmas.blogspot.com/2016/02/baling-selipar.html
- https://x.com/MyMOTAC/status/1073084154193969152
- http://wak120-zanyedge.blogspot.com/2015/03/baling-selipar-permainan-baling-selipar.html
- http://balingselipar99.blogspot.com/
- https://www.scribd.com/doc/92355077/Peraturan-Permainan-Tradisional-Tuju-Selipar
- https://www.researchgate.net/publication/307858756_RE-CREATION_OF_MALAYSIAN_TRADITIONAL_GAME_NAMELY_'BALING_SELIPAR'_A_CRITICAL_REVIEW
- https://www.studocu.com/my/document/universiti-teknologi-mara/leisure-studies/group-2-baling-selipar-traditional-game/22051135
- https://www.fairusmamat.com/2011/03/cara-bermain-permainan-baling-tin.html
- https://www.scribd.com/doc/217233613/Baling-Tin-cara-Bermain
- https://www.scribd.com/doc/162219204/Peraturan-Permainan-Batu-Seremban

Note: the ResearchGate PDF could not be read (compressed). Its details come from search snippets only.
