// Usage: node tests/hand3d.mjs. Synthetic landmark sequences check the 3D inspect maths and the rub meter in web/hand3d.js.
import { qFromAxisAngle, qMul, qAngle, qRotate, handQuat, pinchRatio, HandleRotation, RubMeter, qIdentity, ORIENT_TUNING, fingersExtended } from '../web/hand3d.js';

let failed = 0;
const check = (name, ok, detail = '') => { console.log(`${ok ? 'PASS' : 'FAIL'} ${name} ${detail}`); if (!ok) failed++; };
const deg = (r) => (r * 180) / Math.PI;
const rad = (d) => (d * Math.PI) / 180;
const FPS = 12;
const DT = 1000 / FPS;

// Hand model in the user frame, metres. Wrist at the origin, fingers along +y, palm normal along +z, index on the user's right side for sgn 1.
function model(pinch = 1) {
  const p = Array.from({ length: 21 }, () => [0, 0, 0]);
  p[5] = [0.03, 0.09, 0]; p[9] = [0.005, 0.095, 0]; p[13] = [-0.015, 0.09, 0]; p[17] = [-0.035, 0.08, 0];
  p[8] = [0.03, 0.17, 0]; p[4] = [0.03 - 0.06 * pinch, 0.15 - 0.05 * pinch, 0]; p[12] = [0.005, 0.19, 0];
  return p;
}
function toCamera(user) { return user.map(([x, y, z]) => [-x, -y, z]); }
// Image points: camera x right in the image, y down. Hand of 0.1 m palm spans 0.2 of the image height.
function toImage(cam, cx = 0.5, cy = 0.5) { return cam.map(([x, y]) => [cx + (x * 2) / (4 / 3), cy + y * 2]); }
function makeHand(q, { pinch = 1, side = 'Right', noise = 0, rng = Math.random, depth = true, cx = 0.5, cy = 0.5 } = {}) {
  const user = model(pinch).map((v) => qRotate(q, v));
  const jitter = () => (rng() - 0.5) * 2 * noise;
  const cam = toCamera(user).map(([x, y, z]) => [x + jitter(), y + jitter(), z + jitter()]);
  const points = toImage(cam, cx, cy);
  return { points, world: depth ? cam : undefined, side, pinch: pinchRatio(points), fist: false };
}
function lcg(seed) { let s = seed; return () => { s = (s * 1664525 + 1013904223) % 4294967296; return s / 4294967296; }; }
const base = qFromAxisAngle([0, 0, 1], rad(0));

// 1. Orientation recovery from world landmarks, every axis, both hands.
for (const side of ['Right', 'Left']) {
  const sgn = side === 'Left' ? -1 : 1;
  const ref = handQuat(makeHand(base, { side }), sgn);
  const worst = [];
  for (const [axis, label] of [[[1, 0, 0], 'pitch'], [[0, 1, 0], 'yaw'], [[0, 0, 1], 'roll']]) {
    for (const a of [-60, -30, 30, 60]) {
      const q = qFromAxisAngle(axis, rad(a));
      const got = handQuat(makeHand(q, { side }), sgn);
      const err = deg(qAngle(qMul(got, [ref[0], -ref[1], -ref[2], -ref[3]]), q));
      worst.push(err);
      if (err > 3) console.log('  ', side, label, a, err.toFixed(2));
    }
  }
  check(`orientation recovered within 3 deg on all axes (${side})`, Math.max(...worst) <= 3, `worst ${Math.max(...worst).toFixed(2)} deg`);
}

// 2. Image-only landmarks give in-plane roll but not pitch or yaw. This pins down the limit the findings file states.
{
  const ref = handQuat(makeHand(base, { depth: false }), 1);
  const roll = handQuat(makeHand(qFromAxisAngle([0, 0, 1], rad(40)), { depth: false }), 1);
  const rollErr = deg(qAngle(qMul(roll, [ref[0], -ref[1], -ref[2], -ref[3]]), qFromAxisAngle([0, 0, 1], rad(40))));
  const yaw = handQuat(makeHand(qFromAxisAngle([0, 1, 0], rad(40)), { depth: false }), 1);
  const yawSeen = deg(qAngle(yaw, ref));
  check('image-only landmarks recover roll within 3 deg', rollErr <= 3, `${rollErr.toFixed(2)} deg`);
  check('image-only landmarks lose most of a 40 deg yaw', yawSeen < 20, `seen ${yawSeen.toFixed(1)} deg`);
}

