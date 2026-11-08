// Usage: node store/shoot.mjs. Captures gameplay frames at 1920x1080 into store/shots/ for the icon and cover.
import { createRequire } from 'node:module';
import { fileURLToPath, pathToFileURL } from 'node:url';
import path from 'node:path';

const here = path.dirname(fileURLToPath(import.meta.url));
const tests = path.join(here, '..', 'tests');
// playwright-core lives under the tests folder's resolution path, so resolve from there.
const { chromium } = createRequire(path.join(tests, 'x.js'))('playwright-core');
const { startByTouch, waitForStartScreen } = await import(pathToFileURL(path.join(tests, 'start.mjs')).href);

const args = ['--ignore-certificate-errors', '--enable-unsafe-swiftshader', '--use-gl=angle', '--use-angle=swiftshader'];
const browser = await chromium.launch({ executablePath: '/usr/bin/google-chrome', headless: true, args });
const page = await browser.newPage({ viewport: { width: 1280, height: 720 }, deviceScaleFactor: 1.5 });
page.on('pageerror', (e) => console.log('pageerror', e.message));
await page.goto('https://localhost:8446/?quality=high');
await waitForStartScreen(page);
await page.screenshot({ path: path.join(here, 'shots', 'start.png') });
await startByTouch(page, 0);
// Frames spread over the run: first zombies in fog, then the street filling up.
for (const [name, ms] of [['run-1', 4000], ['run-2', 5000], ['run-3', 5000], ['run-4', 5000], ['run-5', 3000], ['run-6', 3000], ['run-7', 3000], ['run-8', 3000], ['run-9', 3000], ['run-10', 3000]]) {
  await page.waitForTimeout(ms);
  await page.screenshot({ path: path.join(here, 'shots', `${name}.png`) });
}
await browser.close();
