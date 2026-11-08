import { chromium } from 'playwright-core';
import { startByTouch } from './start.mjs';
// Usage: node tests/inspect.mjs. Opens the weapon viewer in a run, then zooms, turns and scrubs by mouse, keys, touch and injected hand data.
const args = ['--ignore-certificate-errors', '--enable-unsafe-swiftshader', '--use-gl=angle', '--use-angle=swiftshader'];
const browser = await chromium.launch({ executablePath: '/usr/bin/google-chrome', headless: true, args });
let failed = 0;
const check = (name, ok, detail = '') => { console.log(`${ok ? 'PASS' : 'FAIL'} ${name} ${detail}`); if (!ok) failed++; };
// Counts bright cyan pixels and checks the backdrop, from a screenshot decoded in the page.
async function pixels(page) {
  const png = (await page.screenshot()).toString('base64');
  return page.evaluate(async (data) => {
    const img = new Image(); img.src = 'data:image/png;base64,' + data; await img.decode();
    const c = document.createElement('canvas'); c.width = img.width; c.height = img.height;
    const g = c.getContext('2d'); g.drawImage(img, 0, 0);
    const d = g.getImageData(0, 0, c.width, c.height).data;
    let cyan = 0, dark = 0, total = 0;
    for (let i = 0; i < d.length; i += 16) { total++; const r = d[i], gr = d[i + 1], b = d[i + 2]; if (gr > 150 && b > 150 && r < 140) cyan++; if (r + gr + b < 110) dark++; }
    return { cyan: cyan / total, dark: dark / total };
  }, png);
}
const shotPath = (name) => new URL(`./${name}.png`, import.meta.url).pathname;

async function begin(viewport) {
  const context = await browser.newContext({ viewport, hasTouch: true });
  const page = await context.newPage();
  const errors = [];
  page.on('pageerror', (e) => errors.push(e.message));
  await page.goto('https://localhost:8446/');
  await page.setViewportSize({ width: 1280, height: 720 });
  await startByTouch(page, 0);
  await page.setViewportSize(viewport);
  await page.waitForTimeout(800);
  return { page, context, errors };
}
const read = (page) => page.evaluate(() => { const b = window.railsBridge; return { open: b.godotInspect, grime: b.godotGrime, zoom: b.godotInspectZoom, yaw: b.godotInspectYaw, dist: b.godotDistance, weapon: b.godotWeapon, lane: b.godotLane }; });
const waitGrime = (page, level) => page.waitForFunction((l) => window.railsBridge.godotGrime >= l, level, { timeout: 180000 });
let feedSeq = 800000;
const feed = (page, extra) => page.evaluate(([e, f]) => {
  window.railsBridge.packed = JSON.stringify({ m: 0, n: 0, ok: true, s: [], f, gn: 0, gk: '', sl: -1, th: null, sr: 0, ...e });
  window.railsBridge.seq = (window.railsBridge.seq || 0) + 1;
}, [extra, ++feedSeq]);

