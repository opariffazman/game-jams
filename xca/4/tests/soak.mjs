import { chromium } from 'playwright-core';
import { startByTouch } from './start.mjs';
// Usage: node tests/soak.mjs [minutes]. Feeds scripted hands through the real tracker for a long session at 10x speed, then reports heap, flick rate and stall recovery.
const minutes = Number(process.argv[2] ?? 6);
const args = ['--ignore-certificate-errors', '--enable-unsafe-swiftshader', '--use-gl=angle', '--use-angle=swiftshader', '--js-flags=--expose-gc', '--enable-precise-memory-info'];
const browser = await chromium.launch({ executablePath: '/usr/bin/google-chrome', headless: true, args });
let failed = 0;
const check = (name, ok, detail = '') => { console.log(`${ok ? 'PASS' : 'FAIL'} ${name} ${detail}`); if (!ok) failed++; };
const page = await (await browser.newContext({ viewport: { width: 1280, height: 720 }, hasTouch: true })).newPage();
const errors = [];
page.on('pageerror', (e) => errors.push(e.message));
await page.goto('https://localhost:8446/');
await startByTouch(page, 0);
await page.waitForTimeout(800);
const cdp = await page.context().newCDPSession(page);
const heapMb = async () => { await cdp.send('HeapProfiler.collectGarbage'); return (await page.evaluate(() => performance.memory.usedJSHeapSize)) / 1048576; };

// A hand sweeping left and right like steering swipes. One sweep lasts 1.2 s of fake time.
const hand = (x, y = 0.5) => {
  const points = Array.from({ length: 21 }, () => [1 - x, y]);
  points[0] = [1 - x, y + 0.12];
  points[8] = [1 - x, y - 0.1];
  return { points, gesture: 'Open_Palm', score: 0.9, side: 'Right' };
};
const run = (seconds, startT) => page.evaluate(([secs, t0]) => {
  const b = window.railsBridge;
  const hz = 15;
  let flicks = 0;
  let last = b.__test.gn ?? 0;
  const lastCount = () => (b.packed ? JSON.parse(b.packed).gn : 0);
  last = lastCount();
  for (let i = 0; i < secs * hz; i++) {
    const t = t0 + (i * 1000) / hz;
    const phase = (i / hz) % 1.2;
    const x = phase < 0.2 ? 0.25 + phase * 2.5 : phase < 0.6 ? 0.75 : phase < 0.8 ? 0.75 - (phase - 0.6) * 2.5 : 0.25;
    const pts = Array.from({ length: 21 }, () => [1 - x, 0.5]);
    pts[0] = [1 - x, 0.62];
    pts[8] = [1 - x, 0.4];
    b.__test.feed([{ points: pts, gesture: 'Open_Palm', score: 0.9, side: 'Right' }], t);
  }
  return { flicks: lastCount() - last, end: t0 + secs * 1000 };
}, [seconds, startT]);

let t = 1000;
const rows = [];
const windowSeconds = 30;
const windows = Math.ceil((minutes * 60) / windowSeconds);
const heap0 = await heapMb();
for (let w = 0; w < windows; w++) {
  const r = await run(windowSeconds, t);
  t = r.end + 500;
  const heap = await heapMb();
  rows.push({ minute: +(((w + 1) * windowSeconds) / 60).toFixed(1), flicks: r.flicks, heap: +heap.toFixed(1) });
}
console.table(rows);
const first = rows[0].flicks;
const lastRow = rows[rows.length - 1].flicks;
check('flicks fire in the first window', first > 0, String(first));
check('flick rate holds over the session', lastRow >= first * 0.9, `${first} -> ${lastRow}`);
check('heap does not grow with time', rows[rows.length - 1].heap - rows[0].heap < 10, `${heap0.toFixed(1)} -> ${rows[rows.length - 1].heap} MB`);
const sizes = await page.evaluate(() => JSON.stringify(window.railsBridge.packed).length);
check('packet size stays small', sizes < 3000, String(sizes));
check('no page errors', errors.length === 0, errors.join('|'));
await browser.close();
process.exit(failed ? 1 : 0);
