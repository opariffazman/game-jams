import { chromium } from 'playwright-core';
import { heroPoint, buttonPoint } from './start.mjs';
// Usage: node tests/flow.mjs. Drives the intro as a player does, by tap and by scripted hand aim, and screenshots each screen and hero.
const args = ['--use-fake-ui-for-media-stream', '--use-fake-device-for-media-stream',
  '--ignore-certificate-errors', '--enable-unsafe-swiftshader', '--use-gl=angle', '--use-angle=swiftshader'];
const browser = await chromium.launch({ executablePath: '/usr/bin/google-chrome', headless: true, args });
const shot = (page, name) => page.screenshot({ path: new URL(`./flow-${name}.png`, import.meta.url).pathname });
const errors = [];
const fail = [];
const expect = (ok, msg) => { if (!ok) fail.push(msg); console.log(ok ? 'PASS' : 'FAIL', msg); };

async function open(extra = {}) {
  const context = await browser.newContext({ viewport: { width: 1280, height: 720 }, ...extra });
  const page = await context.newPage();
  page.on('pageerror', (e) => errors.push('pageerror: ' + e.message));
  page.on('console', (m) => { if (m.type() === 'error' && !/odml|XNNPACK|Content Security/.test(m.text())) errors.push('console: ' + m.text().slice(0, 200)); });
  await page.goto('https://localhost:8446/');
  await page.waitForFunction(() => window.railsBridge && window.railsBridge.godotSeenSeq !== undefined && window.railsBridge.godotFlow === 'select', null, { timeout: 60000 });
  await page.waitForTimeout(1500);
  return page;
}
const flow = (page) => page.evaluate(() => window.railsBridge.godotFlow);
const hero = (page) => page.evaluate(() => window.railsBridge.godotHero);
const state = (page) => page.evaluate(() => ({ flow: window.railsBridge.godotFlow, hero: window.railsBridge.godotHero, hearts: window.railsBridge.godotHearts, shots: window.railsBridge.godotShots, dist: window.railsBridge.godotDistance }));

// Touch path: the start screen never needs a camera, and a tap on a card picks it.
const heroes = ['lis', 'sam', 'shaun', 'matt'];
const LOADOUT = { lis: 'pistol', sam: 'smg', shaun: 'rifle', matt: 'shotgun' };
for (let i = 0; i < heroes.length; i++) {
  const page = await open();
  if (i === 0) await shot(page, '1-start');
  await page.waitForTimeout(1500);
  expect(await flow(page) === 'select', `the campfire is the first screen (${heroes[i]})`);
  if (i === 0) await shot(page, '3-select');
  const at = await heroPoint(page, heroes[i]);
  await page.mouse.move(...at);
  await page.waitForTimeout(1200);
  await page.mouse.move(...(await heroPoint(page, heroes[i])));
  await page.waitForFunction((id) => window.railsBridge.godotHero === id, heroes[i], { timeout: 3000 }).catch(() => {});
  expect(await hero(page) === heroes[i], `hover previews ${heroes[i]}`);
  await shot(page, `3-select-${heroes[i]}`);
  await page.mouse.click(...(await heroPoint(page, heroes[i])));
  await page.waitForTimeout(500);
  expect(await flow(page) === 'select' && await hero(page) === heroes[i], `first tap highlights ${heroes[i]} and waits`);
  // The camera sweeps and frames are slow on a loaded machine, so a tap can land on a pill that has moved. One retry on a re-read point matches what a player does.
  for (let attempt = 0; attempt < 2 && await flow(page) === 'select'; attempt++) {
    await page.mouse.click(...(await heroPoint(page, heroes[i])));
    await page.waitForTimeout(600);
  }
  expect(await flow(page) === 'picked' && await hero(page) === heroes[i], `second tap on card ${i} picks ${heroes[i]}`);
  await page.waitForFunction(() => window.railsBridge.godotFlow === 'play', null, { timeout: 10000 });
  // The bridge publishes on a timer, so the hearts value trails the flow change.
  await page.waitForFunction((n) => window.railsBridge.godotHearts === n, heroes[i] === 'matt' ? 6 : 5, { timeout: 5000 }).catch(() => {});
  const s = await state(page);
  expect(s.flow === 'play' && s.hero === heroes[i], `game starts with ${heroes[i]}`);
  expect(s.hearts === (heroes[i] === 'matt' ? 6 : 5), `hearts for ${heroes[i]} are ${s.hearts}`);
  await page.waitForTimeout(i === 3 ? 9000 : 7000);
  await shot(page, `4-play-${heroes[i]}`);
  const run = await page.evaluate(() => ({ dist: window.railsBridge.godotDistance, weapon: window.railsBridge.godotWeapon }));
  expect(run.dist > 20 && run.weapon === LOADOUT[heroes[i]], `${heroes[i]} starts with its ranged weapon (distance ${run.dist.toFixed(0)}, weapon ${run.weapon})`);
  await page.context().close();
}

