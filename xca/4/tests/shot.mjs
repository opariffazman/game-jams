import { chromium } from 'playwright-core';
import { startByTouch } from './start.mjs';
const args = ['--use-fake-ui-for-media-stream', '--use-fake-device-for-media-stream',
  '--use-file-for-fake-video-capture=/tmp/person/portrait.y4m',
  '--ignore-certificate-errors', '--enable-unsafe-swiftshader', '--use-gl=angle', '--use-angle=swiftshader'];
const browser = await chromium.launch({ executablePath: '/usr/bin/google-chrome', headless: true, args });
const page = await browser.newPage({ viewport: { width: 1280, height: 800 } });
await page.goto('https://localhost:8446/');
await page.waitForTimeout(8000);
await startByTouch(page);
await page.evaluate(() => document.getElementById('startCam').click());
await page.waitForTimeout(12000);
await page.screenshot({ path: process.argv[2] ?? '/tmp/combined_shot.png' });
await browser.close();