// Desktop: keyboard, wheel, drag.
{
  const { page, context, errors } = await begin({ width: 1280, height: 720 });
  await waitGrime(page, 0.12);
  let s = await read(page);
  check('shots add dirt', s.grime >= 0.12, `grime ${s.grime.toFixed(2)}`);
  await page.screenshot({ path: shotPath('inspect-run-dirty') });
  // The SMG fires fast, so its dirt reaches a level where the overlay shows.
  await page.keyboard.press('s'); await page.waitForTimeout(300); await page.keyboard.press('s');
  await waitGrime(page, 0.45);
  await page.screenshot({ path: shotPath('inspect-run-filthy') });
  await page.keyboard.press('w'); await page.waitForTimeout(300); await page.keyboard.press('w');
  await page.waitForTimeout(400);
  await page.keyboard.press('i');
  await page.waitForTimeout(900);
  s = await read(page);
  check('I opens the viewer', s.open === 1, JSON.stringify(s));
  const d0 = s.dist;
  await page.waitForTimeout(1200);
  s = await read(page);
  check('the run pauses while open', Math.abs(s.dist - d0) < 0.5, `moved ${(s.dist - d0).toFixed(2)} m`);
  await page.screenshot({ path: shotPath('inspect-1280x720') });
  const px = await pixels(page);
  check('the viewer covers the run with a dark backdrop', px.dark > 0.7, `dark ${px.dark.toFixed(2)}`);
  check('the viewer draws cyan hologram parts', px.cyan > 0.0008, `cyan ${px.cyan.toFixed(4)}`);

  const z0 = s.zoom;
  await page.mouse.move(640, 360);
  for (let i = 0; i < 4; i++) await page.mouse.wheel(0, -120);
  await page.waitForTimeout(500);
  s = await read(page);
  check('wheel up zooms in', s.zoom > z0, `${z0.toFixed(2)} -> ${s.zoom.toFixed(2)}`);
  for (let i = 0; i < 40; i++) await page.mouse.wheel(0, -120);
  await page.waitForTimeout(400);
  s = await read(page);
  check('zoom stops at the maximum', s.zoom <= 2.61, `zoom ${s.zoom.toFixed(2)}`);
  for (let i = 0; i < 80; i++) await page.mouse.wheel(0, 120);
  await page.waitForTimeout(400);
  s = await read(page);
  check('zoom stops at the minimum', s.zoom >= 0.59, `zoom ${s.zoom.toFixed(2)}`);

  const y0 = s.yaw;
  await page.keyboard.down('ArrowRight');
  await page.waitForTimeout(600);
  await page.keyboard.up('ArrowRight');
  s = await read(page);
  check('arrow right turns the weapon', Math.abs(s.yaw - y0) > 0.3, `${y0.toFixed(2)} -> ${s.yaw.toFixed(2)}`);

  const g1 = s.grime;
  await page.mouse.move(400, 360);
  await page.mouse.down();
  for (let c = 0; c < 1; c++) {
    for (let x = 400; x <= 800; x += 40) await page.mouse.move(x, 360);
    for (let x = 800; x >= 400; x -= 40) await page.mouse.move(x, 360);
  }
  await page.mouse.up();
  await page.waitForTimeout(300);
  s = await read(page);
  check('dragging back and forth scrubs', s.grime < g1, `${g1.toFixed(2)} -> ${s.grime.toFixed(2)}`);

  const g0 = s.grime;
  await page.keyboard.down(' ');
  await page.waitForTimeout(1500);
  await page.keyboard.up(' ');
  s = await read(page);
  check('holding Space scrubs dirt off', s.grime < g0, `${g0.toFixed(2)} -> ${s.grime.toFixed(2)}`);

  await page.keyboard.down(' ');
  await page.waitForFunction(() => window.railsBridge.godotGrime === 0, null, { timeout: 15000 }).catch(() => {});
  await page.keyboard.up(' ');
  s = await read(page);
  check('scrubbing to the end is spotless', s.grime === 0, `grime ${s.grime}`);
  await page.waitForTimeout(500);
  await page.screenshot({ path: shotPath('inspect-clean') });

  const w0 = s.weapon;
  await page.keyboard.press('a');
  await page.waitForTimeout(300);
  check('steering is off while open', (await read(page)).lane === s.lane);
  await page.keyboard.press('Escape');
  await page.waitForTimeout(700);
  s = await read(page);
  check('Escape closes the viewer', s.open === 0, JSON.stringify(s));
  const d1 = s.dist;
  await page.waitForTimeout(1200);
  check('the run resumes', (await read(page)).dist > d1 + 1);
  check('the page reports no error', errors.length === 0, errors.join('|'));
  await context.close();
}

// Injected hand data: two-hand zoom, turn and a scrub counter rise.
{
  const { page, context, errors } = await begin({ width: 1280, height: 720 });
  await waitGrime(page, 0.1);
  await page.keyboard.press('i');
  await page.waitForTimeout(800);
  let s = await read(page);
  check('viewer open for hand data', s.open === 1);
  await feed(page, { th: [1.0, 0.0, 0.5, 0.5] });
  await page.waitForTimeout(300);
  const z0 = (await read(page)).zoom;
  await feed(page, { th: [1.6, 0.0, 0.5, 0.5] });
  await page.waitForTimeout(500);
  s = await read(page);
  check('hands spreading zooms in', s.zoom > z0 * 1.4, `${z0.toFixed(2)} -> ${s.zoom.toFixed(2)}`);
  const y0 = s.yaw;
  await feed(page, { th: [1.6, 0.0, 0.7, 0.5] });
  await page.waitForTimeout(500);
  s = await read(page);
  check('moving both hands sideways turns the weapon', Math.abs(s.yaw - y0) > 0.3, `${y0.toFixed(2)} -> ${s.yaw.toFixed(2)}`);
  const y1 = s.yaw;
  await feed(page, { th: [1.6, 0.8, 0.7, 0.5] });
  await page.waitForTimeout(500);
  s = await read(page);
  check('tilting the hands rolls without changing the turn much', Math.abs(s.yaw - y1) < 0.6, `${y1.toFixed(2)} -> ${s.yaw.toFixed(2)}`);
  const g0 = s.grime;
  await page.keyboard.down(' ');
  await page.waitForTimeout(1500);
  await page.keyboard.up(' ');
  s = await read(page);
  check('holding Space scrubs dirt off', s.grime < g0, `${g0.toFixed(2)} -> ${s.grime.toFixed(2)}`);

  await page.keyboard.down(' ');
  await page.waitForFunction(() => window.railsBridge.godotGrime === 0, null, { timeout: 15000 }).catch(() => {});
  await page.keyboard.up(' ');
  s = await read(page);
  check('scrubbing to the end is spotless', s.grime === 0, `grime ${s.grime}`);
  await page.waitForTimeout(500);
  await page.screenshot({ path: shotPath('inspect-clean') });

  const w0 = s.weapon;
  await page.keyboard.press('a');
  await page.waitForTimeout(300);
  check('steering is off while open', (await read(page)).lane === s.lane);
  await page.keyboard.press('Escape');
  await page.waitForTimeout(700);
  s = await read(page);
  check('Escape closes the viewer', s.open === 0, JSON.stringify(s));
  const d1 = s.dist;
  await page.waitForTimeout(1200);
  check('the run resumes', (await read(page)).dist > d1 + 1);
  check('the page reports no error', errors.length === 0, errors.join('|'));
  await context.close();
}

