# 3D assets research

Question: what can we use for a 3D look. Gameplay stays 2D physics. Art stays behind `VisualSet` and `EntityVisual`.

## Answer

- Use the three Kenney packs for characters, the arena and scenery. All three are CC0.
- Build the sandal from primitives. No pack has one.
- Show the 3D art through one shared `SubViewport` with an angled orthographic camera (about 50 degrees). Build it after the 2D gameplay is done.
- Keep the pre-rendered sprite route (approach c) as the fallback if a phone cannot hold the frame rate.
- The Kenney floor is light peach. Blue `#40bfff` measures 1.09:1 on it and red `#ff5230` measures 1.69:1. The floor must be recoloured dark, or team colour fails.

## Method and limits

- Every number below comes from a script that read the GLB files in `/tmp/kenney`, or from a scratch Godot project in `/tmp/3d-scratch`. Nothing under `game/` changed.
- Frame times come from headless Chrome with software GL. The machine load average was 15 to 21 during the runs. These numbers are not phone numbers. Only the ratio between builds has meaning.
- Sources for Godot facts are the Godot docs, fetched with `ctx7`.

## 1. Inventory

All models use 1 material and share one 512 by 512 colormap per pack. The three packs have three different colormap files (three distinct MD5 hashes), so a model from one pack cannot use the texture of another.

### Characters (Mini Characters)

| Item | Value |
|---|---|
| Models | 20 humanoid, robot, alien and zombie variants named `character-*` |
| Triangles | 686 (male-b) to 947 (soldier) |
| Vertices | 1224 to 1841 |
| Bounding size | about 0.77 wide, 0.67 to 0.84 tall, 0.34 to 0.59 deep |
| Skeleton | 7 joints: root, leg-left, leg-right, torso, arm-left, arm-right, head |
| Meshes | 2 skinned meshes: `body-mesh` and `head-mesh` |
| Animations | 32 clips on every character |
| File size | 230 to 275 KB each |

Animation clips and length in seconds: static 0.10, idle 1.33, walk 0.67, sprint 0.50, jump 0.50, fall 0.33, crouch 0.17, sit 0.17, drive 0.17, die 0.33, pick-up 0.33, emote-yes 0.67, emote-no 0.67, holding-right/left/both 0.17, holding-*-shoot 0.20, attack-melee-right/left 0.42, attack-kick-right/left 0.53, interact-right/left 0.67, and 8 wheelchair clips.

Items in the same pack:

| Item | Triangles | Note |
|---|---|---|
| `weapon-sword`, `weapon-spear`, `weapon-bow`, `weapon-arrow`, `weapon-shooter` | 58 to 136 | Static, 0.1 to 0.6 long |
| `shield-round`, `shield-rectangle` | 160, 134 | Static |
| `wheelchair-*` (4) | 656 to 1040 | Not needed |
| `aid-*` (9), `item-luggage*` (2) | 48 to 176 | Not needed |

### Arena (Mini Arena)

| Model | Triangles | Bounding size (x, y, z) |
|---|---|---|
| `floor` | 2 | 1.0, 0.0, 1.0 |
| `floor-detail` | 50 | 1.0, 0.07, 1.0 |
| `border-straight` | 60 | 1.0, 0.4, 0.6 |
| `border-corner` | 122 | 0.8, 0.4, 0.8 |
| `wall`, `wall-corner`, `wall-gate` | 174, 226, 322 | 1.0, 1.0, 0.6 or 0.8 |
| `column`, `column-damaged` | 168, 148 | 0.6, 1.0 or 0.72, 0.6 |
| `block` | 12 | 1.0, 0.5, 1.0 |
| `stairs`, `stairs-corner`, `stairs-corner-inner` | 44, 84, 72 | 1.0, 0.5, 1.0 |
| `trophy` | 244 | 0.57, 0.48, 0.45 |
| `banner` | 228 | 0.6, 1.02, 0.23 |
| `statue` | 549 | 0.7, 1.34, 0.7 |
| `tree` | 330 | 0.65, 1.92, 0.65 |
| `bricks` | 120 | 0.77, 0.41, 0.85 |
| `character-soldier` | 513 | 25 animations |

