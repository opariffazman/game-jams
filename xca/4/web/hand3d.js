// Pure maths for hand-driven 3D inspect and for rub detection. No DOM, no imports, so node tests run it directly.
// Frame convention: the "user frame" is x to the user's right, y up, z from the camera into the scene. It is right-handed.
// The unmirrored camera frame is x right in the image, y down, z away from the camera. User = (-x, -y, +z).
// Orientation is a quaternion [w, x, y, z].

export const ASPECT = 4 / 3;
const WRIST = 0;
const INDEX_MCP = 5;
const MIDDLE_MCP = 9;
const PINKY_MCP = 17;
const THUMB_TIP = 4;
const INDEX_TIP = 8;

export const ORIENT_TUNING = {
  // Pinch ratio is thumb-tip to index-tip distance divided by palm size. Hysteresis stops chatter at the threshold.
  pinchOn: 0.35,
  pinchOff: 0.6,
  // One Euro style rotation filter. Cutoff in Hz rises with angular speed in rad/s.
  minCutoff: 1.5,
  beta: 0.5,
  // Output holds still until the filtered hand moves this far, then follows without a step.
  deadbandDeg: 2,
  // A raw hand jump larger than this in one frame is a tracker glitch. It is skipped for at most glitchFrames frames.
  glitchDeg: 70,
  glitchFrames: 3,
  // A pinch must hold this many frames in a row before it grabs. A held grip is never delayed.
  pinchHoldFrames: 3,
  // Middle, ring and pinky tip reach over joint reach, from the wrist. A fist reads below 1, an open hand above 1.3.
  extendedRatio: 1.15,
  // Frames after grabbing before the reference pose is taken. The closing hand moves the landmarks.
  settleFrames: 2,
  // A lost hand keeps the grab this long. Longer than a missed frame at 12 fps, shorter than a deliberate release.
  lostGraceMs: 300,
  // Object rotation per hand rotation. 1 is a direct hand-as-handle.
  gain: 1,
};

export const RUB_TUNING = {
  // A direction reversal needs this much travel in palm sizes. Same value as the PathScrub candidate in bench.js.
  reversalSize: 0.25,
  // A stroke must average this speed in palm sizes per second. A hanging hand swaying slowly stays under it.
  minStrokeSpeed: 0.6,
  // History for choosing the dominant axis.
  windowMs: 1000,
  // Energy gains the stroke length and decays with this time constant.
  energyTauMs: 1200,
  // Energy that fills the meter, in palm sizes of stroke length.
  energyFull: 2.5,
  // Rubbing is on while this many counted strokes fall inside rubWindowMs.
  minStrokes: 2,
  rubWindowMs: 1500,
};

const add = (a, b) => [a[0] + b[0], a[1] + b[1], a[2] + b[2]];
const sub = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
const scale = (a, s) => [a[0] * s, a[1] * s, a[2] * s];
const dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
const cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
const norm = (a) => { const l = Math.hypot(a[0], a[1], a[2]); return l < 1e-9 ? null : scale(a, 1 / l); };

export const qIdentity = () => [1, 0, 0, 0];
export const qConj = (q) => [q[0], -q[1], -q[2], -q[3]];
export function qMul(a, b) {
  return [
    a[0] * b[0] - a[1] * b[1] - a[2] * b[2] - a[3] * b[3],
    a[0] * b[1] + a[1] * b[0] + a[2] * b[3] - a[3] * b[2],
    a[0] * b[2] - a[1] * b[3] + a[2] * b[0] + a[3] * b[1],
    a[0] * b[3] + a[1] * b[2] - a[2] * b[1] + a[3] * b[0],
  ];
}
export function qFromAxisAngle(axis, angle) {
  const n = norm(axis);
  const s = Math.sin(angle / 2);
  return [Math.cos(angle / 2), n[0] * s, n[1] * s, n[2] * s];
}
export function qRotate(q, v) {
  const p = qMul(qMul(q, [0, v[0], v[1], v[2]]), qConj(q));
  return [p[1], p[2], p[3]];
}
// Angle in radians of the shortest rotation between two orientations.
export const qAngle = (a, b) => 2 * Math.acos(Math.min(1, Math.abs(a[0] * b[0] + a[1] * b[1] + a[2] * b[2] + a[3] * b[3])));
export function qSlerp(a, b, t) {
  let d = a[0] * b[0] + a[1] * b[1] + a[2] * b[2] + a[3] * b[3];
  const sign = d < 0 ? -1 : 1;
  d = Math.abs(d);
  let wa;
  let wb;
  if (d > 0.9995) { wa = 1 - t; wb = t; }
  else {
    const theta = Math.acos(d);
    const s = Math.sin(theta);
    wa = Math.sin((1 - t) * theta) / s;
    wb = Math.sin(t * theta) / s;
  }
  const q = [0, 1, 2, 3].map((i) => wa * a[i] + wb * sign * b[i]);
  const l = Math.hypot(...q);
  return q.map((v) => v / l);
}
// Rotation by the same axis, scaled angle. Used for gain.
export const qScale = (q, k) => qSlerp(qIdentity(), q, k);

