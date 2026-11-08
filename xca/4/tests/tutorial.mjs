// Usage: node tests/tutorial.mjs. Checks the cleaning guide in the viewer and its persistence, and saves screenshots at three sizes.
import { chromium } from 'playwright-core';
import { startByTouch } from './start.mjs';
const args = ['--ignore-certificate-errors', '--enable-unsafe-swiftshader', '--use-gl=angle', '--use-angle=swiftshader'];
const browser = await chromium.launch({ executablePath: '/usr/bin/google-chrome', headless: true, args });
let failed = 0;
const check = (name, ok, detail = '') => { console.log(`${ok ? 'PASS' : 'FAIL'} ${name} ${detail}`); if (!ok) failed++; };
const shot = (name) => new URL(`./${name}.png`, import.meta.url).pathname;
const sizes = [[1280, 720], [844, 390], [390, 844]];
for (const [width, height] of sizes) {
  const context = await browser.newContext({ viewport: { width: 1280, height: 720 }, hasTouch: true });
  const page = await context.newPage();
  const errors = [];
  page.on('pageerror', (e) => errors.push(e.message));
  await page.goto('https://localhost:8446/');
  await startByTouch(page, 0);
  await page.setViewportSize({ width, height });
  await page.waitForTimeout(1500);
  await page.keyboard.press('i');
  await page.waitForTimeout(1500);
  check(`viewer open at ${width}x${height}`, (await page.evaluate(() => window.railsBridge.godotInspect)) === 1);
  await page.screenshot({ path: shot(`tutorial-viewer-${width}x${height}`) });
  check('guide not yet learned', (await page.evaluate(() => localStorage.getItem('railsCleanLearned'))) === null);
  if (width === 1280) {
    await page.mouse.move(640, 360);
    await page.keyboard.down('Space');
    await page.waitForTimeout(9000);
    await page.keyboard.up('Space');
    check('rubbing marks the guide learned', (await page.evaluate(() => localStorage.getItem('railsCleanLearned'))) === '1');
  }
  check('no page errors', errors.length === 0, errors.join('|'));
  await context.close();
}
await browser.close();
process.exit(failed ? 1 : 0);
