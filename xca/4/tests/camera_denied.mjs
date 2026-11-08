// Usage: node tests/camera_denied.mjs. A rejected getUserMedia (as in the GamePix iframe) shows a message, and two taps on a hero still start a run.
import { chromium } from 'playwright-core';
import { heroPoint, buttonPoint, waitForStartScreen } from './start.mjs';
const args = ['--ignore-certificate-errors', '--enable-unsafe-swiftshader', '--use-gl=angle', '--use-angle=swiftshader'];
const browser = await chromium.launch({ executablePath: '/usr/bin/google-chrome', headless: true, args });
let failed = 0;
const check = (ok, msg) => { console.log(ok ? 'PASS' : 'FAIL', msg); if (!ok) failed++; };
for (const [width, height] of [[1280, 720], [390, 844]]) {
  const page = await (await browser.newContext({ viewport: { width, height } })).newPage();
  await page.addInitScript(() => {
    const reject = () => Promise.reject(new DOMException('Permission denied', 'NotAllowedError'));
    if (!navigator.mediaDevices) Object.defineProperty(navigator, 'mediaDevices', { value: {} });
    navigator.mediaDevices.getUserMedia = reject;
  });
  await page.goto('https://localhost:8446/');
  await waitForStartScreen(page);
  await page.waitForTimeout(1500);
  await page.mouse.click(...(await buttonPoint(page, 'Hands')));
  await page.waitForFunction(() => (window.railsBridge.camError || '') !== '', null, { timeout: 20000 }).catch(() => {});
  await page.waitForTimeout(2500);
  check((await page.evaluate(() => window.railsBridge.camError || '')) !== '', `${width}x${height}: the page reports a camera error`);
  await page.screenshot({ path: `/tmp/camera-denied-${width}x${height}.png` });
  check(await page.evaluate(() => (window.railsBridge.godotUiRects || []).some((r) => r[0] === 'CameraNotice')), `${width}x${height}: the notice shows on the first screen`);
  check(await page.evaluate(() => window.railsBridge.godotFlow) === 'select', `${width}x${height}: still on the campfire`);
  await page.mouse.click(...(await heroPoint(page, 'sam')));
  await page.waitForTimeout(600);
  await page.mouse.click(...(await heroPoint(page, 'sam')));
  await page.waitForFunction(() => window.railsBridge.godotFlow === 'play', null, { timeout: 20000 }).catch(() => {});
  check(await page.evaluate(() => window.railsBridge.godotFlow) === 'play', `${width}x${height}: two taps on a hero start the run`);
  await page.context().close();
}
await browser.close();
process.exit(failed ? 1 : 0);
