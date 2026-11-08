# GamePix readiness checklist

Sources:
- Submission guidelines: https://partners.gamepix.com/guidelines/submission
- SDK docs index: https://partners.gamepix.com/sdk/doc
- HTML5 SDK guide: https://partners.gamepix.com/sdk/doc/javascript

## Build format

- [x] Web export, single-threaded (`variant/thread_support=false`). No COOP/COEP headers needed.
- [x] All resource paths are relative. The export uses `index.html`, `index.js`, `index.wasm`, `index.pck`.
- [ ] Upload archive layout: unconfirmed. The guidelines name only the Unity `.gpx` format. Ask GamePix or check the upload form in the partner dashboard.

## Size budget

- Max upload size: unconfirmed. The guidelines and SDK docs state no limit.
- Current export: `index.wasm` is 37.7 MB raw and 9.4 MB gzipped. The rest is under 0.4 MB.
- [ ] Decide a budget once GamePix confirms the limit. The engine wasm is fixed, so assets get what remains.

## External requests

- [x] The shell loads no fonts, CDNs, or analytics.
- [ ] Keep it so. Guidelines: no external links, analytics, or ads. Only the GamePix and Xsolla SDKs are allowed.
- [ ] Check the Network tab for third-party hosts before each submission.

## Audio

- [ ] Browsers block audio until a user gesture. The TAP TO PLAY overlay is that gesture. Start music only after the engine starts.
- [ ] Mute all audio on the SDK `pause` event. Guidelines require music and effects to stop during ads and incoming calls.

## Pause and resume

- [ ] Pause on the Page Visibility API (`visibilitychange`) and resume on return. Do not pause on iframe blur. Guidelines: "The game should only pause when the Page Visibility API is triggered."
- [ ] Make pause and resume idempotent. SDK handlers can fire repeatedly.

## Display and input

- [x] Viewport meta has `user-scalable=no`. Body has `touch-action: none`.
- [x] Loading screen (progress bar) shows during the initial load.
- [ ] Test inside an iframe of at least 640x480. The game must resize to the iframe.
- [ ] Rotate prompt conflict: the guidelines say "Remove any 'Rotate Your Device' prompts" and to use resize events. `web/shell.html` shows a rotate overlay in portrait. Decide before submission whether to remove it or make the game playable in portrait.
- [ ] The Fullscreen and orientation lock calls can fail inside the GamePix iframe if the iframe lacks the `allow` permission. Unconfirmed.

## SDK integration point

- SDK script: `https://integration.gamepix.com/sdk/v3/gamepix.sdk.js`. Load it in `web/shell.html` before `$GODOT_URL`. Load it only in the GamePix build, since it is an external request.
- Call `GamePix.lifecycle.loading(0..100)` from the shell `onProgress` callback.
- Call `await GamePix.lifecycle.loaded()` when `engine.startGame()` resolves.
- Call `GamePix.lifecycle.gameStart()` on the first real gameplay frame.
- Register `GamePix.events.on('pause', ...)` and `on('resume', ...)`. The pause handler must mute audio.
- Bridge to GDScript with `JavaScriptBridge` from an autoload in `autoload/`.
- Interstitial and reward ads: `GamePix.ads.interstitial()` and `GamePix.ads.reward()`. Both need `loaded()` first.
- Validate with the GamePix testkit on my.gamepix before submission, as the SDK docs recommend.