// Injected hand data: two-hand zoom, turn and a scrub counter rise.
{
  const { page, context } = await begin({ width: 1280, height: 720 });
  await waitGrime(page, 0.1);
  await page.keyboard.press('i');
  await page.waitForTimeout(800);
  let s = await read(page);
  check('viewer open for hand data', s.open === 1);
  await feed(page, { th: [1.0, 0.0, 0.5, 0.5] });
  await page.waitForTimeout(300);
  const z0 = (await read(page)).zoom;
  await feed(page, { th: [1.6, 0.0, 0.5, 0.5] });
  await page.waitForTimeout(500);
  s = await read(page);
  check('hands spreading zooms in', s.zoom > z0 * 1.4, `${z0.toFixed(2)} -> ${s.zoom.toFixed(2)}`);
  const y0 = s.yaw;
  await feed(page, { th: [1.6, 0.0, 0.7, 0.5] });
  await page.waitForTimeout(500);
  s = await read(page);
  check('moving both hands sideways turns the weapon', Math.abs(s.yaw - y0) > 0.3, `${y0.toFixed(2)} -> ${s.yaw.toFixed(2)}`);
  const y1 = s.yaw;
  await feed(page, { th: [1.6, 0.8, 0.7, 0.5] });
  await page.waitForTimeout(500);
  s = await read(page);
  check('tilting the hands rolls without changing the turn much', Math.abs(s.yaw - y1) < 0.6, `${y1.toFixed(2)} -> ${s.yaw.toFixed(2)}`);
  const g0 = s.grime;
  await feed(page, { th: null, sr: 0 });
  await page.waitForTimeout(200);
  await feed(page, { th: null, sr: 4 });
  await page.waitForTimeout(500);
  s = await read(page);
  check('scrub counter rise cleans', s.grime < g0, `${g0.toFixed(2)} -> ${s.grime.toFixed(2)} open ${s.open}`);
  await feed(page, { th: [1.6, 0.8, 0.7, 0.5], tp: 0 });
  await page.waitForTimeout(900);
  await feed(page, { th: [1.6, 0.8, 0.7, 0.5], tp: 1 });
  await page.waitForTimeout(800);
  check('two palms held less than the gate keep the viewer open', (await read(page)).open === 1);
  await page.waitForTimeout(1500);
  check('two palms held still close the viewer', (await read(page)).open === 0);
  await context.close();
}

// Touch: pinch zoom, one-finger scrub, and the layout in portrait and phone sizes.
for (const [w, h] of [[720, 1280], [390, 844], [844, 390]]) {
  const { page, context } = await begin({ width: w, height: h });
  await waitGrime(page, 0.1);
  await page.keyboard.press('i');
  await page.waitForTimeout(900);
  let s = await read(page);
  check(`${w}x${h} viewer opens`, s.open === 1);
  const client = await page.context().newCDPSession(page);
  const cx = w / 2, cy = h / 2;
  const touch = (type, pts) => client.send('Input.dispatchTouchEvent', { type, touchPoints: pts.map(([x, y], id) => ({ x, y, id })) });
  const z0 = s.zoom;
  await touch('touchStart', [[cx - 40, cy], [cx + 40, cy]]);
  for (let i = 1; i <= 10; i++) { await touch('touchMove', [[cx - 40 - i * 8, cy], [cx + 40 + i * 8, cy]]); await page.waitForTimeout(30); }
  await touch('touchEnd', []);
  await page.waitForTimeout(500);
  s = await read(page);
  check(`${w}x${h} pinch out zooms in`, s.zoom > z0 * 1.3, `${z0.toFixed(2)} -> ${s.zoom.toFixed(2)}`);
  const g0 = s.grime;
  await touch('touchStart', [[cx - 80, cy + 60]]);
  for (let c = 0; c < 8; c++) {
    for (let i = 0; i <= 8; i++) { await touch('touchMove', [[cx - 80 + i * 20, cy + 60]]); await page.waitForTimeout(16); }
    for (let i = 8; i >= 0; i--) { await touch('touchMove', [[cx - 80 + i * 20, cy + 60]]); await page.waitForTimeout(16); }
  }
  await touch('touchEnd', []);
  await page.waitForTimeout(400);
  s = await read(page);
  check(`${w}x${h} finger scrub cleans`, s.grime < g0, `${g0.toFixed(2)} -> ${s.grime.toFixed(2)}`);
  await page.screenshot({ path: shotPath(`inspect-${w}x${h}`) });
  const px = await pixels(page);
  check(`${w}x${h} backdrop covers the run`, px.dark > 0.7, `dark ${px.dark.toFixed(2)}`);
  await context.close();
}
await browser.close();
process.exit(failed ? 1 : 0);
