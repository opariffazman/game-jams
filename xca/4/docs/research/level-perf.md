# Level performance

Measured with `tests/level.mjs` and `tests/level_profile.mjs` in headless Chrome on swiftshader (software GL, far slower than a real GPU).

## Before and after

| Measure | Before | After |
|---|---|---|
| Landscape fps, median | 7.5 | 10.0 |
| Landscape fps, street hidden | 30.3 | 28.8 |
| Landscape fps, street shown (static) | 13.5 | 19.5 |
| Portrait fps, median | 19.8 | 25.6 |
| Landscape worst draws | 69 | 62 |
| Portrait worst draws | 68 | 64 |
| Street draws | 7 | 1 |
| Street triangles in view | 17609 | 13589 |

Targets were about 45 draws and above 25 fps landscape. Both are unmet in landscape. Portrait meets the fps target.

## Changes

- Chunk pool ahead: 2 to 1. Fewer meshes drawn.
- Camera `far` 95 m. The fog hides everything past it.
- Backdrop ground: 600 m plane to 160 x 200 m, unshaded. It was overdraw beneath the chunk ground.
- Street material: per-vertex shading. No fps change in swiftshader.

## Findings

- Lights: the scene has one DirectionalLight3D, no OmniLights, no shadows. Nothing to cut.
- The street is one draw call per material per chunk. Merging more gains nothing.
- The inspect SubViewport uses `UPDATE_DISABLED` while closed.
- Draw calls come from the HUD (about 22), hero, particles and pooled zombies. The street adds 1 to 7.
- The remaining fps cost is fill rate. Swiftshader shades per pixel on the CPU. Hiding the street raises landscape fps from 19.5 to 28.8.
- `tests/level_profile.mjs` hides one group at a time with `railsBridge.levelOff`. Deltas between runs vary by up to 10 draws, because zombies and particles spawn during the run.

## Not verified

- Real GPU fps. Expected to be far above swiftshader.
- Draw-call target. A HUD pass (fewer Control nodes with their own draw) is the next step.

## Clean and Skip prompt

- Moved to top centre at y 192, below the hearts and weapon strip.
- Opaque dark panel, white text, white 2 px borders, blue buttons.
- Buttons are 150 x 64 px, above the 48 px minimum.
- The dirt bar hides while the prompt shows, because it overlapped the text in portrait.
- Inspect button and dirt bar use the same borders. Screenshots: `tests/level-run-landscape.png`, `tests/level-run-portrait.png`.
