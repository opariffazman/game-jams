import { chromium } from 'playwright-core';
// Usage: node tests/hologram.mjs <clip.y4m>. Screenshots the hologram after a flick, then checks the toggle and that the canvas ignores clicks.
const clip = process.argv[2];
const args = ['--use-fake-ui-for-media-stream', '--use-fake-device-for-media-stream', `--use-file-for-fake-video-capture=${clip}`,
  '--ignore-certificate-errors', '--enable-unsafe-swiftshader', '--use-gl=angle', '--use-angle=swiftshader'];
const browser = await chromium.launch({ executablePath: '/usr/bin/google-chrome', headless: true, args });
const page = await browser.newPage({ viewport: { width: 640, height: 360 } });
await page.goto('https://localhost:8446/');
await page.waitForFunction(() => window.railsBridge?.godotFlow === 'select', null, { timeout: 60000 });
await page.evaluate(() => { window.railsBridge.setMagic(true); });
await page.waitForFunction(() => document.getElementById('startCam').textContent === 'Camera on', null, { timeout: 90000 });
await page.waitForFunction(() => window.railsBridge.gestureCount > 0, null, { timeout: 40000, polling: 20 });
await page.waitForTimeout(150);
const box = { x: 640 - 150, y: 0, width: 150, height: 115 };
await page.screenshot({ path: 'tests/hologram_on.png', clip: box });
const pe = await page.evaluate(() => getComputedStyle(document.getElementById('holo')).pointerEvents);
await page.evaluate(() => window.railsBridge.setHologram(false));
const display = await page.evaluate(() => getComputedStyle(document.getElementById('holo')).display);
await page.screenshot({ path: 'tests/hologram_off.png', clip: box });
console.log(JSON.stringify({ pointerEvents: pe, displayAfterOff: display }));
await browser.close();
