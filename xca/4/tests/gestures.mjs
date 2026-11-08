import { chromium } from 'playwright-core';
// Usage: node tests/gestures.mjs <clip.y4m> [seconds] [steer]. Plays a fake-camera clip through MediaPipe and logs flick events from the packed tracker data.
// Make the clips first: python3 -I tests/make_gesture_clips.py (writes /tmp/gest/*.y4m).
const clip = process.argv[2];
const seconds = Number(process.argv[3] ?? 14);
const steer = process.argv[4] ?? 'flick';
const args = ['--use-fake-ui-for-media-stream', '--use-fake-device-for-media-stream', `--use-file-for-fake-video-capture=${clip}`,
  '--ignore-certificate-errors', '--enable-unsafe-swiftshader', '--use-gl=angle', '--use-angle=swiftshader'];
const browser = await chromium.launch({ executablePath: '/usr/bin/google-chrome', headless: true, args });
const page = await browser.newPage({ viewport: { width: Number(process.env.VW ?? 1280), height: Number(process.env.VH ?? 720) } });
const errors = [];
page.on('pageerror', (e) => errors.push('pageerror: ' + e.message));
await page.goto('https://localhost:8446/');
await page.waitForFunction(() => window.railsBridge?.godotFlow === 'select', null, { timeout: 60000 });
await page.evaluate((mode) => { window.railsBridge.setSteerMode(mode); window.railsBridge.setMagic(true); }, steer);
await page.waitForFunction(() => document.getElementById('startCam').textContent === 'Camera on', null, { timeout: 90000 });
await page.waitForTimeout(3000);
// Poll fast, and record every change of the gesture counter with the clip-relative time.
await page.evaluate(() => {
  window.__ev = []; window.__frames = []; window.__t0 = performance.now(); let lastGn = JSON.parse(window.railsBridge.packed).gn ?? 0; let lastSeq = -1;
  setInterval(() => {
    const b = window.railsBridge;
    if (b.seq === lastSeq) return;
    lastSeq = b.seq;
    const d = JSON.parse(b.packed);
    window.__frames.push([Math.round(performance.now() - window.__t0), d.n, d.s?.[0]?.[0] ?? 0, d.sl]);
    if (d.gn !== lastGn) { window.__ev.push([Math.round(performance.now() - window.__t0), d.gk, d.gn - lastGn]); lastGn = d.gn; }
  }, 10);
});
await page.waitForTimeout(seconds * 1000);
const out = await page.evaluate(() => ({ trace: window.__frames.map((f) => f.join(':')).join(' '), ev: window.__ev, frames: window.__frames.length, seen: window.__frames.filter((f) => f[1] > 0).length, last: JSON.parse(window.railsBridge.packed), hud: document.getElementById('hud').textContent }));
const rate = out.frames / seconds;
if (process.env.TRACE) console.log(out.trace);
console.log(JSON.stringify({ clip, steer, seconds, events: out.ev, resultFrames: out.frames, framesWithHand: out.seen, trackerFps: +rate.toFixed(1), errors }));
await browser.close();
