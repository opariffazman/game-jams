import { chromium } from 'playwright-core';
// Usage: node tests/hologram_play.mjs <clip.y4m>. Plays a run with the camera on, waits for a flick, and screenshots the whole page at two shapes.
const clip = process.argv[2];
const args = ['--use-fake-ui-for-media-stream', '--use-fake-device-for-media-stream', `--use-file-for-fake-video-capture=${clip}`,
  '--ignore-certificate-errors', '--enable-unsafe-swiftshader', '--use-gl=angle', '--use-angle=swiftshader'];
const browser = await chromium.launch({ executablePath: '/usr/bin/google-chrome', headless: true, args });
let failed = 0;
const check = (name, ok, detail = '') => { console.log(`${ok ? 'PASS' : 'FAIL'} ${name} ${detail}`); if (!ok) failed++; };
for (const [w, h, tag] of [[1280, 720, 'landscape'], [540, 960, 'portrait']]) {
  const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
  await page.goto('https://localhost:8446/');
  await page.waitForFunction(() => window.railsBridge?.godotFlow === 'select', null, { timeout: 90000 });
  await page.waitForTimeout(1000);
    await page.waitForFunction(() => window.railsBridge.godotFlow === 'select', null, { timeout: 15000 });
  await page.waitForTimeout(500);
  await page.mouse.click(170, 460);
  await page.waitForFunction(() => window.railsBridge.godotFlow === 'play', null, { timeout: 15000 });
  await page.evaluate(() => { window.railsBridge.setMagic(true); });
  await page.waitForFunction(() => document.getElementById('startCam').textContent === 'Camera on', null, { timeout: 90000 });
  await page.setViewportSize({ width: w, height: h });
  await page.waitForFunction(() => window.railsBridge.gestureCount > 0, null, { timeout: 60000, polling: 20 }).catch(() => {});
  await page.waitForTimeout(200);
  await page.screenshot({ path: new URL(`./hologram-play-${tag}.png`, import.meta.url).pathname });
  const info = await page.evaluate(() => {
    const r = document.getElementById('holo').getBoundingClientRect();
    const m = window.railsBridge;
    return { holo: [r.left, r.top, r.width, r.height].map(Math.round), flow: m.godotFlow, gestures: m.gestureCount, visible: getComputedStyle(document.getElementById('holo')).display };
  });
  console.log(tag, JSON.stringify(info));
  check(`${tag}: the hologram is a small corner preview`, info.holo[2] <= 160 && info.holo[3] <= 120, JSON.stringify(info.holo));
  check(`${tag}: the run continues`, info.flow === 'play');
  await page.close();
}
await browser.close();
process.exit(failed ? 1 : 0);
