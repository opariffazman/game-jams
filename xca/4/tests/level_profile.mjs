import { chromium } from 'playwright-core';
import { startByTouch } from './start.mjs';
// Usage: node tests/level_profile.mjs. Hides one scene group at a time and prints the draw calls it removes.
const GROUPS = ['Chunks', 'Backdrop', 'ZombiePool', 'Hero', 'Confetti', 'Juice', 'Hud', 'Fog', 'Pool'];
const args = ['--ignore-certificate-errors', '--enable-unsafe-swiftshader', '--use-gl=angle', '--use-angle=swiftshader'];
const browser = await chromium.launch({ executablePath: '/usr/bin/google-chrome', headless: true, args });
const context = await browser.newContext({ viewport: { width: 1280, height: 720 }, hasTouch: true });
const page = await context.newPage();
await page.goto('https://localhost:8446/');
await startByTouch(page, 0);
await page.waitForTimeout(3000);
const fps = () => page.evaluate(() => new Promise((resolve) => { let n = 0; const t = performance.now(); const tick = () => { n++; if (performance.now() - t > 4000) resolve(n / 4); else requestAnimationFrame(tick); }; requestAnimationFrame(tick); }));
const read = async () => ({ ...(await page.evaluate(() => ({ d: window.railsBridge.levelDraws, t: window.railsBridge.levelTris }))), f: await fps() });
const set = async (off) => { await page.evaluate((o) => { window.railsBridge.levelOff = o; }, off); await page.waitForTimeout(1500); };
const base = await read();
console.log(`all on: ${base.d} draws, ${base.t} tris, ${base.f.toFixed(1)} fps`);
for (const g of GROUPS) {
  await set(g);
  const r = await read();
  console.log(`hide ${g}: ${r.d} draws (${base.d - r.d} saved), ${r.t} tris, ${r.f.toFixed(1)} fps`);
}
await set('');
await browser.close();
