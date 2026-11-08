import { chromium } from 'playwright-core';
import { startByTouch } from './start.mjs';
// Usage: node tests/fire.mjs <clip.y4m> <label>. Feeds a still hand image as the camera and reads the readouts.
const clip = process.argv[2];
const label = process.argv[3] ?? 'run';
const args = ['--use-fake-ui-for-media-stream', '--use-fake-device-for-media-stream',
  `--use-file-for-fake-video-capture=${clip}`,
  '--ignore-certificate-errors', '--enable-unsafe-swiftshader', '--use-gl=angle', '--use-angle=swiftshader'];
const browser = await chromium.launch({ executablePath: '/usr/bin/google-chrome', headless: true, args });
const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
const errors = [];
page.on('pageerror', (e) => errors.push('pageerror: ' + e.message));
await page.goto('https://localhost:8446/');
await page.waitForTimeout(15000);
await startByTouch(page);
await page.waitForTimeout(2000);
await page.evaluate(() => window.railsBridge.setMagic(true));
await page.waitForFunction(() => document.getElementById('startCam').textContent === 'Camera on' || document.getElementById('err').style.display === 'block', null, { timeout: 90000 });
await page.waitForTimeout(12000);
const state = await page.evaluate(() => ({ b: { ...window.railsBridge }, hud: document.getElementById('hud').textContent, err: document.getElementById('err').textContent }));
console.log(`${label}: gesture ${state.b.gesture} score ${state.b.score.toFixed(2)} action ${state.b.action} fistRatio ${state.b.fistRatio.toFixed(2)} palmRatio ${state.b.palmRatio.toFixed(2)} hands ${state.b.handCount} godotShots ${state.b.godotShots} godotFps ${state.b.godotFps.toFixed(1)}`);
console.log(state.hud);
console.log('err box:', state.err || 'none', '| errors', errors.length ? errors : 'none');
await browser.close();