// Orthonormal basis columns to quaternion. Standard branch on the largest diagonal term.
export function qFromBasis(x, y, z) {
  const m00 = x[0]; const m01 = y[0]; const m02 = z[0];
  const m10 = x[1]; const m11 = y[1]; const m12 = z[1];
  const m20 = x[2]; const m21 = y[2]; const m22 = z[2];
  const tr = m00 + m11 + m22;
  let q;
  if (tr > 0) { const s = Math.sqrt(tr + 1) * 2; q = [s / 4, (m21 - m12) / s, (m02 - m20) / s, (m10 - m01) / s]; }
  else if (m00 > m11 && m00 > m22) { const s = Math.sqrt(1 + m00 - m11 - m22) * 2; q = [(m21 - m12) / s, s / 4, (m01 + m10) / s, (m02 + m20) / s]; }
  else if (m11 > m22) { const s = Math.sqrt(1 + m11 - m00 - m22) * 2; q = [(m02 - m20) / s, (m01 + m10) / s, s / 4, (m12 + m21) / s]; }
  else { const s = Math.sqrt(1 + m22 - m00 - m11) * 2; q = [(m10 - m01) / s, (m02 + m20) / s, (m12 + m21) / s, s / 4]; }
  return q;
}

// Landmarks in the user frame. World landmarks (metres, origin at the hand) give depth. Image landmarks give no depth, so only in-plane roll works.
export function handPoints(hand, aspect = ASPECT) {
  const src = hand.world?.length >= 21 ? hand.world : hand.points.map((p) => [p[0] * aspect, p[1], 0]);
  return src.map(([x, y, z]) => [-x, -y, z]);
}

// y is the wrist-to-knuckle axis, x is across the knuckles (signed by sgn), z is the palm normal for a correct sgn.
export function handBasis(pts, sgn) {
  const up = norm(add(sub(pts[MIDDLE_MCP], pts[WRIST]), sub(scale(add(pts[INDEX_MCP], pts[PINKY_MCP]), 0.5), pts[WRIST])));
  if (!up) return null;
  const across = sub(pts[INDEX_MCP], pts[PINKY_MCP]);
  const x = norm(scale(sub(across, scale(up, dot(across, up))), sgn));
  if (!x) return null;
  return { x, y: up, z: cross(x, up) };
}

export const handQuat = (hand, sgn, aspect = ASPECT) => {
  const b = handBasis(handPoints(hand, aspect), sgn);
  return b ? qFromBasis(b.x, b.y, b.z) : null;
};

export function pinchRatio(points, aspect = ASPECT) {
  const d = (a, b) => Math.hypot((points[a][0] - points[b][0]) * aspect, points[a][1] - points[b][1]);
  return d(THUMB_TIP, INDEX_TIP) / Math.max(d(WRIST, MIDDLE_MCP), 1e-6);
}

// Same ratio in world space when the worker sends it. Image-space tips overlap when a curled hand points at the camera or hangs, world space does not.
export function pinchRatio3d(hand, aspect = ASPECT) {
  const w = hand.world;
  if (!w || w.length < 21) return pinchRatio(hand.points, aspect);
  const d = (a, b) => Math.hypot(w[a][0] - w[b][0], w[a][1] - w[b][1], w[a][2] - w[b][2]);
  return d(THUMB_TIP, INDEX_TIP) / Math.max(d(WRIST, MIDDLE_MCP), 1e-6);
}

