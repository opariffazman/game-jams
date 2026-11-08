import { chromium } from 'playwright-core';
import { startByTouch } from './start.mjs';
const args = ['--use-fake-ui-for-media-stream', '--use-fake-device-for-media-stream',
  '--use-file-for-fake-video-capture=/tmp/person/portrait.y4m',
  '--ignore-certificate-errors', '--enable-unsafe-swiftshader', '--use-gl=angle', '--use-angle=swiftshader'];
const browser = await chromium.launch({ executablePath: '/usr/bin/google-chrome', headless: true, args });
const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
const errors = [];
page.on('pageerror', (e) => errors.push('pageerror: ' + e.message));
page.on('console', (m) => { if (m.type() === 'error' && !/odml|XNNPACK|Content Security/.test(m.text())) errors.push('console: ' + m.text().slice(0, 200)); });
const external = new Set();
page.on('request', (r) => { const u = new URL(r.url()); if (u.hostname !== 'localhost') external.add(u.host); });
await page.goto('https://localhost:8446/');
await page.waitForTimeout(15000);
await startByTouch(page);
await page.evaluate(() => window.railsBridge.setMagic(true));
await page.waitForFunction(() => document.getElementById('startCam').textContent === 'Camera on' || document.getElementById('err').style.display === 'block', null, { timeout: 90000 });
await page.waitForTimeout(12000);
await page.screenshot({ path: new URL('./shot-moving.png', import.meta.url).pathname });
for (let i = 0; i < 8; i++) { await page.waitForTimeout(3500); await page.screenshot({ path: new URL(`./shot-${i}.png`, import.meta.url).pathname }); }
await page.mouse.move(640, 300);
await page.mouse.down();
await page.waitForTimeout(4000);
await page.mouse.up();
const read = () => page.evaluate(() => ({ bridge: { ...window.railsBridge }, hud: document.getElementById('hud').textContent, err: document.getElementById('err').textContent }));
const a = await read();
await page.waitForTimeout(5000);
const b = await read();
console.log(a.hud);
console.log('bridge', JSON.stringify(b.bridge));
console.log('seq advanced', b.bridge.seq - a.bridge.seq, 'godotSeenSeq', b.bridge.godotSeenSeq);
console.log('page err box:', b.err || 'none');
await page.screenshot({ path: new URL('./shot.png', import.meta.url).pathname });
const [dl] = await Promise.all([page.waitForEvent('download'), page.evaluate(() => document.getElementById('dlLog').click())]);
console.log('download', dl.suggestedFilename());
console.log('errors', errors.length ? errors : 'none');
console.log('external hosts', [...external]);
await browser.close();