### Scenery (Mini Forest)

| Model | Triangles |
|---|---|
| `tree`, `tree-high` | 182, 266 |
| `rocks-low`, `rocks-high`, `rocks-ramp`, `stones` | 342, 342, 234, 236 |
| `fence` | 330 |
| `tent` | 847 |
| `flag` | 162 |
| `patch-grass`, `patch-dirt` | 295, 108 |
| `plant` | 156 |
| `target` | 188 |
| `platform` | 651 |
| `bridge`, `ladder`, `building-*` | 144 to 508 |
| `character-archer` | 574, 32 animations |

### Gaps

| Need | In the packs | Result |
|---|---|---|
| Sandal, slipper, flip-flop | None. I found no footwear model. | Gap. See section 2. |
| Ball-like throwable | None. The sandal is the throwable, so this gap follows the sandal. | Gap. |
| Stack plinth | `block` (12 triangles, 1.0 by 0.5 by 1.0) or `column` (168 triangles) | Covered. |
| Arena floor and border | `floor`, `floor-detail`, `border-straight`, `border-corner` | Covered. |
| Trophy for match end | `trophy` (244 triangles) | Covered. |

Unconfirmed: I read only the three packs on disk. Kenney lists 3D packs on 14 pages. The fetch covered page 1 only (Mini Characters, Mini Shop, Mini Skate, City Kit Roads, City Kit Industrial, Mini Dungeon, Mini Forest). I did not open Mini Shop or Mini Dungeon for footwear.

## 2. The sandal

### Can the character's own feet serve as the sandal?

No. I cut the foot triangles out of `body-mesh` by vertex height and bone weight, then rendered the result.

| Measure | Result |
|---|---|
| Foot vertices (lowest 15 percent of the body mesh height) | male-a: 194 of 900. soldier: 150 of 1012. |
| Both feet split by bone | Even split between `leg-left` and `leg-right` |
| One cut foot (x greater than 0) | male-a 54 triangles, soldier 66, robot 78 |
| Watertight | No. The mesh is open at the cut line. |
| Colours in the foot zone | male-a: 5 cells. Tan `(230,185,110)`, brown `(144,87,65)`, light grey `(207,207,225)`, blue `(92,104,197)`, skin tones. |

The render (see the board) shows a blunt boot or a block with a strap-less top. I could not weld the cut edges into a count of open edges. The cut mesh has 92 to 136 unwelded boundary edges, which proves only that it is open. There is no thin flat sole and no strap, so it reads as a shoe stump and not as a sandal. The cut also needs a cap on the open side.

I measured the foot data on male-a, soldier and robot. I rendered soldier and robot only. The male-a foot sat outside the camera frame. This is a scratch layout flaw.

### Ranked options

| Rank | Option | Triangles | Licence | Reads as sandal | Cost |
|---|---|---|---|---|---|
| 1 | Primitive sandal: flattened sole plus two strap boxes | 96 with a 16-sided cylinder sole plus 24 for two boxes. A capsule sole costs 288 at 12 segments and 3456 at the default 64, and the scratch render used the default. | none | Yes. A flat brown sole with tan straps reads at once in the render. | 1 to 2 hours |
| 2 | CC0 Slippers by Isa Lousberg | 360 | CC0 | Slipper, yellow, rounded. Matches the chunky style. | 1 hour |
| 3 | CC-BY candidates (below) | 388 to 2032 | CC BY, credit needed | Mixed | 1 to 2 hours plus credits |
| 4 | Kenney character foot cut | 54 to 78 | CC0 | No | 3 hours and still a stump |

The primitive sandal can reuse the character colours by value. Sole brown `(144,87,65)`, strap tan `(230,185,110)`. In the colormap these sit at pixel x 96 to 127, y 343 to 345 (brown) and x 0 to 63, y 384 to 511 (tan). A flat albedo colour of the same value looks the same and needs no UV work. The primitive sandal also takes a team tint on the sole without clashing with a baked texture.

### Candidates found