// Drive the handle with a rotation path. Returns the final object orientation.
function run(handle, steps, { noise = 0, seed = 1, startMs = 0 } = {}) {
  const rng = lcg(seed);
  let t = startMs;
  let last;
  for (const s of steps) {
    t += DT;
    last = handle.update(t, s === null ? null : makeHand(s.q, { pinch: s.open ? 1 : 0.1, side: 'Right', noise, rng }));
  }
  return { last, t };
}
const hold = (q, n, open = false) => Array.from({ length: n }, () => ({ q, open }));
const sweep = (axis, from, to, n, open = false) => Array.from({ length: n }, (_, i) => ({ q: qFromAxisAngle(axis, rad(from + ((to - from) * (i + 1)) / n)), open }));

// 3. Handle rotation follows the hand while pinched.
{
  const h = new HandleRotation();
  run(h, hold(base, 6));
  const { last } = run(h, sweep([0, 1, 0], 0, 90, 12), { startMs: 6 * DT });
  run(h, hold(qFromAxisAngle([0, 1, 0], rad(90)), 12), { startMs: 18 * DT });
  const err = deg(qAngle(h.object, qFromAxisAngle([0, 1, 0], rad(90))));
  check('pinch drag turns the object 90 deg about yaw within 8 deg', err <= 8 && last.engaged, `error ${err.toFixed(2)} deg`);
}

// 4. Jitter is rejected. A still pinched hand with 2 mm landmark noise moves the object by less than the deadband plus a margin.
{
  const h = new HandleRotation();
  run(h, hold(base, 4));
  let maxDrift = 0;
  const rng = lcg(7);
  let t = 4 * DT;
  for (let i = 0; i < 120; i++) {
    t += DT;
    h.update(t, makeHand(base, { pinch: 0.1, noise: 0.002, rng }));
    maxDrift = Math.max(maxDrift, deg(qAngle(h.object, qIdentity())));
  }
  check('2 mm landmark noise on a still pinch drifts under 4 deg', maxDrift < 4, `max drift ${maxDrift.toFixed(2)} deg`);
}

// 5. Clutch: opening the hand holds the object. Turning the open hand back does not turn the object. A second pinch continues from the held pose.
{
  const h = new HandleRotation();
  run(h, hold(base, 6));
  let t = 6 * DT;
  ({ t } = run(h, sweep([0, 1, 0], 0, 60, 8), { startMs: t }));
  ({ t } = run(h, hold(qFromAxisAngle([0, 1, 0], rad(60)), 6), { startMs: t }));
  const afterFirst = h.object;
  ({ t } = run(h, sweep([0, 1, 0], 60, 0, 8, true), { startMs: t }));
  check('open hand turned back leaves the object where it was', deg(qAngle(h.object, afterFirst)) < 0.5, `${deg(qAngle(h.object, afterFirst)).toFixed(2)} deg`);
  ({ t } = run(h, hold(base, 6, true), { startMs: t }));
  ({ t } = run(h, hold(base, 4), { startMs: t }));
  ({ t } = run(h, sweep([0, 1, 0], 0, 60, 8), { startMs: t }));
  run(h, hold(qFromAxisAngle([0, 1, 0], rad(60)), 8), { startMs: t });
  const total = deg(qAngle(h.object, qFromAxisAngle([0, 1, 0], rad(120))));
  check('regrip adds a second 60 deg turn, 120 deg in total, within 10 deg', total <= 10, `error ${total.toFixed(2)} deg`);
}

// 6. A single bad frame is skipped. Hand lost for less than the grace keeps the grab. Lost for longer releases it.
{
  const h = new HandleRotation();
  run(h, hold(base, 6));
  let t = 6 * DT;
  const rng = lcg(3);
  for (let i = 0; i < 4; i++) { t += DT; h.update(t, makeHand(qFromAxisAngle([0, 1, 0], rad(i * 3)), { pinch: 0.1, rng })); }
  const before = h.object;
  t += DT; h.update(t, makeHand(qFromAxisAngle([1, 0, 0], rad(150)), { pinch: 0.1, rng }));
  check('one 150 deg glitch frame is ignored', deg(qAngle(h.object, before)) < 5 && h.glitches === 1, `glitches ${h.glitches}`);
  t += DT; h.update(t, null); t += DT; h.update(t, null);
  check('two lost frames keep the grab', h.engaged);
  t += ORIENT_TUNING.lostGraceMs + DT; h.update(t, null);
  check('a hand lost past the grace releases the grab', !h.engaged);
}