// A real pinch keeps the middle, ring and pinky fingers out. A fist or curled hand fails this, so it never grabs.
// Image space is primary. The ratio uses reach from the wrist, so it does not depend on the hand direction.
export function fingersExtended(points, limit = ORIENT_TUNING.extendedRatio) {
  const reach = (i) => Math.hypot(points[i][0] - points[WRIST][0], points[i][1] - points[WRIST][1]);
  return [[12, 10], [16, 14], [20, 18]].every(([tip, pip]) => reach(tip) / Math.max(reach(pip), 1e-6) > limit);
}

// A hanging hand points its fingers down. Grabbing needs the fingers level or up, with the middle knuckle not below the wrist by more than this share of palm size.
export const GRAB_MAX_DROP = 0.15;
export function fingersDown(points, aspect = ASPECT) {
  const drop = points[MIDDLE_MCP][1] - points[WRIST][1];
  const size = Math.max(Math.hypot((points[MIDDLE_MCP][0] - points[WRIST][0]) * aspect, drop), 1e-6);
  return drop / size > GRAB_MAX_DROP;
}

export class OrientationFilter {
  constructor(tuning = {}) { this.k = { ...ORIENT_TUNING, ...tuning }; this.reset(); }
  reset() { this.q = null; this.out = null; this.t = 0; }
  push(q, tMs) {
    if (!this.q) { this.q = q; this.out = q; this.t = tMs; return q; }
    const dt = Math.max((tMs - this.t) / 1000, 1e-3);
    this.t = tMs;
    const cutoff = this.k.minCutoff + this.k.beta * (qAngle(this.q, q) / dt);
    const alpha = 1 / (1 + 1 / (2 * Math.PI * cutoff) / dt);
    this.q = qSlerp(this.q, q, alpha);
    const dead = (this.k.deadbandDeg * Math.PI) / 180;
    const ang = qAngle(this.out, this.q);
    if (ang > dead) this.out = qSlerp(this.q, this.out, dead / ang);
    return this.out;
  }
}

// Hand as a handle. While the hand pinches or makes a fist, the object turns by the change in hand orientation since the grab.
// Opening the hand releases it, so the player can regrip and turn past the range one wrist turn gives.
export class HandleRotation {
  constructor(tuning = {}) {
    this.k = { ...ORIENT_TUNING, ...tuning };
    this.filter = new OrientationFilter(this.k);
    this.object = qIdentity();
    this.reset();
  }
  reset() {
    this.engaged = false; this.pinching = false; this.pinchRun = 0; this.settle = 0; this.sgn = 1; this.grabQ = null; this.grabObject = null;
    this.lastRaw = null; this.glitchRun = 0; this.lostSince = -1; this.glitches = 0; this.grabs = 0;
    this.filter.reset();
  }
  resetObject() { this.object = qIdentity(); this.grabObject = null; if (this.engaged) this.grabQ = null; this.settle = 0; }
  // hand: { points, world, side, pinch, fist } or null.
  update(tMs, hand) {
    const k = this.k;
    if (!hand) {
      if (this.engaged && this.lostSince < 0) this.lostSince = tMs;
      if (this.engaged && tMs - this.lostSince > k.lostGraceMs) this.release();
      return this.state();
    }
    this.lostSince = -1;
    // A new grab needs extended fingers (hand.extended, when the caller sets it) and a pinch held for pinchHoldFrames.
    const canStart = hand.extended !== false;
    if (hand.pinch > k.pinchOff) { this.pinching = false; this.pinchRun = 0; }
    else if (hand.pinch < k.pinchOn && (this.engaged || canStart)) {
      this.pinchRun++;
      if (this.engaged || this.pinchRun >= k.pinchHoldFrames) this.pinching = true;
    } else if (!this.engaged) this.pinchRun = 0;
    const clutch = this.pinching || !!hand.fist;
    if (!clutch) { if (this.engaged) this.release(); return this.state(); }
    if (!this.engaged) {
      this.engaged = true; this.settle = 0; this.grabQ = null; this.lastRaw = null; this.glitchRun = 0; this.grabs++;
      this.sgn = hand.side === 'Left' ? -1 : 1;
      this.filter.reset();
    }
    const raw = handQuat(hand, this.sgn);
    if (!raw) return this.state();
    if (this.lastRaw && qAngle(this.lastRaw, raw) > (k.glitchDeg * Math.PI) / 180 && this.glitchRun < k.glitchFrames) { this.glitchRun++; this.glitches++; return this.state(); }
    this.glitchRun = 0;
    this.lastRaw = raw;
    const smooth = this.filter.push(raw, tMs);
    if (!this.grabQ) {
      if (++this.settle >= k.settleFrames) { this.grabQ = smooth; this.grabObject = this.object; }
      return this.state();
    }
    const rel = qScale(qMul(smooth, qConj(this.grabQ)), k.gain);
    this.object = qMul(rel, this.grabObject);
    return this.state();
  }
  release() { this.engaged = false; this.pinching = false; this.pinchRun = 0; this.lostSince = -1; this.grabQ = null; this.lastRaw = null; this.filter.reset(); }
  state() { return { engaged: this.engaged, settling: this.engaged && !this.grabQ, object: this.object }; }
}