I read licence text from the model pages. A fetch helper reported the CC BY version (3.0). I checked only the words "Creative Commons Attribution" on each page myself. The version stays unconfirmed.

| Model | Author | Licence | Triangles | Style fit | URL |
|---|---|---|---|---|---|
| Slippers | Isa Lousberg | Public Domain (CC0) | 360 | Good. One material with an embedded texture. The node carries a 100 times scale, so the real size is about 0.74 by 0.21 by 0.59 units. | https://poly.pizza/m/XV1WqNYen3 |
| Slippers | J-Toastie | Creative Commons Attribution | 560 | Not checked visually | https://poly.pizza/m/2wR1M99UwP |
| Sandal | jeremy | Creative Commons Attribution | 388 | Not checked visually. The raw size is 4.9 by 3.0 by 9.7 units, so it needs a rescale. | https://poly.pizza/m/4_4lQugjiRa |
| Flip flops | Poly by Google | Creative Commons Attribution | 2032 | Too dense. Raw size is about 954000 units, so the node transform is odd. | https://poly.pizza/m/aIMn3mC1FJ- |

Rejected or unreachable:

- Quaternius: its packs are CC0, but I found no footwear pack in the search results.
- OpenGameArt "Lowpoly shoe": the page returned HTTP 403. The search snippet says CC0 and calls it a sneaker.
- Creazilla "Slippers and Sandals": HTTP 403, licence not seen.
- Sketchfab low-poly flip-flop: licence not stated in the snippet.
- CGTrader and similar sites: mixed paid and free, not CC0 confirmed.

Recommendation: build the primitive sandal. Take the CC0 Isa Lousberg slippers only if the team wants a modelled slipper.

## 3. Integration approaches

Camera angles are in the next section. All approaches must keep touch, the HUD and the `EntityVisual` calls unchanged.

| Approach | Visual swap contract | Touch and HUD | Team colour | Hours (48 h jam) | Risk |
|---|---|---|---|---|---|
| a. One shared `SubViewport`, ortho `Camera3D`, `Node3D` per 2D body | A 3D skin makes a `Node3D` inside the shared world. The `EntityVisual` stays a `Node2D` proxy that copies the body transform each frame. | Unchanged. The viewport draws as a texture under the HUD. | Ring or disc under each character. | 14 to 20 | Aim line and rings are drawn in 2D, so they need the camera projection. Phone frame rate unconfirmed. |
| b. Full `Node3D` scene, 3D bodies locked to a plane | The contract breaks. Logic nodes change type. | Touch needs a ray cast to the ground plane. The HUD moves to a `CanvasLayer`. | Same as a. | 30 or more | Rewrites the physics and every test. Highest risk. |
| c. Pre-rendered sprites from the 3D models | `EntityVisual` stays as is. It plays an `AnimatedSprite2D`. | Fully unchanged. | A ring sprite under each character. | 10 to 16 for the render pipeline, plus a render per skin | Large sprite atlases. Facing needs 8 directions or a flip. A new skin needs a new render. |

Hours are my estimates and are unconfirmed.

Recommendation: approach a, behind a skin switch, after the 2D gameplay is stable. It keeps the swap contract and the 2D physics. Run a phone frame test first. Fall back to c if the frame rate fails.

### Cost of approach a, measured

Scratch scene: 6 or 12 animated Kenney characters, the arena floor and border, and 3 slippers, in an orthographic `SubViewport` at 50 degrees. Same viewport size (844 by 390), 240 frames, three repeat runs.

| Build | Mean frame time | p95 | Draw calls | Primitives |
|---|---|---|---|---|
| 2D baseline, 6 moving shapes | 16.6 ms | 16.8 ms | 7 | n/a |
| Real 2D game, current build | 16.6 ms | 16.8 ms | not read | n/a |
| 3D, 6 characters, no shadows | 35.1 to 39.3 ms | 50 ms | 38 | 7529 |
| 3D, 12 characters, no shadows | 42.7 to 44.4 ms | 50 ms | 50 | 12541 |
| 3D, 6 characters, one shadowed light | 74.9 to 77.5 ms | 83 ms | 74 | 11366 |

