// Usage: node tests/gestures_unit.mjs. Feeds synthetic palm traces at 12 fps through the engine and counts flicks.
import { GestureEngine } from '../web/gestures.js';
import { copyFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
// The camera package is CommonJS to Node, so the filter loads from a copy with an .mjs extension.
const filterCopy = `${tmpdir()}/rails-filters-${process.pid}.mjs`;
copyFileSync(new URL('../camera/js/filters.js', import.meta.url), filterCopy);
const { OneEuro } = await import(filterCopy);

const FRAME_MS = 1000 / 12;
const SIZE = 0.2;
let seed = 7;
const rand = () => { seed = (seed * 16807) % 2147483647; return seed / 2147483647; };
const jitter = (amp) => (rand() - 0.5) * 2 * amp;

// A path is a function of time in ms that returns [x, y] in frame shares (x mirrored). Returns null for a dropped frame.
function run(path, durationMs, { drop = 0, noise = 0.004, steer = 'flick', tuning } = {}) {
  const engine = new GestureEngine({ OneEuro, tuning });
  engine.setSteer(steer);
  const events = [];
  for (let t = 0; t <= durationMs; t += FRAME_MS + jitter(6)) {
    if (rand() < drop) { engine.update([], -1, t); continue; }
    const [x, y] = path(t);
    const d = engine.update([{ x: x + jitter(noise), y: y + jitter(noise), size: SIZE * (1 + jitter(0.03)) }], 0, t);
    if (d) events.push([Math.round(t), d]);
  }
  return { events, engine };
}
const smooth = (a, b, t0, dur) => (t) => (t <= t0 ? a : t >= t0 + dur ? b : a + (b - a) * (3 * ((t - t0) / dur) ** 2 - 2 * ((t - t0) / dur) ** 3));

const results = { pass: 0, fail: 0 };
const check = (ok, msg) => { results[ok ? 'pass' : 'fail']++; console.log(ok ? 'PASS' : 'FAIL', msg); };

// Detection rate across amplitude and speed. A flick spans 1.9 to 3 palm sizes (0.38 to 0.6 of the frame width in x).
const dirs = { r: [1, 0], l: [-1, 0], d: [0, 1], u: [0, -1] };
const summary = {};
for (const [name, [dx, dy]] of Object.entries(dirs)) {
  let hit = 0, total = 0, wrong = 0, extra = 0;
  for (const dur of [140, 200, 260]) {
    for (const palms of [2.2, 2.8]) {
      for (const drop of [0, 0.15]) {
        for (let rep = 0; rep < 10; rep++) {
          const horiz = dx !== 0;
          const reach = palms * SIZE / (horiz ? 4 / 3 : 1);
          const x0 = horiz ? 0.5 - dx * reach / 2 : 0.5, y0 = horiz ? 0.5 : 0.5 - dy * reach / 2;
          const px = smooth(x0, x0 + dx * reach, 600, dur), py = smooth(y0, y0 + dy * reach, 600, dur);
          const { events } = run((t) => [px(t), py(t)], 1800, { drop });
          total++;
          if (events.some(([, d]) => d === name)) hit++;
          if (events.some(([, d]) => d !== name)) wrong++;
          if (events.length > 1) extra++;
        }
      }
    }
  }
  summary[name] = { hit, total, wrong, extra };
  console.log(`flick ${name}: detected ${hit}/${total} (${(100 * hit / total).toFixed(0)}%), wrong direction ${wrong}, double fire ${extra}`);
}
const overall = Object.values(summary).reduce((a, s) => a + s.hit, 0) / Object.values(summary).reduce((a, s) => a + s.total, 0);
check(overall >= 0.9, `overall flick detection ${(100 * overall).toFixed(0)}% (needs 90%)`);
check(Object.values(summary).every((s) => s.wrong === 0), 'no flick reads as the wrong direction');

// Return stroke: flick right fast, then the hand returns left in 700 ms. Only one event must fire.
{
  let bad = 0, runs = 0;
  for (const back of [500, 700, 900]) {
    for (let rep = 0; rep < 10; rep++) {
      const out = smooth(0.35, 0.65, 600, 180), ret = smooth(0.65, 0.35, 1000, back);
      const { events } = run((t) => [t < 1000 ? out(t) : ret(t), 0.5], 2600);
      runs++; if (events.length !== 1 || events[0][1] !== 'r') bad++;
    }
  }
  check(bad === 0, `return stroke never counts (${bad}/${runs} runs fired extra or wrong events)`);
}

// Quick return: the hand snaps back in 250 ms. This is the hard case. Report it, do not hide it.
{
  let one = 0, runs = 0;
  for (let rep = 0; rep < 20; rep++) {
    const out = smooth(0.35, 0.65, 600, 180), ret = smooth(0.65, 0.35, 900, 250);
    const { events } = run((t) => [t < 900 ? out(t) : ret(t), 0.5], 2400);
    runs++; if (events.length === 1) one++;
  }
  console.log(`quick return (250 ms): exactly one event in ${one}/${runs} runs`);
  check(one / runs >= 0.9, 'a snap-back return stays a single event (needs 90%)');
}

// Two deliberate flicks to the right with a slow reset between them: both must count.
{
  let ok = 0, runs = 0;
  for (let rep = 0; rep < 20; rep++) {
    const first = smooth(0.2, 0.5, 400, 180), back = smooth(0.5, 0.2, 900, 600), second = smooth(0.2, 0.5, 1900, 180);
    const { events } = run((t) => [t < 900 ? first(t) : t < 1500 ? back(t) : second(t), 0.5], 2800);
    runs++; if (events.length === 2 && events.every(([, d]) => d === 'r')) ok++;
  }
  console.log(`repeat flick after a slow reset: exactly two right events in ${ok}/${runs} runs`);
  check(ok / runs >= 0.9, 'a repeat flick after a slow reset counts (needs 90%)');
}

// Resting hand with jitter: no events over 60 s.
{
  let n = 0;
  for (let rep = 0; rep < 6; rep++) n += run(() => [0.5, 0.5], 10000, { noise: 0.008 }).events.length;
  check(n === 0, `resting hand, 60 s of jitter: ${n} false positives`);
}
// Slow drift across the frame in 2 s and 3 s.
{
  let n = 0;
  for (const dur of [1500, 2000, 3000]) {
    for (let rep = 0; rep < 10; rep++) {
      const p = smooth(0.2, 0.8, 500, dur), q = smooth(0.3, 0.7, 500, dur);
      n += run((t) => [p(t), q(t)], 4500).events.length;
    }
  }
  check(n === 0, `slow drift across the frame (1.5 to 3 s): ${n} false positives in 30 runs`);
}
// Walking the hand to a new spot at normal speed (0.4 s for 1.2 palms) must not fire.
{
  let n = 0;
  for (let rep = 0; rep < 20; rep++) {
    const p = smooth(0.4, 0.4 + 1.2 * SIZE / (4 / 3), 500, 400);
    n += run((t) => [p(t), 0.5], 1500).events.length;
  }
  check(n === 0, `small repositioning move: ${n} false positives in 20 runs`);
}

// Slide mode suppresses horizontal flicks and reports position.
{
  const p = smooth(0.2, 0.8, 500, 200);
  const { events, engine } = run((t) => [p(t), 0.5], 1500, { steer: 'slide' });
  check(events.length === 0, 'slide mode: horizontal flick does not fire');
  check(engine.slideValue > 0.9, `slide value follows the hand (${engine.slideValue.toFixed(2)})`);
  const e2 = new GestureEngine({ OneEuro });
  e2.update([{ x: 0.5, y: 0.5, size: SIZE }], 0, 0);
  e2.update([], -1, 1000);
  check(e2.slideValue === -1, 'slide value is -1 after the hand is gone');
}

// Scrub: left hand holds, right hand strokes back and forth 6 times.
{
  const engine = new GestureEngine({ OneEuro });
  const frames = [];
  for (let t = 0; t < 3000; t += FRAME_MS) {
    const stroke = 0.65 + 0.07 * Math.sin((t / 1000) * 2 * Math.PI * 1.5);
    engine.update([{ x: 0.3 + jitter(0.003), y: 0.5 + jitter(0.003), size: SIZE }, { x: stroke, y: 0.5 + jitter(0.003), size: SIZE }], 0, t, { twoHands: true });
    frames.push(engine.sr);
  }
  const want = 9;
  console.log(`scrub 1.5 Hz for 3 s: ${engine.sr} reversals (about ${want} strokes)`);
  check(engine.sr >= 5 && engine.sr <= 12, `scrub reversal count ${engine.sr} is near ${want}`);
  const still = new GestureEngine({ OneEuro });
  for (let t = 0; t < 3000; t += FRAME_MS) still.update([{ x: 0.3 + jitter(0.003), y: 0.5, size: SIZE }, { x: 0.65 + jitter(0.003), y: 0.5, size: SIZE }], 0, t, { twoHands: true });
  check(still.sr === 0, `two still hands: ${still.sr} scrub reversals`);
  const zoom = new GestureEngine({ OneEuro });
  for (let t = 0; t < 3000; t += FRAME_MS) {
    const spread = 0.2 + 0.15 * (t / 3000);
    zoom.update([{ x: 0.5 - spread, y: 0.5, size: SIZE }, { x: 0.5 + spread, y: 0.5, size: SIZE }], 0, t, { twoHands: true });
  }
  check(zoom.sr === 0, `both hands spreading (zoom): ${zoom.sr} scrub reversals`);
  check(zoom.th && zoom.th[0] > 0.5, `two-hand distance reported (${zoom.th?.[0]})`);
}
console.log(results.fail ? `FAILED ${results.fail}` : 'ALL PASS');
process.exit(results.fail ? 1 : 0);
