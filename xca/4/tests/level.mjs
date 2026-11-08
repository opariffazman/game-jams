import { chromium } from 'playwright-core';
import { startByTouch } from './start.mjs';
// Usage: node tests/level.mjs. Runs the street for 60 s at two sizes, jumps to each chunk type, and reports render cost and fps.
const SIZES = [[1280, 720, 'landscape'], [390, 844, 'portrait']];
// The high tier is for a discrete GPU, so its fps is not judged on the software renderer this test runs on.
const TIERS = { low: { draws: 110, tris: 60000, fps: 20 }, high: { draws: 80, tris: 110000, fps: 0 } };
const KINDS = ['street', 'crossroads', 'market', 'park', 'graveyard', 'gate', 'porch'];
// Chunk index that shows each kind first in the sequence (street 0, crossroads 2, market 3, park 5, gate 7, graveyard 8, porch 11).
const CHUNK_OF = { street: 0, crossroads: 2, market: 3, park: 5, graveyard: 8, gate: 7, porch: 11 };
const RUN_SECONDS = 60;
const args = ['--ignore-certificate-errors', '--enable-unsafe-swiftshader', '--use-gl=angle', '--use-angle=swiftshader'];
const browser = await chromium.launch({ executablePath: '/usr/bin/google-chrome', headless: true, args });
const errors = [];
let failed = 0;
const check = (name, ok, detail = '') => { console.log(`${ok ? 'PASS' : 'FAIL'} ${name} ${detail}`); if (!ok) failed++; };
const shot = (page, name) => page.screenshot({ path: new URL(`./level-${name}.png`, import.meta.url).pathname });

for (const [tier, BUDGET] of Object.entries(TIERS).filter(([t]) => !process.env.TIER || t === process.env.TIER)) for (const [width, height, size] of SIZES) {
  const label = `${tier} ${size}`;
  const context = await browser.newContext({ viewport: { width: 1280, height: 720 }, hasTouch: true });
  const page = await context.newPage();
  page.on('pageerror', (e) => errors.push('pageerror: ' + e.message));
  page.on('console', (m) => { if (m.type() === 'error' && !/odml|XNNPACK|Content Security/.test(m.text())) errors.push('console: ' + m.text().slice(0, 200)); });
  await page.goto(`https://localhost:8446/?quality=${tier}`);
  await startByTouch(page, 0);
  await page.setViewportSize({ width, height });
  await page.waitForTimeout(1500);
  const read = () => page.evaluate(() => ({ draws: window.railsBridge.levelDraws, tris: window.railsBridge.levelTris, street: window.railsBridge.levelStreetTris, chunk: window.railsBridge.levelChunk, kind: window.railsBridge.levelKind, dist: window.railsBridge.godotDistance, flow: window.railsBridge.godotFlow }));

  // Each chunk type is shown by jumping the drawn street, so the run itself keeps playing.
  for (const kind of KINDS) {
    await page.evaluate((chunk) => { window.railsBridge.levelJump = chunk; }, CHUNK_OF[kind]);
    await page.waitForTimeout(1200);
    const s = await read();
    check(`${label} ${kind} chunk is drawn`, s.chunk === CHUNK_OF[kind] || s.chunk === CHUNK_OF[kind] + 1, `chunk ${s.chunk} kind ${s.kind}`);
    await shot(page, `${kind}-${label}`);
  }

  // Baseline: the same scene with the street hidden, so the street's own cost is the difference.
  await page.evaluate(() => { window.railsBridge.levelHide = true; });
  await page.waitForTimeout(1500);
  const bare = await read();
  const frames = () => page.evaluate(() => new Promise((resolve) => { let n = 0; const t = performance.now(); const tick = () => { n++; if (performance.now() - t > 4000) resolve(n / 4); else requestAnimationFrame(tick); }; requestAnimationFrame(tick); }));
  const bareFps = await frames();
  await page.evaluate(() => { window.railsBridge.levelHide = false; });
  await page.waitForTimeout(1500);
  const full = await read();
  const fullFps = await frames();
  console.log(`${label}: fps with street hidden ${bareFps.toFixed(1)}, with street ${fullFps.toFixed(1)}`);
  console.log(`${label}: street costs ${full.draws - bare.draws} draw calls and ${full.tris - bare.tris} triangles (rest of game ${bare.draws} draws, ${bare.tris} triangles)`);

  // Steady run for 60 s. The real distance carries the street through every chunk without a jump.
  await page.evaluate(() => { window.railsBridge.levelJump = 0; });
  await page.waitForTimeout(600);
  const fpsSamples = [];
  let worstDraws = 0;
  let worstTris = 0;
  let worstStreet = 0;
  const kindsSeen = new Set();
  let lastChunk = (await read()).chunk;
  let chunkSteps = 0;
  const t0 = Date.now();
  while (Date.now() - t0 < RUN_SECONDS * 1000) {
    const a = await page.evaluate(() => performance.now());
    await page.evaluate(() => new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r))));
    const b = await page.evaluate(() => performance.now());
    fpsSamples.push(2000 / (b - a));
    const s = await read();
    worstDraws = Math.max(worstDraws, s.draws ?? 0);
    worstTris = Math.max(worstTris, s.tris ?? 0);
    worstStreet = Math.max(worstStreet, s.street ?? 0);
    kindsSeen.add(s.kind);
    if (s.chunk !== lastChunk) { chunkSteps++; lastChunk = s.chunk; }
    if (s.flow !== 'play') break;
    await page.waitForTimeout(250);
  }
  fpsSamples.sort((x, y) => x - y);
  const median = fpsSamples[Math.floor(fpsSamples.length / 2)];
  const low = fpsSamples[Math.floor(fpsSamples.length * 0.05)];
  console.log(`${label}: median fps ${median.toFixed(1)}, p5 fps ${low.toFixed(1)}, worst draws ${worstDraws}, worst triangles ${worstTris}, street triangles ${worstStreet}, chunks passed ${chunkSteps}`);
  if (BUDGET.fps > 0) check(`${label} fps over ${BUDGET.fps}`, median > BUDGET.fps, `median ${median.toFixed(1)}`);
  check(`${label} draw calls within ${BUDGET.draws}`, worstDraws > 0 && worstDraws <= BUDGET.draws, `${worstDraws}`);
  check(`${label} triangles within ${BUDGET.tris}`, worstTris > 0 && worstTris <= BUDGET.tris, `${worstTris}`);
  await shot(page, `run-${label}`);
  await context.close();
}
console.log('errors', errors.length ? errors : 'none');
check('no page errors', errors.length === 0);
await browser.close();
process.exit(failed ? 1 : 0);
