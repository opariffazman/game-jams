import { chromium } from 'playwright-core';
import { startByTouch } from './start.mjs';
// Usage: node tests/fog_shots.mjs. Screenshots the run start and later moments to check fog and zombie emergence.
const args = ['--ignore-certificate-errors', '--enable-unsafe-swiftshader', '--use-gl=angle', '--use-angle=swiftshader'];
const browser = await chromium.launch({ executablePath: '/usr/bin/google-chrome', headless: true, args });
const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
await page.goto('https://localhost:8446/?quality=high');
await startByTouch(page, 0);
for (const [i, ms] of [[0, 300], [1, 3000], [2, 1500], [3, 1500]]) {
  await page.waitForTimeout(ms);
  await page.screenshot({ path: `tests/fog-${i}.png` });
}
await browser.close();
