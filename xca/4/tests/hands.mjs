import { chromium } from 'playwright-core';
// Usage: node tests/hands.mjs. Injects two hands in the packed data and checks that only the chosen hand drives the reticle.
// The tracker's side choice runs in the page, so this test feeds hands through the real readHands via a fake worker result.
const args = ['--use-fake-ui-for-media-stream', '--use-fake-device-for-media-stream',
  '--ignore-certificate-errors', '--enable-unsafe-swiftshader', '--use-gl=angle', '--use-angle=swiftshader'];
const browser = await chromium.launch({ executablePath: '/usr/bin/google-chrome', headless: true, args });
const fail = [];
const expect = (ok, msg) => { if (!ok) fail.push(msg); console.log(ok ? 'PASS' : 'FAIL', msg); };
const page = await (await browser.newContext({ viewport: { width: 1280, height: 720 } })).newPage();
await page.goto('https://localhost:8446/');
await page.waitForFunction(() => window.railsBridge && window.railsBridge.godotFlow === 'select', null, { timeout: 60000 });

// A hand whose knuckle sits at mirrored x. The raw landmark x is 1 - mirrored x. A larger palm is nearer the camera.
const handAt = (mirroredX, y = 0.5, palm = 0.1) => {
  const points = Array.from({ length: 21 }, () => [1 - mirroredX, y]);
  points[0] = [1 - mirroredX, y + palm];
  points[8] = [1 - mirroredX, y - 0.1];
  return { points, gesture: 'None', score: 0 };
};
const slotX = async (hands, now) => (await page.evaluate(([h, t]) => { window.railsBridge.__test.feed(h, t); const d = JSON.parse(window.railsBridge.packed); return [d.n, d.s[0][0]]; }, [hands, now]));

// No hand choice exists. The hand nearest the camera plays, whichever side it is on.
for (const [near, label] of [[0.2, 'left'], [0.8, 'right']]) {
  const hands = near === 0.2 ? [handAt(0.2, 0.5, 0.16), handAt(0.8, 0.5, 0.08)] : [handAt(0.2, 0.5, 0.08), handAt(0.8, 0.5, 0.16)];
  const [n, x] = await slotX(hands, label === 'left' ? 1000 : 3000);
  expect(n === 1 && Math.abs(x - near) < 0.001, `the nearer ${label} hand plays (n ${n}, x ${x})`);
}
const [, lone] = await slotX([handAt(0.3)], 5000);
expect(Math.abs(lone - 0.3) < 0.001, `a lone hand is accepted on either side (x ${lone})`);
await slotX([handAt(0.2, 0.5, 0.08), handAt(0.7, 0.5, 0.16)], 6000);
const [, near] = await slotX([handAt(0.2), handAt(0.55)], 6100);
expect(Math.abs(near - 0.55) < 0.001, `the tracked hand keeps the cursor (x ${near})`);
const [, crossed] = await slotX([handAt(0.6), handAt(0.52)], 6200);
expect(Math.abs(crossed - 0.52) < 0.001, `crossing hands does not swap the cursor (x ${crossed})`);
// The player tires and swaps hands: the old hand leaves, the other one plays at once.
await slotX([], 8000);
const [sn, swapped] = await slotX([handAt(0.15)], 8700);
expect(sn === 1 && Math.abs(swapped - 0.15) < 0.001, `switching to the other hand works (x ${swapped})`);
await browser.close();
if (fail.length) { console.log('FAILED', fail.length); process.exit(1); }
console.log('ALL PASS');
