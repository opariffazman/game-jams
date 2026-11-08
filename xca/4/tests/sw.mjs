// Usage: node tests/sw.mjs. First load registers the service worker, second load serves index.wasm from it, and the game starts.
import { chromium } from 'playwright-core';
import { startByTouch } from './start.mjs';
const args = ['--ignore-certificate-errors', '--enable-unsafe-swiftshader', '--use-gl=angle', '--use-angle=swiftshader'];
const browser = await chromium.launch({ executablePath: '/usr/bin/google-chrome', headless: true, args });
const context = await browser.newContext({ viewport: { width: 1280, height: 720 }, ignoreHTTPSErrors: true });
let failed = 0;
const check = (name, ok, detail = '') => { console.log(`${ok ? 'PASS' : 'FAIL'} ${name} ${detail}`); if (!ok) failed++; };
const URL_ = 'https://localhost:8446/';

const first = await context.newPage();
await first.goto(URL_);
const scope = await first.evaluate(async () => (await navigator.serviceWorker.ready).scope);
check('worker registers', scope === URL_, scope);
await first.waitForFunction(async () => {
  const names = await caches.keys();
  const name = names.find((n) => n.startsWith('rails-'));
  return !!name && !!(await (await caches.open(name)).match('index.wasm'));
}, null, { timeout: 120000 });
check('index.wasm precached', true);
await first.close();

const page = await context.newPage();
const errors = [];
page.on('pageerror', (e) => errors.push(String(e)));
let wasmFromWorker = null;
page.on('response', (r) => { if (r.url().endsWith('/index.wasm')) wasmFromWorker = r.fromServiceWorker(); });
await page.goto(URL_);
await page.waitForFunction(() => navigator.serviceWorker.controller, null, { timeout: 30000 });
check('second load is controlled', true);
await startByTouch(page);
check('game starts', true);
check('index.wasm from service worker', wasmFromWorker === true, String(wasmFromWorker));
check('no page errors', errors.length === 0, errors.join(' | '));
await browser.close();
process.exit(failed ? 1 : 0);
