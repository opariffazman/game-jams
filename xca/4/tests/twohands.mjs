import { chromium } from 'playwright-core';
// Usage: node tests/twohands.mjs <clip.y4m> [secondsPerPhase]. Measures tracker fps with one hand, then with two hands, and logs th and sr.
const clip = process.argv[2];
const seconds = Number(process.argv[3] ?? 8);
const args = ['--use-fake-ui-for-media-stream', '--use-fake-device-for-media-stream', `--use-file-for-fake-video-capture=${clip}`,
  '--ignore-certificate-errors', '--enable-unsafe-swiftshader', '--use-gl=angle', '--use-angle=swiftshader'];
const browser = await chromium.launch({ executablePath: '/usr/bin/google-chrome', headless: true, args });
const page = await browser.newPage({ viewport: { width: Number(process.env.VW ?? 320), height: Number(process.env.VH ?? 180) } });
const errors = [];
page.on('pageerror', (e) => errors.push('pageerror: ' + e.message));
await page.goto('https://localhost:8446/');
await page.waitForFunction(() => window.railsBridge?.godotFlow === 'select', null, { timeout: 60000 });
await page.evaluate(() => { window.railsBridge.setMagic(true); });
await page.waitForFunction(() => document.getElementById('startCam').textContent === 'Camera on', null, { timeout: 90000 });
await page.waitForTimeout(3000);
const phase = async (two) => {
  await page.evaluate((on) => window.railsBridge.setTwoHands(on), two);
  await page.waitForTimeout(1500);
  await page.evaluate(() => {
    const b = window.railsBridge; window.__s = { frames: 0, hands2: 0, th: null, sr0: JSON.parse(b.packed).sr ?? 0, n: [] }; let last = b.seq;
    window.__iv = setInterval(() => { if (b.seq === last) return; last = b.seq; const d = JSON.parse(b.packed); window.__s.frames++; window.__s.n.push(d.n); if (d.th) { window.__s.hands2++; window.__s.th = d.th; } window.__s.sr = d.sr; }, 10);
  });
  await page.waitForTimeout(seconds * 1000);
  const s = await page.evaluate(() => { clearInterval(window.__iv); return window.__s; });
  return { two, fps: +(s.frames / seconds).toFixed(1), framesWithTh: s.hands2, lastTh: s.th, srDelta: (s.sr ?? 0) - s.sr0, maxHands: Math.max(...s.n) };
};
const one = await phase(false);
const two = await phase(true);
console.log(JSON.stringify({ clip, one, two, errors }));
await browser.close();
