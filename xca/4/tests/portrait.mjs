import { chromium } from 'playwright-core';
// Usage: node tests/portrait.mjs. Opens each screen at four sizes, saves screenshots, and checks that buttons and cards stay on screen, reach 48 px, and never overlap.
const args = ['--use-fake-ui-for-media-stream', '--use-fake-device-for-media-stream',
  '--ignore-certificate-errors', '--enable-unsafe-swiftshader', '--use-gl=angle', '--use-angle=swiftshader'];
const SIZES = [[720, 1280], [390, 844], [844, 390], [1280, 720], [1920, 1080], [2560, 1440]];
const MIN_TARGET = 48;
const browser = await chromium.launch({ executablePath: '/usr/bin/google-chrome', headless: true, args });
const fail = [];
const expect = (ok, msg) => { if (!ok) fail.push(msg); console.log(ok ? 'PASS' : 'FAIL', msg); };
const shot = (page, name, w, h) => page.screenshot({ path: new URL(`./portrait-${name}-${w}x${h}.png`, import.meta.url).pathname });

async function check(page, name, w, h) {
  await page.waitForTimeout(700);
  const rects = await page.evaluate(() => window.railsBridge.godotUiRects ?? []);
  const label = `${name} ${w}x${h}`;
  for (const [text, x, y, rw, rh] of rects) {
    expect(x >= -0.5 && y >= -0.5 && x + rw <= w + 0.5 && y + rh <= h + 0.5, `${label}: "${text}" stays on screen`);
    expect(rw >= MIN_TARGET && rh >= MIN_TARGET, `${label}: "${text}" is at least ${MIN_TARGET} px (${rw.toFixed(0)}x${rh.toFixed(0)})`);
  }
  for (let i = 0; i < rects.length; i++) for (let j = i + 1; j < rects.length; j++) {
    const [ta, ax, ay, aw, ah] = rects[i]; const [tb, bx, by, bw, bh] = rects[j];
    if (ta.startsWith('card:') && tb.startsWith('card:')) continue;
    const overlap = ax < bx + bw - 1 && bx < ax + aw - 1 && ay < by + bh - 1 && by < ay + ah - 1;
    expect(!overlap, `${label}: "${ta}" and "${tb}" do not overlap`);
  }
  await shot(page, name, w, h);
}

for (const [w, h] of SIZES) {
  const context = await browser.newContext({ viewport: { width: w, height: h } });
  const page = await context.newPage();
  await page.goto('https://localhost:8446/');
  await page.waitForFunction(() => window.railsBridge?.godotFlow === 'select', null, { timeout: 60000 });
  await page.waitForTimeout(1500);
  await check(page, 'select', w, h);
  // The first tap highlights a hero and the second confirms. The camera circles, so each tap reads the pill position again.
  const tapCard = async () => {
    const card = (await page.evaluate(() => window.railsBridge.godotUiRects)).find((r) => r[0].startsWith('card:'));
    await page.mouse.click(card[1] + card[3] / 2, card[2] + card[4] / 2);
  };
  await tapCard();
  await page.waitForTimeout(600);
  await tapCard();
  await page.waitForFunction(() => window.railsBridge.godotFlow === 'play', null, { timeout: 8000 });
  await page.waitForTimeout(3000);
  await check(page, 'play', w, h);
  // Rotating mid-run must keep the run.
  const before = await page.evaluate(() => window.railsBridge.godotDistance);
  await page.setViewportSize({ width: h, height: w });
  await page.waitForTimeout(1500);
  const after = await page.evaluate(() => ({ flow: window.railsBridge.godotFlow, dist: window.railsBridge.godotDistance }));
  expect(after.flow === 'play' && after.dist > before, `rotation ${w}x${h} to ${h}x${w} keeps the run (${before.toFixed(0)} to ${after.dist.toFixed(0)})`);
  await check(page, 'play-rotated', h, w);
  await context.close();
}
await browser.close();
process.exit(fail.length ? 1 : 0);
