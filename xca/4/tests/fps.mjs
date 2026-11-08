import { chromium } from 'playwright-core';
import { startByTouch } from './start.mjs';
const clip = process.argv[2] ?? '/tmp/person/portrait.y4m';
const label = process.argv[3] ?? 'run';
const args = ['--use-fake-ui-for-media-stream', '--use-fake-device-for-media-stream',
  `--use-file-for-fake-video-capture=${clip}`,
  '--ignore-certificate-errors', '--enable-unsafe-swiftshader', '--use-gl=angle', '--use-angle=swiftshader'];
const browser = await chromium.launch({ executablePath: '/usr/bin/google-chrome', headless: true, args });
const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
const errors = [];
page.on('pageerror', (e) => errors.push('pageerror: ' + e.message));
page.on('console', (m) => { if (m.type() === 'error' && !/odml|XNNPACK|Content Security/.test(m.text())) errors.push('console: ' + m.text().slice(0, 200)); });
await page.goto('https://localhost:8446/');
await page.waitForTimeout(15000);
await startByTouch(page);
await page.waitForTimeout(3000);
const sample = async (ms) => {
  const a = await page.evaluate(() => performance.now());
  const frames0 = await page.evaluate(() => window.railsBridge?.godotFrames ?? 0);
  const fps = [];
  const end = Date.now() + ms;
  while (Date.now() < end) { await page.waitForTimeout(500); fps.push(await page.evaluate(() => window.railsBridge.godotFps)); }
  return fps.reduce((x, y) => x + y, 0) / fps.length;
};
const off = await sample(8000);
await page.click('#startCam');
await page.waitForFunction(() => document.getElementById('startCam').textContent === 'Camera on' || document.getElementById('err').style.display === 'block', null, { timeout: 90000 });
await page.waitForTimeout(6000);
const on = await sample(10000);
const state = await page.evaluate(() => ({ bridge: { ...window.railsBridge }, hud: document.getElementById('hud').textContent, err: document.getElementById('err').textContent }));
console.log(`${label}: godot fps tracking-off ${off.toFixed(1)} on ${on.toFixed(1)} ratio ${(on / off).toFixed(2)}`);
console.log(state.hud);
console.log('err box:', state.err || 'none', '| errors', errors.length ? errors : 'none');
console.log('bridge', JSON.stringify(state.bridge));
await browser.close();
