import { chromium } from 'playwright-core';
import { startByTouch } from './start.mjs';
// Usage: node tests/palm_gate.mjs. Two palms: a brief show never opens the viewer, held two palms do, and a fist never closes it.
const args = ['--ignore-certificate-errors', '--enable-unsafe-swiftshader', '--use-gl=angle', '--use-angle=swiftshader'];
const browser = await chromium.launch({ executablePath: '/usr/bin/google-chrome', headless: true, args });
let failed = 0;
const check = (name, ok, detail = '') => { console.log(`${ok ? 'PASS' : 'FAIL'} ${name} ${detail}`); if (!ok) failed++; };
const context = await browser.newContext({ viewport: { width: 1280, height: 720 }, hasTouch: true });
const page = await context.newPage();
const errors = [];
page.on('pageerror', (e) => errors.push(e.message));
await page.goto('https://localhost:8446/');
await startByTouch(page, 0);
await page.waitForTimeout(800);
await page.evaluate(() => {
  const b = window.railsBridge;
  window.__frame = 900000;
  Object.defineProperty(b, 'seq', { get: () => window.__frame, set: () => {} });
  b.magic = true;
  b.cameraKey = 'scripted|1280x720';
});
// pose 1 is two open palms, 2 is the fist, 0 is a relaxed hand. Frames arrive at 12 Hz like the real tracker.
const hold = async (pose, seconds) => {
  const end = Date.now() + seconds * 1000;
  while (Date.now() < end) {
    await page.evaluate((p) => {
      window.__frame++;
      Object.defineProperty(window.railsBridge, 'packed', { configurable: true, get: () => JSON.stringify({ m: 1, n: 1, ok: true, f: window.__frame, ps: 0.2, gs: 0, fr: 1.5, pg: 0, pr: 1.5, tp: p === 1 ? 1 : 0, s: [[0.5, 0.6, p === 1 ? 0 : p]], gn: 0, gk: '', sl: -1, th: null, sr: 0 }) });
    }, pose);
    await page.waitForTimeout(80);
  }
};
const open = () => page.evaluate(() => window.railsBridge.godotInspect);
await hold(0, 1.0);
const menu = (await page.evaluate(() => window.railsBridge.godotUiRects)).find((r) => r[0] === 'Menu');
await page.mouse.click(menu[1] + menu[3] / 2, menu[2] + menu[4] / 2);
await page.waitForTimeout(800);
await hold(1, 0.4);
await hold(0, 0.6);
check('a brief two-palm show never opens the viewer', await open() === 0);
await hold(1, 1.0);
check('two palms held 1 s is still not enough', await open() === 0);
await hold(1, 2.5);
await page.waitForTimeout(300);
check('two palms held for the full gate opens the viewer', await open() === 1);
await hold(2, 4);
check('a held fist never closes the viewer', await open() === 1);
await hold(0, 4);
check('a hand that hangs never closes the viewer', await open() === 1);
check('no page errors', errors.length === 0, errors.join('|'));
await browser.close();
process.exit(failed ? 1 : 0);