// Counts rub strokes of one hand. A stroke is a reversal after enough travel at enough average speed.
// Energy adds each stroke length and decays, so the meter falls when the hand stops.
// x, y and size share one unit (palm sizes work, with x already scaled by the aspect ratio).
export class RubMeter {
  constructor(tuning = {}) { this.k = { ...RUB_TUNING, ...tuning }; this.reset(); }
  reset() {
    this.hist = []; this.axis = null; this.dir = 0; this.turn = 0; this.turnT = 0; this.ext = 0; this.extT = 0;
    this.energy = 0; this.lastT = null; this.strokes = 0; this.stamps = [];
  }
  get level() { return Math.min(1, this.energy / this.k.energyFull); }
  get rubbing() { return this.stamps.length >= this.k.minStrokes; }
  tick(tMs) {
    if (this.lastT !== null) this.energy *= Math.exp(-(tMs - this.lastT) / this.k.energyTauMs);
    this.lastT = tMs;
    this.stamps = this.stamps.filter((s) => tMs - s <= this.k.rubWindowMs);
  }
  // active is false when the hand is outside the weapon region. Leaving the region forgets the stroke in progress.
  push(tMs, x, y, size, active = true) {
    this.tick(tMs);
    if (!active) { this.hist = []; this.axis = null; return 0; }
    const k = this.k;
    this.hist.push({ t: tMs, x, y });
    while (this.hist.length && tMs - this.hist[0].t > k.windowMs) this.hist.shift();
    const range = (a) => { let lo = Infinity; let hi = -Infinity; for (const s of this.hist) { lo = Math.min(lo, s[a]); hi = Math.max(hi, s[a]); } return hi - lo; };
    const axis = range('x') >= range('y') ? 'x' : 'y';
    const v = this.hist[this.hist.length - 1][axis];
    const amp = k.reversalSize * size;
    if (this.axis !== axis) { this.axis = axis; this.dir = 0; this.ext = v; this.extT = tMs; this.turn = v; this.turnT = tMs; return 0; }
    if (this.dir === 0) {
      if (Math.abs(v - this.ext) >= amp) { this.dir = Math.sign(v - this.ext); this.turn = this.ext; this.turnT = this.extT; this.ext = v; this.extT = tMs; }
      return 0;
    }
    if (this.dir * (v - this.ext) > 0) { this.ext = v; this.extT = tMs; return 0; }
    if (this.dir * (this.ext - v) < amp) return 0;
    const len = Math.abs(this.ext - this.turn);
    const seconds = (this.extT - this.turnT) / 1000;
    const counted = len >= amp && seconds > 0 && len / seconds >= k.minStrokeSpeed * size;
    this.turn = this.ext; this.turnT = this.extT; this.dir = -this.dir; this.ext = v; this.extT = tMs;
    if (!counted) return 0;
    this.energy += len / size;
    this.strokes++;
    this.stamps.push(tMs);
    return 1;
  }
}