// 7. Rub meter. A sine stroke at the given frequency, amplitude in palm sizes, sampled at 12 fps.
function rubRun(freq, { ampSize = 0.5, seconds = 6, size = 0.2, hanging = false, still = false, region = true } = {}) {
  const m = new RubMeter();
  let peak = 0;
  const rng = lcg(11);
  let t = 0;
  let strokesAt2 = 0;
  for (let i = 0; i < seconds * FPS; i++) {
    t = i * DT;
    const sway = hanging ? 0.04 * size * Math.sin((2 * Math.PI * 0.4 * t) / 1000) : 0;
    const x = still ? 0 : ampSize * size * Math.sin((2 * Math.PI * freq * t) / 1000);
    const jitter = (rng() - 0.5) * 0.04 * size;
    m.push(t, x + sway + jitter, (rng() - 0.5) * 0.04 * size, size, region);
    if (i === 2 * FPS) strokesAt2 = m.strokes;
    if (t > 2000) peak = Math.max(peak, m.level);
  }
  return { m, peak, expected: 2 * freq * (seconds - 0.5) };
}
for (const f of [0.5, 1, 1.5, 2, 3]) {
  const r = rubRun(f);
  const lo = f <= 2 ? 0.6 : 0.3;
  check(`rub at ${f} Hz counts strokes and fills the meter`, r.m.strokes >= lo * r.expected && r.peak > 0.3, `strokes ${r.m.strokes} of about ${r.expected.toFixed(0)}, peak ${r.peak.toFixed(2)}`);
}
{
  const r = rubRun(1, { still: true });
  check('a still hand counts no strokes', r.m.strokes === 0 && r.peak === 0, `strokes ${r.m.strokes}`);
  const hang = rubRun(1, { hanging: true, still: true });
  check('a hanging hand with sway and noise counts no strokes', hang.m.strokes === 0, `strokes ${hang.m.strokes}`);
  const slow = rubRun(0.15);
  check('a slow 0.15 Hz wave counts no rub', slow.m.strokes === 0 || !slow.m.rubbing, `strokes ${slow.m.strokes}`);
  const out = rubRun(1.5, { region: false });
  check('rubbing outside the weapon region counts nothing', out.m.strokes === 0);
  const m = new RubMeter();
  let t = 0;
  for (let i = 0; i < 4 * FPS; i++) { t = i * DT; m.push(t, 0.1 * Math.sin((2 * Math.PI * 1.5 * t) / 1000), 0, 0.2); }
  const full = m.level;
  for (let i = 0; i < 4 * FPS; i++) { t += DT; m.push(t, 0, 0, 0.2); }
  check('the meter decays to under a quarter 4 s after the hand stops', full > 0.4 && m.level < full / 4, `full ${full.toFixed(2)} later ${m.level.toFixed(2)}`);
}

// 8. Pinch guard. Image-space hand with pip joints, so finger extension can be measured.
function guardHand({ thumbGap, curled }) {
  const p = Array.from({ length: 21 }, () => [0.5, 0.8]);
  p[5] = [0.55, 0.65]; p[9] = [0.5, 0.64]; p[13] = [0.46, 0.65]; p[17] = [0.42, 0.67];
  p[6] = [0.56, 0.58]; p[10] = [0.5, 0.57]; p[14] = [0.45, 0.58]; p[18] = [0.41, 0.6];
  const tipY = curled ? 0.62 : 0.45;
  p[12] = [0.5, tipY]; p[16] = [0.45, tipY + 0.01]; p[20] = [0.4, tipY + 0.04];
  p[8] = [0.57, 0.5]; p[4] = [0.57 - thumbGap, 0.5];
  return { points: p, side: 'Right', pinch: pinchRatio(p), fist: false, extended: fingersExtended(p) };
}
const feed = (h, hand, n) => { let out; for (let i = 0; i < n; i++) out = h.update(1000 + i * DT, hand); return out; };
{
  const fist = guardHand({ thumbGap: 0.005, curled: true });
  const curled = guardHand({ thumbGap: 0.02, curled: true });
  const pinch = guardHand({ thumbGap: 0.005, curled: false });
  check('fingersExtended is false for a fist and true for a pinch with open fingers', !fingersExtended(fist.points) && fingersExtended(pinch.points));
  check('a fist with thumb at the index tip never grabs', !feed(new HandleRotation(), fist, 30).engaged);
  check('a curled hand never grabs', !feed(new HandleRotation(), curled, 30).engaged);
  check('a pinch with extended fingers grabs', feed(new HandleRotation(), pinch, 30).engaged);
  const h2 = new HandleRotation();
  check('a pinch does not grab on frame 2', !feed(h2, pinch, 2).engaged && h2.grabs === 0);
  check('a pinch grabs on frame 3', feed(new HandleRotation(), pinch, 3).engaged);
  const h3 = new HandleRotation();
  feed(h3, pinch, 2); feed(h3, guardHand({ thumbGap: 0.2, curled: false }), 1); feed(h3, pinch, 2);
  check('a pinch broken by an open frame restarts the 3-frame hold', !h3.engaged);
}

console.log(failed ? `${failed} FAILED` : 'all passed');
process.exit(failed ? 1 : 0);
