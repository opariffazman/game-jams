import { chromium } from 'playwright-core';
import { startByTouch } from './start.mjs';
// Usage: node tests/pickups.mjs. Runs a few minutes with no steering. Checks pickups spawn, nothing errors and the run never stalls.
const args = ['--ignore-certificate-errors', '--enable-unsafe-swiftshader', '--use-gl=angle', '--use-angle=swiftshader'];
const browser = await chromium.launch({ executablePath: '/usr/bin/google-chrome', headless: true, args });
const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
const errors = [];
page.on('pageerror', (e) => errors.push(String(e)));
page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
await page.goto('https://localhost:8446/');
await startByTouch(page, 0);
let sawItems = 0;
let last = '';
for (let i = 0; i < 240; i++) {
  await page.waitForTimeout(250);
  last = await page.evaluate(() => window.railsBridge.godotPickups || '');
  const [items] = last.split(',').map(Number);
  sawItems = Math.max(sawItems, items || 0);
  if (i % 4 === 0) await page.keyboard.press(['ArrowLeft', 'ArrowRight'][(i >> 2) % 2]);
}
await page.screenshot({ path: 'tests/pickups.png' });
const [items, ammo, health, hearts] = last.split(',').map(Number);
console.log(JSON.stringify({ last, sawItems, errors: errors.slice(0, 3) }));
const ok = sawItems > 0 && ammo + health > 0 && hearts <= 6 && errors.length === 0;
console.log(ok ? 'PASS pickups spawn and are collected, no page errors' : 'FAIL');
await browser.close();
process.exit(ok ? 0 : 1);
