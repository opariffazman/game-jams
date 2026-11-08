import { chromium } from 'playwright-core';
// Usage: node tests/repro.mjs <clip.y4m>. Plays with magic hands on a real hand clip and logs the tracker output and a screenshot.
const clip = process.argv[2];
const args = ['--use-fake-ui-for-media-stream', '--use-fake-device-for-media-stream', `--use-file-for-fake-video-capture=${clip}`,
  '--ignore-certificate-errors', '--enable-unsafe-swiftshader', '--use-gl=angle', '--use-angle=swiftshader'];
const browser = await chromium.launch({ executablePath: '/usr/bin/google-chrome', headless: true, args });
const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
await page.goto('https://localhost:8446/');
await page.waitForFunction(() => window.railsBridge?.godotFlow === 'select', null, { timeout: 60000 });
await page.waitForTimeout(1500);
await page.waitForTimeout(1500);
await page.mouse.click(170, 460);
await page.waitForTimeout(3500);
await page.evaluate(() => { window.railsBridge.setMagic(true); });
await page.waitForFunction(() => document.getElementById('startCam').textContent === 'Camera on', null, { timeout: 90000 });
await page.waitForTimeout(8000);
const samples = [];
for (let i = 0; i < 24; i++) {
  await page.waitForTimeout(500);
  samples.push(await page.evaluate(() => { const d = JSON.parse(window.railsBridge.packed || '{}'); return { n: d.n, s0: d.s?.[0], vis: window.railsBridge.visibleHands, ax: +window.railsBridge.godotAimX.toFixed(3), ay: +window.railsBridge.godotAimY.toFixed(3) }; }));
}
console.log(JSON.stringify(samples.map((s) => [s.n, s.vis, s.s0 && s.s0[0], s.s0 && s.s0[1], s.ax, s.ay].join(","))));
await page.screenshot({ path: 'tests/repro.png' });
await browser.close();