- 16.6 ms is the display refresh cap in headless Chrome. The 2D build does not use more than that, so the 3D ratio of about 2.2 times is a lower bound.
- One shadowed light doubled the frame time again. Plan for no real shadows and use a dark disc under each character.
- Files: the scratch `.pck` is 712 KB for 12 characters, the arena pieces and the slippers. The real game `.pck` is 1.2 MB. The `.wasm` is 37.7 MB in both, so it dominates the load.
- Load time was 1.1 to 2.6 s and varied more with machine load than with the scene. It does not separate the builds.
- This test does not run on a phone. Software GL on a loaded desktop CPU says nothing about an Android GPU. A phone test is required.

### Godot facts (source: Godot docs through ctx7)

| Fact | Source |
|---|---|
| Compatibility is the only renderer for web exports. | https://docs.godotengine.org/en/latest/tutorials/rendering/renderers.html |
| It draws lights with shadows in extra passes: the first pass has up to one shadowed `DirectionalLight3D`, and each later pass adds one omni, one spot and one directional shadow light. | https://docs.godotengine.org/en/latest/engine_details/architecture/internal_rendering_architecture.html |
| 3D MSAA works in Compatibility without alpha to coverage. 2D MSAA does not work. FXAA, SMAA and TAA are not supported. | https://docs.godotengine.org/en/latest/tutorials/rendering/renderers.html |
| `Viewport.scaling_3d_scale` below 1.0 speeds up 3D at a quality cost. | https://docs.godotengine.org/en/latest/classes/class_viewport.html |
| Import dock options include Root Type and Apply Root Scale. | https://docs.godotengine.org/en/latest/tutorials/assets_pipeline/importing_3d_scenes/import_configuration.html |

Unconfirmed: how many skinned characters a mid-range Android phone can draw at 60 frames per second. The skeleton has 7 joints, which keeps skinning cheap, but I did not measure it.

## 4. Camera angle

I rendered the scratch scene at four pitch angles (see the board).

| Pitch | View | Verdict |
|---|---|---|
| 90 degrees (top-down) | Only heads and shoulders show. Models lose their faces and animation reads poorly. | Worst for the models |
| 65 degrees | Faces visible, arena still reads as a field | Good |
| 50 degrees | Full figures, clear faces, border and floor read well | Best |
| 35 degrees | Models look best, but characters hide each other and the far side of the field shrinks | Too flat for a team arena |

Pick 50 degrees. One cost applies to every pitch below 90: the ground axis away from the camera squashes by sin(pitch). At 50 degrees that factor is 0.77. The 2D physics circle becomes an ellipse on screen. All 2D preview graphics (aim line, target ring, throw ring, orbit ring) must go through `Camera3D.unproject_position`, or be drawn in the 3D world. This is the main extra cost of approach a.

## 5. Team colour on models with their own palette

Floor contrast, measured with the exact team colours:

| Floor | Blue `#40bfff` | Red `#ff5230` |
|---|---|---|
| Current navy `(23,33,56)` | 7.71:1 | 4.96:1 |
| Kenney peach `(236,174,138)` | 1.09:1 | 1.69:1 |

A dark outline `#101828` reaches 9.29:1 on the peach floor. It reaches 1.11:1 on the navy floor.

Colour blindness (Machado simulation, severity 1.0). Blue and red stay apart in luminance on the navy floor by 2.42:1 under protanopia and 1.21:1 under deuteranopia. Red on navy drops to 3.49:1 under protanopia. This matches the earlier 2D finding. Shape carries the team there.

Heavy clothing clash. I estimated the share of each model's surface that has a blue or red colormap cell. The heuristic is rough.

| Model | Blue share | Red share |
|---|---|---|
| female-c | 23.6 percent | 42.9 percent |
| male-b | 13.5 | 46.6 |
| male-f | 0.1 | 44.2 |
| knight | 38.9 | 11.6 |
| robot | 45.7 | 0.0 |
| alien | 42.4 | 0.0 |
| male-e | 0.5 | 5.4 |
| female-e | 7.3 | 0.5 |
| zombie | 9.2 | 9.1 |

