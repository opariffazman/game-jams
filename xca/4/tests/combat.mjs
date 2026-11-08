import { chromium } from 'playwright-core';
import { startByTouch } from './start.mjs';
// Usage: node tests/combat.mjs. Runs 40 s with no steering input and checks that auto-fire hits zombies and the chain counts.
const args = ['--ignore-certificate-errors', '--enable-unsafe-swiftshader', '--use-gl=angle', '--use-angle=swiftshader'];
const browser = await chromium.launch({ executablePath: '/usr/bin/google-chrome', headless: true, args });
const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
const errors = [];
page.on('pageerror', (e) => errors.push(String(e)));
page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
await page.goto('https://localhost:8446/');
await startByTouch(page, 0);
let maxCombo = 0;
for (let i = 0; i < 160; i++) {
  await page.waitForTimeout(250);
  maxCombo = Math.max(maxCombo, await page.evaluate(() => window.railsBridge.godotCombo));
}
const r = await page.evaluate(() => ({ shots: window.railsBridge.godotShots, hits: window.railsBridge.godotHits, hearts: window.railsBridge.godotHearts, fps: window.railsBridge.godotFps }));
await page.screenshot({ path: 'tests/combat.png' });
console.log(JSON.stringify({ ...r, maxCombo, errors: errors.slice(0, 3) }));
const ok = r.shots > 0 && r.hits > 0 && maxCombo >= 2 && errors.length === 0;
console.log(ok ? 'PASS auto-fire hits zombies, chain reaches 2, no page errors' : 'FAIL');
await browser.close();
process.exit(ok ? 0 : 1);
