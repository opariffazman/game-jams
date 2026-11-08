import { chromium } from 'playwright-core';
import { startByTouch } from './start.mjs';
// Usage: node tests/runner.mjs. Plays the lane runner by keyboard and touch swipe, then feeds webcam flick events, and screenshots four sizes.
const SIZES = [[1280, 720], [720, 1280], [390, 844], [844, 390]];
const args = ['--ignore-certificate-errors', '--enable-unsafe-swiftshader', '--use-gl=angle', '--use-angle=swiftshader'];
const browser = await chromium.launch({ executablePath: '/usr/bin/google-chrome', headless: true, args });
const page = await browser.newPage({ viewport: { width: 1280, height: 720 }, hasTouch: true });
let failed = 0;
const check = (name, ok, detail = '') => { console.log(`${ok ? 'PASS' : 'FAIL'} ${name} ${detail}`); if (!ok) failed++; };
const state = () => page.evaluate(() => ({ lane: window.railsBridge.godotLane, weapon: window.railsBridge.godotWeapon, dist: window.railsBridge.godotDistance, hearts: window.railsBridge.godotHearts, flicks: window.railsBridge.godotFlicks, flow: window.railsBridge.godotFlow }));
const settle = () => page.waitForTimeout(700);

await page.goto('https://localhost:8446/');
await startByTouch(page, 0);
await page.waitForTimeout(1500);
let s = await state();
check('run starts in the middle lane', s.lane === 1, JSON.stringify(s));
check('the world moves', s.dist > 1, `dist ${s.dist}`);

await page.keyboard.press('a'); await settle();
s = await state(); check('A moves left', s.lane === 0, `lane ${s.lane}`);
await page.keyboard.press('a'); await settle();
s = await state(); check('left edge holds', s.lane === 0, `lane ${s.lane}`);
await page.keyboard.press('ArrowRight'); await page.keyboard.press('ArrowRight'); await settle();
s = await state(); check('arrow right moves to the right edge', s.lane === 2, `lane ${s.lane}`);

const w0 = (await state()).weapon;
await page.keyboard.press('s'); await settle();
const w1 = (await state()).weapon;
check('S cycles to the next weapon', w1 !== w0, `${w0} -> ${w1}`);
await page.keyboard.press('w'); await settle();
check('W cycles back', (await state()).weapon === w0);

// Touch swipe: a quick drag left across the screen.
async function swipeTouch(dx, dy) {
  const client = await page.context().newCDPSession(page);
  const x = 640, y = 360;
  await client.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x, y }] });
  await page.waitForTimeout(30);
  await client.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x: x + dx, y: y + dy }] });
  await page.waitForTimeout(30);
  await client.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
}
await swipeTouch(-200, 0); await settle();
s = await state(); check('swipe left moves a lane', s.lane === 1, `lane ${s.lane}`);
const w2 = s.weapon;
await swipeTouch(0, 200); await settle();
check('swipe down cycles the weapon', (await state()).weapon !== w2);

// Webcam flick events through a packed feed. A rise of gn is one event.
let packedFrame = 900000;
const feed = (gn, gk) => page.evaluate(([n, k, f]) => {
  window.railsBridge.packed = JSON.stringify({ m: 0, n: 0, ok: true, s: [], f, gn: n, gk: k, sl: -1, th: null, sr: 0 });
  window.railsBridge.seq = (window.railsBridge.seq || 0) + 1;
  return 'ok';
}, [gn, gk, ++packedFrame]);
await feed(1, 'l'); await settle(); // baseline, never fires
const beforeFlick = await state();
await feed(2, 'r'); await settle();
s = await state(); check('flick event r moves right', s.lane === beforeFlick.lane + 1 && s.flicks === beforeFlick.flicks + 1, JSON.stringify(s));
await feed(2, 'l'); await settle();
const same = await state(); check('a repeated gn is ignored', same.lane === s.lane, `lane ${same.lane}`);

for (const [w, h] of SIZES) {
  const before = await state();
  await page.setViewportSize({ width: w, height: h });
  await page.waitForTimeout(1200);
  const after = await state();
  check(`rotate to ${w}x${h} keeps the run`, after.dist >= before.dist && after.flow === 'play', `${before.dist.toFixed(0)} -> ${after.dist.toFixed(0)}`);
  await page.screenshot({ path: `tests/runner-${w}x${h}.png` });
}
await browser.close();
console.log(failed ? `${failed} FAILED` : 'ALL PASS');
process.exit(failed ? 1 : 0);
