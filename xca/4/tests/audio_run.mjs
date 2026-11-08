import { chromium } from 'playwright-core';
// Spies on AudioContext to report its state and output level after the first tap on the start screen.
const args = ['--ignore-certificate-errors', '--enable-unsafe-swiftshader', '--use-gl=angle', '--use-angle=swiftshader', '--autoplay-policy=document-user-activation-required'];
const browser = await chromium.launch({ executablePath: '/usr/bin/google-chrome', headless: true, args });
const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
const logs = [];
page.on('console', (m) => logs.push(m.type() + ': ' + m.text()));
page.on('pageerror', (e) => logs.push('pageerror: ' + e.message));
await page.addInitScript(() => {
  window.__ctxs = [];
  const Orig = window.AudioContext;
  window.AudioContext = function (...a) {
    const c = new Orig(...a);
    const an = c.createAnalyser();
    const origDest = c.destination;
    window.__ctxs.push({ c, an });
    const origConnect = AudioNode.prototype.connect;
    return c;
  };
  window.AudioContext.prototype = Orig.prototype;
  const oc = AudioNode.prototype.connect;
  AudioNode.prototype.connect = function (dest, ...r) {
    if (dest && dest instanceof AudioDestinationNode) {
      const rec = window.__ctxs.find((x) => x.c === dest.context);
      if (rec) oc.call(this, rec.an);
    }
    return oc.call(this, dest, ...r);
  };
});
await page.addInitScript(() => {
  window.__stat = { destConnects: 0, sourcesStarted: 0, workletNodes: 0 };
  const oc2 = AudioNode.prototype.connect;
  AudioNode.prototype.connect = function (d, ...r) { if (d instanceof AudioDestinationNode) window.__stat.destConnects++; return oc2.call(this, d, ...r); };
  const os = AudioBufferSourceNode.prototype.start;
  AudioBufferSourceNode.prototype.start = function (...a) { window.__stat.sourcesStarted++; return os.apply(this, a); };
  const W = window.AudioWorkletNode;
  if (W) window.AudioWorkletNode = class extends W { constructor(...a) { super(...a); window.__stat.workletNodes++; } };
});
await page.goto('https://localhost:8446/');
await page.waitForFunction(() => window.railsBridge && window.railsBridge.godotFlow === 'select', null, { timeout: 60000 });
await page.waitForTimeout(1500);
const snap = () => page.evaluate(() => window.__ctxs.map(({ c, an }) => {
  const d = new Float32Array(an.fftSize); an.getFloatTimeDomainData(d);
  let peak = 0; for (const v of d) peak = Math.max(peak, Math.abs(v));
  return { state: c.state, peak: +peak.toFixed(4) };
}));
const flow = () => page.evaluate(() => window.railsBridge.godotFlow);
await page.waitForTimeout(1500);
for (let i = 0; i < 3; i++) { console.log('select', await flow(), JSON.stringify(await snap())); await page.waitForTimeout(700); }
await page.evaluate(() => { window.__pk = 0; setInterval(() => { for (const { an } of window.__ctxs) { const d = new Float32Array(an.fftSize); an.getFloatTimeDomainData(d); for (const v of d) window.__pk = Math.max(window.__pk, Math.abs(v)); } }, 20); });
await page.mouse.click(170, 460);
await page.waitForTimeout(3500);
for (let i = 0; i < 8; i++) { await page.evaluate(() => { window.__pk = 0; }); await page.waitForTimeout(1000);
  console.log('run', await flow(), 'peak1s', await page.evaluate(() => +window.__pk.toFixed(3)), await page.evaluate(() => window.railsBridge.godotAudioLayers)); await page.waitForTimeout(700); }
console.log(logs.filter((l) => /audio|sound|warn|error|ogg|missing/i.test(l)).slice(0, 20).join('\n') || 'no audio logs');
await browser.close();