Models with the lowest clash: male-e, female-e, female-f, zombie, raider.

| Option | Readability | Cost | Verdict |
|---|---|---|---|
| Ring or disc under each character | Works with any outfit. One draw call. The human ring already exists. | Low | Pick this |
| Rim or outline shader | Outline colour fights the outfit. Needs a second pass. | Medium | No |
| Coloured armband mesh | Needs bone attachment per model. Small on screen. | Medium | No |
| `material_overlay` tint | Muddies the baked palette. Clash with blue and red outfits. | Low | No |

Pick the disc. Make the floor dark (a flat albedo override on `floor.glb`) so the current measured contrast still holds. Shape stays: circle disc for attackers, square disc for defenders.

## 6. Import and animation plan

Import:

- Keep each pack in its own folder with its own `Textures/colormap.png`. Do not copy a colormap into two folders. The importer then keeps one `.ctex` per file.
- Root type: `Node3D` (the default). Each GLB has one `AnimationPlayer` with the clips and two skinned meshes.
- Use `Apply Root Scale` for the slippers, because the node carries a scale of 100.
- Set loop mode on `idle`, `walk` and `sprint`. The clips are short (0.17 to 1.33 s). I set `LOOP_LINEAR` in code in the scratch test. Whether the importer sets a loop flag by default is unconfirmed.
- Check the texture compression for the web export. The current preset has `vram_texture_compression/for_mobile=false`. A 512 by 512 colormap is about 1 MB in VRAM uncompressed. This is unconfirmed on a phone.

Animation map:

| `EntityVisual` state | Kenney clip | Note |
|---|---|---|
| `idle` | `idle` (1.33 s) | Loop |
| `run` | `walk` (0.67 s) and `sprint` (0.50 s) | Blend by speed |
| `carry` | `holding-right` or `holding-both` (0.17 s) | A pose, not a loop |
| `throw` | `holding-right-shoot` (0.20 s) or `attack-melee-right` (0.42 s) | The shorter clip matches a flick |
| `dash` | `sprint` | Faster play speed |
| `die` | `die` (0.33 s) | No loop, hold the last frame |
| `hit` | `fall` (0.33 s) or `crouch` (0.17 s) | Short flinch |
| kick away | `attack-kick-right` (0.53 s) | Defender run-through |
| pick up | `pick-up` (0.33 s) | Sandal pick up |

Unusable or low value: `wheelchair-*`, `aid-*`, `item-luggage*`, and any character with more than about 40 percent blue or red surface (knight, robot, alien, female-c, male-b, male-f).

## 7. Licences and credits

| Source | Licence | Credit needed | `ASSETS.md` row |
|---|---|---|---|
| Kenney Mini Characters, Mini Arena, Mini Forest | CC0 | None. Optional line: `Kenney (www.kenney.nl)`. | Add one row per pack, with the zip name and date. |
| Primitive sandal | none | None | No row. |
| Isa Lousberg Slippers (poly.pizza) | CC0 | None | One row with the URL. |
| jeremy Sandal, J-Toastie Slippers, Poly by Google Flip flops | CC BY (3.0, unconfirmed) | Yes. Use: `"<title>" by <author>, https://poly.pizza/m/<id>, licensed under CC BY 3.0.` | One row and one line in `game/CREDITS.md`. |

The game-icons.net icons stay CC BY 3.0 and keep their existing credit lines. I did not edit `game/assets/ASSETS.md` or `game/CREDITS.md`. Another agent owns `game/`.

## Unconfirmed

- Frame rate of 3D on a real Android phone.
- Whether Kenney's other 3D packs contain a sandal.
- The CC BY version number (3.0) for the poly.pizza models.
- The visual fit of the J-Toastie and jeremy models. I only rendered the CC0 slippers.
- Estimated hours for every approach.
- Whether the glTF importer sets loop flags for Kenney clips.
- Texture compression effect on phones.
- The blue and red clothing shares. The heuristic depends on how I classified colormap cells.
- Contrast of a blue or red disc against its own dark outline.