// Hand path: scripted tracker frames. The hand moves onto a card, then dwells.
{
  const page = await open();
  await page.evaluate(() => {
    const b = window.railsBridge;
    window.__frame = { f: 0 };
    let seq = 5000;
    window.__send = (hand) => {
      window.__frame = { m: 1, n: hand ? 1 : 0, ok: !!hand, f: ++window.__frame.f, ps: 0.2, gs: 0, fr: 1.5, pg: 0, pr: 1.5,
        s: hand ? [[hand.x, hand.y, hand.pose ?? 0], [0.5, 0.5, 0], [0.5, 0.5, 0], [0.5, 0.5, 0]] : [] };
      seq++;
    };
    Object.defineProperty(b, 'seq', { get: () => seq, set: () => {} });
    Object.defineProperty(b, 'packed', { get: () => JSON.stringify(window.__frame), set: () => {} });
    b.setMagic = (on) => { b.magic = !!on; };
    b.cameraKey = 'scripted|1280x720';
    b.magic = true;
    window.__send({ x: 0.5, y: 0.5 });
  });
  const drive = async (path, hz = 12) => { for (const p of path) { await page.evaluate((h) => window.__send(h), p); await page.waitForTimeout(1000 / hz); } };
  await page.mouse.click(...(await buttonPoint(page, 'Hands')));
  await page.waitForTimeout(1500);
  expect(await flow(page) === 'select', 'the hands button stays in the campfire');
  await drive(Array.from({ length: 6 }, () => ({ x: 0.5, y: 0.5 })));
  expect(await flow(page) === 'select', 'a hand resting at the centre picks nothing');
  // A flick sends a new gesture count with the direction. The first update only sets the baseline.
  let gestures = 1;
  const flick = async (dir) => {
    await page.evaluate(([d, n]) => { window.__gesture = { gn: n, gk: d }; }, [dir, ++gestures]);
    await drive([{ x: 0.5, y: 0.5 }]);
    await page.waitForTimeout(500);
  };
  await page.evaluate(() => {
    const send = window.__send;
    window.__send = (hand) => { send(hand); Object.assign(window.__frame, window.__gesture ?? { gn: 1, gk: '' }); };
  });
  await drive(Array.from({ length: 4 }, () => ({ x: 0.5, y: 0.5 })));
  const start = await hero(page);
  await flick('r');
  const afterRight = await hero(page);
  expect(afterRight !== start, `flick right moves the highlight (${start} to ${afterRight})`);
  await flick('l');
  expect(await hero(page) === start, 'flick left moves the highlight back');
  const order = [];
  for (let i = 0; i < 5; i++) { order.push(await hero(page)); await flick('r'); }
  expect(new Set(order).size === 4, `flicks cycle round the circle (${order.join(',')})`);
  const goalId = await hero(page);
  // A held palm confirms after one second and a short palm does not.
  await drive(Array.from({ length: 6 }, () => ({ x: 0.5, y: 0.5, pose: 1 })));
  expect(await flow(page) === 'select', 'half a second of palm does not confirm');
  await drive(Array.from({ length: 4 }, () => ({ x: 0.5, y: 0.5, pose: 0 })));
  await drive(Array.from({ length: 24 }, () => ({ x: 0.5, y: 0.5, pose: 1 })));
  const picked = await state(page);
  expect(picked.flow === 'picked' || picked.flow === 'play', `palm hold picks (flow ${picked.flow}, hero ${picked.hero})`);
  expect(picked.hero === goalId, `palm hold picked the highlighted hero (${picked.hero}, highlighted ${goalId})`);
  await page.waitForTimeout(3000);
  expect((await state(page)).flow === 'play', 'pose then ride starts');
  await page.context().close();
}
console.log('errors', errors.length ? errors : 'none');
await browser.close();
process.exit(fail.length || errors.length ? 1 : 0);
