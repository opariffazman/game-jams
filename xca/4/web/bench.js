// Test bench for hand gestures. It runs the same camera, worker and GestureEngine as the game and shows every number the game decides on.
// The game code in tracker.js is a script with side effects, so the pose rules below are copies. Keep them equal to tracker.js:
// fingerRatios, palmSize, classifyAction, the default tuning and the calibration storage key.
import { RollingAvg, OneEuro } from './js/filters.js';
import { stopStream } from './js/camera.js';
import { GestureEngine, palmCentre } from './gestures.js';
import { LabEngine, STEPS as LAB_STEPS } from './lab.js';
import { HandleRotation, RubMeter, pinchRatio, pinchRatio3d, fingersDown, fingersExtended, qRotate, qIdentity, qMul, qFromAxisAngle, ORIENT_TUNING, RUB_TUNING } from './hand3d.js';

// Every detection frame is 4:3, because gestures.js and hand3d.js assume it. A wider capture is centre-cropped to 4:3.
// The stage shows the video with object-fit: cover, so the crop and the overlay line up.
const ASPECT = 4 / 3;
const QUALITIES = {
  pc: {
    label: 'PC quality', capture: { w: 640, h: 480 }, detect: { w: 640, h: 480 }, fps: 30,
    options: { delegate: 'GPU', numHands: 2, minHandDetectionConfidence: 0.6, minHandPresenceConfidence: 0.6, minTrackingConfidence: 0.6 },
  },
  hd: {
    label: '1280x720 capture', capture: { w: 1280, h: 720 }, detect: { w: 960, h: 720 }, fps: 30,
    options: { delegate: 'GPU', numHands: 2, minHandDetectionConfidence: 0.6, minHandPresenceConfidence: 0.6, minTrackingConfidence: 0.6 },
  },
  low: { label: 'Low end', capture: { w: 640, h: 480 }, detect: { w: 320, h: 240 }, fps: 15, options: { delegate: 'CPU', numHands: 1 } },
};
const PINCH_KEY_PREFIX = 'bench-pinch-v1:';
const CALIBRATE_PHASE_S = 2;
const CALIBRATE_MIN_GAP = 0.3;
// Where the thresholds sit between the measured pinch and open values. On is below the midpoint and off above it, so the grip has hysteresis.
const CALIBRATE_ON_AT = 0.4;
const CALIBRATE_OFF_AT = 0.65;
const WRIST = 0;
const MIDDLE_MCP = 9;
// Tip and middle joint of the thumb, index, middle, ring and pinky. The game uses only the last four.
const FINGER_JOINTS = [[4, 3], [8, 6], [12, 10], [16, 14], [20, 18]];
const FINGER_NAMES = ['thumb', 'index', 'middle', 'ring', 'pinky'];
const DEFAULT_TUNING = { fistScore: 0.3, fistRatio: 1.0, palmScore: 0.5, palmRatio: 1.3 };
const CALIBRATION_KEY_PREFIX = 'rails-calib-v3:';
const LOG_SECONDS = 30;
const FLASH_MS = 1000;
const SCRUB_WINDOW_MS = 2000;
// Inspect rule in scrub_station.gd: PALM_SLOWMO_AFTER and PALM_COMMIT_AFTER.
const PALM_SLOWMO_S = 0.5;
const PALM_COMMIT_S = 1.6;
const THUMB_HOLD_S = 1.0;
const TWO_PALMS_HOLD_S = 1.0;
const TWO_PALMS_MAX_Y = 0.65;
const CONNECTIONS = [[0, 1], [1, 2], [2, 3], [3, 4], [0, 5], [5, 6], [6, 7], [7, 8], [5, 9], [9, 10], [10, 11], [11, 12], [9, 13], [13, 14], [14, 15], [15, 16], [13, 17], [17, 18], [18, 19], [19, 20], [0, 17]];
// Rub counts only while the hand is inside this box of the frame (mirrored x, y), the stand-in for the weapon on screen.
const RUB_REGION = { x0: 0.2, x1: 0.8, y0: 0.25, y1: 0.95 };
const BOX_HALF = [0.9, 0.35, 0.2];
const BOX_COLOURS = ['#5ee0ff', '#ffcf5a', '#8cf0a0'];
const HAND_COLOURS = ['#5ee0ff', '#ffcf5a'];

const $ = (id) => document.getElementById(id);
const video = $('cam');
const overlay = $('overlay');
const ctx = overlay.getContext('2d');
const gestures = new GestureEngine({ OneEuro });
const stats = { handMs: new RollingAvg(60), runs: 0, lastRuns: 0, lastAt: performance.now(), fps: 0, dropped: 0, seenTime: -1 };
const t0 = performance.now();
const state = {
  worker: null, running: false, busy: false, lastVideoTime: -1, hands: [], chosen: -1, tuning: { ...DEFAULT_TUNING }, tuningSource: 'default',
  quality: 'low', delegate: '-', delegateReason: '-', capture: '-', detectSent: '-', pinchCal: { phase: 'idle', since: 0, samples: [], pinchValue: 0, note: '' },
  cameraKey: '', flickAt: -1e9, flickDir: '', flickCount: 0, recording: false, frames: [], markers: [], events: [],
  scrubStamps: [], lastSr: 0, pathScrub: [null, null], pathStamps: [],
  gate: { palmSince: -1, thumbSince: -1, twoSince: -1, triggers: { palm: 0, thumb: 0, two: 0 }, fired: { palm: false, thumb: false, two: false } },
  gateOutput: { palm: 0, thumb: 0, two: 0, palmPhase: 'idle' },
  handle: new HandleRotation(), rub: new RubMeter(), view: qFromAxisAngle([1, 0, 0], 0.35), rubIn: false,
};

function showError(label, e) {
  const box = $('err');
  box.style.display = 'block';
  box.textContent += `${label}: ${e?.name ?? ''} ${e?.message ?? e}\n`;
}
window.addEventListener('error', (ev) => showError('window error', ev.error ?? ev.message));
window.addEventListener('unhandledrejection', (ev) => showError('unhandled rejection', ev.reason));

const now = () => Math.round(performance.now() - t0);

function fingerRatios(points) {
  const wrist = points[WRIST];
  const reach = (i) => Math.hypot(points[i][0] - wrist[0], points[i][1] - wrist[1]);
  return FINGER_JOINTS.map(([tip, pip]) => reach(tip) / reach(pip));
}

function palmSize(points) {
  const dx = (points[WRIST][0] - points[MIDDLE_MCP][0]) * ASPECT;
  return Math.hypot(dx, points[WRIST][1] - points[MIDDLE_MCP][1]);
}

// Same rules as classifyAction in tracker.js, plus the reason each clause fired. Ratios of the four non-thumb fingers decide.
function classify(hand, ratios, tuning) {
  const four = ratios.slice(1);
  const fistLabel = hand.gesture === 'Closed_Fist' && hand.score >= tuning.fistScore;
  const fistRatio = Math.max(...four) < tuning.fistRatio;
  const palmLabel = hand.gesture === 'Open_Palm' && hand.score >= tuning.palmScore;
  const palmRatio = Math.min(...four) > tuning.palmRatio;
  let pose = 'none';
  let why = '';
  if (fistLabel || fistRatio) { pose = 'fist'; why = fistLabel ? 'label' : 'ratio'; }
  else if (palmLabel || palmRatio) { pose = 'palm'; why = palmLabel && palmRatio ? 'label+ratio' : palmLabel ? 'label' : 'ratio'; }
  return { pose, why, fistLabel, fistRatio, palmLabel, palmRatio, maxRatio: Math.max(...four), minRatio: Math.min(...four) };
}

// The game saves its calibration under the camera label and size. Use it when it exists, so the bench decides like the game does.
function loadTuning(useDefaults) {
  state.tuning = { ...DEFAULT_TUNING };
  state.tuningSource = 'default';
  if (useDefaults) return;
  try {
    for (let i = 0; i < localStorage.length; i++) {
      const key = localStorage.key(i);
      if (!key.startsWith(CALIBRATION_KEY_PREFIX) || !key.endsWith(`:${state.cameraKey}`)) continue;
      const saved = JSON.parse(localStorage.getItem(key));
      state.tuning = { fistScore: saved.fist_score, fistRatio: saved.fist_ratio, palmScore: saved.palm_score, palmRatio: saved.palm_ratio };
      state.tuningSource = `game calibration (${key.slice(CALIBRATION_KEY_PREFIX.length)}, poses_ok ${saved.poses_ok})`;
      return;
    }
  } catch { /* storage unavailable */ }
}

// Candidate scrub rule: one hand, any direction, no need for the other hand to hold still.
// It counts direction reversals of the hand with the larger travel over the last second.
class PathScrub {
  constructor() { this.hist = []; this.axis = null; this.dir = 0; this.extreme = 0; }
  push(t, x, y, size) {
    this.hist.push({ t, x: x * ASPECT, y, size });
    while (this.hist.length && t - this.hist[0].t > 1000) this.hist.shift();
    const range = (a) => { const v = this.hist.map((s) => s[a]); return Math.max(...v) - Math.min(...v); };
    const axis = range('x') >= range('y') ? 'x' : 'y';
    const cur = this.hist[this.hist.length - 1];
    if (this.axis !== axis) { this.axis = axis; this.dir = 0; this.extreme = cur[axis]; return 0; }
    const v = cur[axis];
    const amp = 0.25 * cur.size;
    if (this.dir === 0) { if (Math.abs(v - this.extreme) >= amp) { this.dir = Math.sign(v - this.extreme); this.extreme = v; } return 0; }
    if (this.dir > 0) { if (v > this.extreme) this.extreme = v; else if (this.extreme - v >= amp) { this.dir = -1; this.extreme = v; return 1; } }
    else if (v < this.extreme) this.extreme = v;
    else if (v - this.extreme >= amp) { this.dir = 1; this.extreme = v; return 1; }
    return 0;
  }
}

// Cross product of the wrist-to-index-knuckle and wrist-to-pinky-knuckle directions, signed by MediaPipe's handedness label.
// The sign flips when the hand turns over, so it can tell the palm from the back of the hand. Which sign is the palm is read from the recordings.
function facing(points, side) {
  const [wx, wy] = points[0];
  const cross = (points[5][0] - wx) * (points[17][1] - wy) - (points[5][1] - wy) * (points[17][0] - wx);
  return cross * (side === 'Left' ? -1 : 1);
}

function readHands(rawHands, t) {
  const hands = rawHands.map((h) => {
    const ratios = fingerRatios(h.points);
    const centre = palmCentre(h.points);
    const decision = classify(h, ratios, state.tuning);
    return { points: h.points, world: h.world, pinch: $('worldPinch').checked ? pinchRatio3d(h) : pinchRatio(h.points), extended: fingersExtended(h.points), down: fingersDown(h.points), gesture: h.gesture, score: h.score, side: h.side, facing: facing(h.points, h.side), ratios, size: palmSize(h.points), x: 1 - centre[0], y: centre[1], ...decision };
  });
  // Like the game for a right-handed player: the hand at the larger mirrored x plays.
  let chosen = -1;
  hands.forEach((h, i) => { if (chosen < 0 || h.x > hands[chosen].x) chosen = i; });
  state.hands = hands;
  state.chosen = chosen;
  labFeed(hands, t);
  const flick = gestures.update(hands.map((h) => ({ x: h.x, y: h.y, size: h.size })), chosen, t, { twoHands: $('twoHands').checked });
  if (flick) {
    state.flickAt = t; state.flickDir = flick; state.flickCount++;
    addEvent(`flick ${flick}`);
    cancelPalmHold();
  }
  if (gestures.sr > state.lastSr) {
    for (let i = state.lastSr; i < gestures.sr; i++) state.scrubStamps.push(t);
    state.lastSr = gestures.sr;
  }
  const sorted = hands.map((h, i) => i).sort((a, b) => hands[a].x - hands[b].x);
  sorted.slice(0, 2).forEach((idx, slot) => {
    state.pathScrub[slot] ??= new PathScrub();
    const h = hands[idx];
    if (state.pathScrub[slot].push(t, h.x, h.y, h.size)) state.pathStamps.push(t);
  });
  for (let slot = hands.length; slot < 2; slot++) state.pathScrub[slot] = null;
  updateGates(t);
  update3d(t);
  state.scrubStamps = state.scrubStamps.filter((s) => t - s <= SCRUB_WINDOW_MS);
  state.pathStamps = state.pathStamps.filter((s) => t - s <= SCRUB_WINDOW_MS);
  logFrame(t, flick);
}

// Rotation uses the hand that pinches most tightly. Rub uses the other hand when two show, else the playing hand, and is off while a hand holds the box.
// A relaxed, curled hand passes the fist rule, so the fist never grips the box. Only a pinch does.
const FIST_GRIPS = false;

function update3d(t) {
  const hands = state.hands;
  // A fist also puts the thumb tip beside the index tip, so a fist hand never counts as a pinch, held or new.
  const pinchOf = (h) => (h.pose === 'fist' ? 1 : h.pinch);
  let grip = -1;
  hands.forEach((h, i) => { if (grip < 0 || pinchOf(h) < pinchOf(hands[grip])) grip = i; });
  // A new grab needs the fingers level or up. A grip already held keeps going when the hand turns past that.
  // Inspect starts from two palms, so a grip needs both hands in view. One hand alone never grips.
  const blocked = grip >= 0 && !state.handle.engaged && (hands[grip].down || hands.length < 2);
  const limits = pinchLimits(grip >= 0 ? hands[grip].side : '');
  state.handle.k.pinchOn = limits.pinchOn;
  state.handle.k.pinchOff = limits.pinchOff;
  const handle = state.handle.update(t, grip >= 0 && hands.length >= 2 ? { ...hands[grip], pinch: blocked ? 1 : pinchOf(hands[grip]), fist: FIST_GRIPS && hands[grip].pose === 'fist' } : null);
  updatePinchCalibration(t);
  const rubIdx = hands.length > 1 ? 1 - grip : state.chosen;
  const rubHand = rubIdx >= 0 && !handle.engaged ? hands[rubIdx] : null;
  state.rubIn = !!rubHand && rubHand.x >= RUB_REGION.x0 && rubHand.x <= RUB_REGION.x1 && rubHand.y >= RUB_REGION.y0 && rubHand.y <= RUB_REGION.y1;
  if (rubHand) state.rub.push(t, rubHand.x * ASPECT, rubHand.y, rubHand.size, state.rubIn);
  else state.rub.tick(t);
}

// Saved thresholds per hand label. A missing entry uses the defaults in ORIENT_TUNING.
function pinchLimits(side) {
  try {
    const saved = JSON.parse(localStorage.getItem(PINCH_KEY_PREFIX + side) ?? 'null');
    if (saved) return { pinchOn: saved.pinchOn, pinchOff: saved.pinchOff, source: `calibrated (${side})` };
  } catch { /* storage unavailable */ }
  return { pinchOn: ORIENT_TUNING.pinchOn, pinchOff: ORIENT_TUNING.pinchOff, source: 'default' };
}

const median = (v) => [...v].sort((a, b) => a - b)[Math.floor(v.length / 2)];

// Hold a pinch for 2 s, then hold the hand open for 2 s. The playing hand is the one measured.
function updatePinchCalibration(t) {
  const c = state.pinchCal;
  if (c.phase === 'idle') return;
  const main = state.hands[state.chosen];
  if (!main) { c.since = t; c.samples = []; return; }
  if (c.phase === 'pinch' && !main.extended) { c.since = t; c.samples = []; c.note = 'Pinch with the middle, ring and pinky fingers out.'; return; }
  c.note = '';
  c.samples.push(main.pinch);
  if (t - c.since < CALIBRATE_PHASE_S * 1000) return;
  if (c.phase === 'pinch') { c.pinchValue = median(c.samples); c.phase = 'open'; c.since = t; c.samples = []; return; }
  const open = median(c.samples);
  const gap = open - c.pinchValue;
  if (gap < CALIBRATE_MIN_GAP) { c.note = `Rejected: open ${open.toFixed(2)} is too close to pinch ${c.pinchValue.toFixed(2)}. Try again.`; c.phase = 'idle'; return; }
  const saved = { pinchOn: +(c.pinchValue + gap * CALIBRATE_ON_AT).toFixed(3), pinchOff: +(c.pinchValue + gap * CALIBRATE_OFF_AT).toFixed(3), pinchMeasured: +c.pinchValue.toFixed(3), openMeasured: +open.toFixed(3) };
  try { localStorage.setItem(PINCH_KEY_PREFIX + (main.side || ''), JSON.stringify(saved)); } catch { /* storage unavailable */ }
  c.note = `Saved for ${main.side || 'hand'}: on ${saved.pinchOn}, off ${saved.pinchOff}.`;
  c.phase = 'idle';
  addEvent(`pinch calibrated ${main.side}: on ${saved.pinchOn} off ${saved.pinchOff}`);
}

function cancelPalmHold() { state.gate.palmSince = -1; }

function updateGates(t) {
  const g = state.gate;
  const hands = state.hands;
  const main = hands[state.chosen];
  const trig = (name, since, needS) => {
    const held = since >= 0 ? (t - since) / 1000 : 0;
    if (held >= needS && !g.fired[name]) { g.fired[name] = true; g.triggers[name]++; addEvent(`GATE ${name} would open inspect`); }
    if (since < 0) g.fired[name] = false;
    return held;
  };
  // Current game rule: the playing hand shows a palm pose.
  if (main?.pose === 'palm') { if (g.palmSince < 0) g.palmSince = t; } else g.palmSince = -1;
  const palmHeld = trig('palm', g.palmSince, PALM_COMMIT_S);
  state.gateOutput.palm = palmHeld;
  state.gateOutput.palmPhase = palmHeld >= PALM_COMMIT_S ? 'OPEN' : palmHeld >= PALM_SLOWMO_S ? 'slow motion' : palmHeld > 0 ? 'palm seen' : 'idle';
  if (hands.some((h) => h.gesture === 'Thumb_Up' && h.score >= 0.5)) { if (g.thumbSince < 0) g.thumbSince = t; } else g.thumbSince = -1;
  state.gateOutput.thumb = trig('thumb', g.thumbSince, THUMB_HOLD_S);
  const palms = hands.filter((h) => h.pose === 'palm' && h.y < TWO_PALMS_MAX_Y);
  if (palms.length >= 2) { if (g.twoSince < 0) g.twoSince = t; } else g.twoSince = -1;
  state.gateOutput.two = trig('two', g.twoSince, TWO_PALMS_HOLD_S);
}

function addEvent(text) {
  const t = now();
  state.events.push({ t, text });
  if (state.events.length > 200) state.events.shift();
  $('log').textContent = state.events.slice(-60).reverse().map((e) => `${(e.t / 1000).toFixed(2)}s  ${e.text}`).join('\n');
}

function logFrame(t, flick) {
  if (!state.recording) return;
  const main = state.hands[state.chosen];
  state.frames.push({
    t, flick, pose: main?.pose ?? 'none', sr: gestures.sr, sl: +gestures.slideValue.toFixed(3), th: gestures.th,
    pathReversals: state.pathStamps.length, grip: state.handle.engaged, rubLevel: +state.rub.level.toFixed(3), rubStrokes: state.rub.strokes,
    gates: { palm: +state.gateOutput.palm.toFixed(2), thumb: +state.gateOutput.thumb.toFixed(2), two: +state.gateOutput.two.toFixed(2) },
    hands: state.hands.map((h, i) => ({
      chosen: i === state.chosen, gesture: h.gesture, score: +h.score.toFixed(3), ratios: h.ratios.map((r) => +r.toFixed(3)), size: +h.size.toFixed(4),
      x: +h.x.toFixed(4), y: +h.y.toFixed(4), pinch: +h.pinch.toFixed(3), down: h.down, world: h.world?.map((p) => p.map((v) => +v.toFixed(4))), pose: h.pose, why: h.why, side: h.side, facing: +h.facing.toFixed(5),
    })),
  });
  const cut = t - LOG_SECONDS * 1000;
  while (state.frames.length && state.frames[0].t < cut) state.frames.shift();
}

function addMarker(label) {
  const text = (label ?? $('markText').value).trim() || 'mark';
  const t = now();
  state.markers.push({ t, label: text });
  addEvent(`MARK ${text}`);
  const chip = document.createElement('button');
  chip.textContent = text;
  chip.title = 'Use this label again';
  chip.onclick = () => { $('markText').value = text; addMarker(text); };
  $('chips').append(chip);
}

function qualitySummary() {
  const q = QUALITIES[state.quality];
  const ms = stats.handMs.v;
  return {
    mode: state.quality, label: q.label, delegate: state.delegate, delegateReason: state.delegateReason, capture: state.capture, detectSent: state.detectSent,
    targetFps: q.fps, trackerFps: +stats.fps.toFixed(1), workerMsAvg: +stats.handMs.avg.toFixed(1), workerMsMax: +(ms.length ? Math.max(...ms) : 0).toFixed(1),
    droppedFrames: stats.dropped, options: q.options,
  };
}

function buildLog() {
  const first = state.frames[0]?.t ?? 0;
  return {
    savedAt: new Date().toISOString(), userAgent: navigator.userAgent, screen: `${screen.width}x${screen.height}`, dpr: devicePixelRatio,
    cameraKey: state.cameraKey, quality: qualitySummary(), pinchLimits: { Left: pinchLimits('Left'), Right: pinchLimits('Right') }, worldPinch: $('worldPinch').checked, tuning: state.tuning, tuningSource: state.tuningSource, trackerFps: +stats.fps.toFixed(1),
    gestureTuning: gestures.tuning,
    markers: state.markers.filter((m) => m.t >= first), allMarkers: state.markers, events: state.events, frames: state.frames,
  };
}
window.benchSave = buildLog;

function download() {
  const blob = new Blob([JSON.stringify(buildLog())], { type: 'application/json' });
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = `hand-bench-${Date.now()}.json`;
  a.click();
  URL.revokeObjectURL(a.href);
}

function draw() {
  requestAnimationFrame(draw);
  ctx.clearRect(0, 0, overlay.width, overlay.height);
  state.hands.forEach((h, i) => {
    const colour = HAND_COLOURS[i % 2];
    ctx.lineWidth = 5;
    ctx.strokeStyle = colour;
    ctx.beginPath();
    for (const [a, b] of CONNECTIONS) { ctx.moveTo(h.points[a][0] * overlay.width, h.points[a][1] * overlay.height); ctx.lineTo(h.points[b][0] * overlay.width, h.points[b][1] * overlay.height); }
    ctx.stroke();
    h.points.forEach((p, k) => {
      ctx.fillStyle = [4, 8, 12, 16, 20].includes(k) ? '#fff' : colour;
      ctx.beginPath();
      ctx.arc(p[0] * overlay.width, p[1] * overlay.height, [4, 8, 12, 16, 20].includes(k) ? 9 : 6, 0, Math.PI * 2);
      ctx.fill();
    });
  });
  drawBox();
  const flash = $('flash');
  const active = now() - state.flickAt < FLASH_MS;
  flash.classList.toggle('show', active);
  if (active) flash.textContent = { l: '←', r: '→', u: '↑', d: '↓' }[state.flickDir] ?? '';
}

const boxCanvas = $('box');
const boxCtx = boxCanvas.getContext('2d');
const BOX_VERTS = [-1, 1].flatMap((x) => [-1, 1].flatMap((y) => [-1, 1].map((z) => [x * BOX_HALF[0], y * BOX_HALF[1], z * BOX_HALF[2]])));
const BOX_EDGES = BOX_VERTS.flatMap((a, i) => BOX_VERTS.map((b, j) => [i, j]).filter(([i2, j]) => j > i2 && BOX_VERTS[i2].filter((v, k) => v !== BOX_VERTS[j][k]).length === 1));
function drawBox() {
  const w = boxCanvas.width;
  const h = boxCanvas.height;
  boxCtx.clearRect(0, 0, w, h);
  const q = qMul(state.view, state.handle.object);
  const project = ([x, y, z]) => { const f = 4 / (4 - z); return [w / 2 + x * f * w * 0.3, h / 2 - y * f * w * 0.3, z]; };
  const pts = BOX_VERTS.map((v) => project(qRotate(q, v)));
  boxCtx.lineWidth = 4;
  BOX_EDGES.forEach(([a, b]) => {
    const axisIdx = BOX_VERTS[a].findIndex((v, k) => v !== BOX_VERTS[b][k]);
    boxCtx.strokeStyle = BOX_COLOURS[axisIdx];
    boxCtx.beginPath(); boxCtx.moveTo(pts[a][0], pts[a][1]); boxCtx.lineTo(pts[b][0], pts[b][1]); boxCtx.stroke();
  });
  boxCtx.fillStyle = state.handle.engaged ? '#8cf0a0' : '#b6c2cf';
  boxCtx.font = '600 18px system-ui, sans-serif';
  boxCtx.fillText(state.handle.engaged ? (state.handle.state().settling ? 'Grip: settling' : 'Grip: turning') : 'Open: box held', 10, 24);
}

const pct = (v) => `${Math.max(0, Math.min(100, v * 100)).toFixed(0)}%`;
const mark = (ok) => (ok ? 'YES' : 'no ');

function render() {
  const t = now();
  const n = performance.now();
  stats.fps = (stats.runs - stats.lastRuns) / ((n - stats.lastAt) / 1000);
  stats.lastRuns = stats.runs; stats.lastAt = n;
  const q = QUALITIES[state.quality];
  const msList = stats.handMs.v;
  $('status').textContent = `Tracker ${stats.fps.toFixed(1)} fps  hands ${state.hands.length}  ${state.recording ? `recording ${state.frames.length} frames` : 'not recording'}`;
  $('qualityInfo').textContent =
    `Mode: ${q.label}\n` +
    `Delegate: ${state.delegate}  (${state.delegateReason})\n` +
    `Capture: ${state.capture}  target ${q.fps} fps\n` +
    `Detection frame sent: ${state.detectSent}\n` +
    `Tracker: ${stats.fps.toFixed(1)} fps  worker ${stats.handMs.avg.toFixed(1)} ms avg, ${(msList.length ? Math.max(...msList) : 0).toFixed(1)} ms max\n` +
    `Dropped frames: ${stats.dropped}  hands: ${state.hands.length}\n` +
    `Confidences: ${q.options.minHandDetectionConfidence ?? 'default'} detect, ${q.options.minHandPresenceConfidence ?? 'default'} presence, ${q.options.minTrackingConfidence ?? 'default'} tracking\n` +
    `Pinch limits: left on ${pinchLimits('Left').pinchOn} off ${pinchLimits('Left').pinchOff} (${pinchLimits('Left').source}), right on ${pinchLimits('Right').pinchOn} off ${pinchLimits('Right').pinchOff} (${pinchLimits('Right').source})`;
  const pc = state.pinchCal;
  $('calibratePinch').textContent = pc.phase === 'idle' ? 'Calibrate pinch' : `${pc.phase === 'pinch' ? 'Hold a pinch' : 'Hold hand open'}: ${Math.max(0, CALIBRATE_PHASE_S - (now() - pc.since) / 1000).toFixed(1)} s`;
  $('calibrateNote').textContent = pc.note;
  const hands = state.hands;
  $('hands').textContent = hands.length ? hands.map((h, i) =>
    `Hand ${i}${i === state.chosen ? ' (plays)' : ''}\n` +
    `  MediaPipe: ${h.gesture} ${h.score.toFixed(2)}  side ${h.side || '-'}  facing ${h.facing >= 0 ? '+' : '-'}${Math.abs(h.facing).toFixed(4)}\n` +
    `  ratios: ${h.ratios.map((r, k) => `${FINGER_NAMES[k]} ${r.toFixed(2)}`).join('  ')}\n` +
    `  palm size ${h.size.toFixed(3)}  centre ${h.x.toFixed(2)}, ${h.y.toFixed(2)}`).join('\n\n') : 'No hands.';
  const main = hands[state.chosen];
  const k = state.tuning;
  $('pose').textContent = main
    ? `Limits: ${state.tuningSource}\n` +
      `  fist score ${k.fistScore}  fist ratio ${k.fistRatio.toFixed(2)}  palm score ${k.palmScore}  palm ratio ${k.palmRatio.toFixed(2)}\n\n` +
      `Fist: label Closed_Fist >= ${k.fistScore}: ${mark(main.fistLabel)}  max ratio ${main.maxRatio.toFixed(2)} < ${k.fistRatio.toFixed(2)}: ${mark(main.fistRatio)}\n` +
      `Palm: label Open_Palm >= ${k.palmScore}: ${mark(main.palmLabel)}  min ratio ${main.minRatio.toFixed(2)} > ${k.palmRatio.toFixed(2)}: ${mark(main.palmRatio)}\n\n` +
      `Game pose: ${main.pose.toUpperCase()}${main.why ? ` (by ${main.why})` : ''}`
    : 'No playing hand.';
  const th = gestures.th;
  $('gest').textContent =
    `Flick: ${state.flickDir || '-'} (${state.flickCount} total${state.flickCount ? `, ${((t - state.flickAt) / 1000).toFixed(1)} s ago` : ''})\n` +
    `Slide: ${gestures.slideValue < 0 ? '-' : gestures.slideValue.toFixed(2)}\n` +
    `Two hands th: ${th ? `distance ${th[0].toFixed(2)}  angle ${th[1].toFixed(2)}  mid ${th[2].toFixed(2)}, ${th[3].toFixed(2)}` : '-'}\n` +
    `Scrub, game rule: ${gestures.scrub.axis ? `active on ${gestures.scrub.axis}` : 'idle (needs two hands, one still)'}  reversals total ${gestures.sr}  last 2 s ${state.scrubStamps.length}\n` +
    `Scrub, path candidate: reversals last 2 s ${state.pathStamps.length}`;
  $('slideBar').style.width = pct(gestures.slideValue < 0 ? 0 : gestures.slideValue);
  $('scrubBar').style.width = pct(state.scrubStamps.length / 6);
  $('pathBar').style.width = pct(state.pathStamps.length / 6);
  const hd = state.handle;
  const rub = state.rub;
  $('box3d').textContent =
    `Grip (pinch below ${ORIENT_TUNING.pinchOn} of palm size, or fist; opens above ${ORIENT_TUNING.pinchOff}): ${hd.engaged ? 'ON' : 'off'}  now ${state.hands.length ? Math.min(...state.hands.map((h) => (h.pose === 'fist' ? 1 : h.pinch))).toFixed(2) : '-'} fingers ${state.hands.some((h) => h.down) ? 'DOWN (grab blocked)' : 'level or up'}  grabs ${hd.grabs}  glitch frames skipped ${hd.glitches}\n` +
    `Depth source: ${hands.some((h) => h.world?.length >= 21) ? 'world landmarks' : 'image only (roll only)'}\n` +
    `Rotation tuning: ${Object.entries(ORIENT_TUNING).map(([k2, v]) => `${k2} ${v}`).join('  ')}\n` +
    `Rub: ${rub.rubbing ? 'RUBBING' : 'idle'}  strokes ${rub.strokes}  in last ${RUB_TUNING.rubWindowMs} ms ${rub.stamps.length}  hand in weapon box ${mark(state.rubIn)}\n` +
    `Rub tuning: ${Object.entries(RUB_TUNING).map(([k2, v]) => `${k2} ${v}`).join('  ')}`;
  $('rubBar').style.width = pct(rub.level);
  const g = state.gate;
  const o = state.gateOutput;
  $('gates').textContent =
    `Current rule (palm ${PALM_SLOWMO_S} s, then slow motion, opens at ${PALM_COMMIT_S} s): ${o.palmPhase}  ${o.palm.toFixed(1)} s\n` +
    `  triggers: ${g.triggers.palm}\n` +
    `Candidate thumbs-up ${THUMB_HOLD_S} s: ${o.thumb.toFixed(1)} s  triggers: ${g.triggers.thumb}\n` +
    `Candidate two open palms above y ${TWO_PALMS_MAX_Y} for ${TWO_PALMS_HOLD_S} s: ${o.two.toFixed(1)} s  triggers: ${g.triggers.two}`;
  $('gatePalm').style.width = pct(o.palm / PALM_COMMIT_S);
  $('gateThumb').style.width = pct(o.thumb / THUMB_HOLD_S);
  $('gateTwo').style.width = pct(o.two / TWO_PALMS_HOLD_S);
  window.benchState = { delegate: state.delegate, quality: state.quality, dropped: stats.dropped, grip: hd.engaged, rubLevel: rub.level, rubStrokes: rub.strokes, hands: hands.length, pose: main?.pose ?? 'none', gesture: main?.gesture ?? '-', fps: stats.fps, markers: state.markers.length, frames: state.frames.length, running: state.running };
}

function onWorkerMessage(ev) {
  const msg = ev.data;
  if (msg.type === 'delegate') { state.delegate = msg.delegate; state.delegateReason = msg.reason; addEvent(`delegate ${msg.delegate}: ${msg.reason}`); return; }
  if (msg.type === 'ready') { state.delegate = msg.delegate ?? 'CPU'; state.delegateReason = msg.reason ?? '-'; state.running = true; state.worker.postMessage({ type: 'hands', count: $('twoHands').checked ? 2 : 1 }); $('startCam').textContent = 'Camera on'; return; }
  if (msg.type === 'error') { state.busy = false; showError('worker', msg); return; }
  if (msg.type !== 'result') return;
  state.busy = false;
  stats.handMs.push(msg.ms);
  stats.runs++;
  readHands(msg.hands, now());
}

async function pump() {
  requestAnimationFrame(pump);
  if (!state.running || video.readyState < 2) return;
  if (state.busy) {
    if (video.currentTime !== stats.seenTime) { stats.seenTime = video.currentTime; stats.dropped++; }
    return;
  }
  if (video.currentTime === state.lastVideoTime) return;
  state.lastVideoTime = video.currentTime;
  stats.seenTime = video.currentTime;
  state.busy = true;
  try {
    const { w, h } = QUALITIES[state.quality].detect;
    // Centre-crop to 4:3 first, so a 16:9 camera keeps hand shapes undistorted.
    const vw = video.videoWidth;
    const vh = video.videoHeight;
    const cropW = Math.min(vw, Math.round(vh * ASPECT));
    const cropH = Math.min(vh, Math.round(vw / ASPECT));
    const bitmap = await createImageBitmap(video, Math.round((vw - cropW) / 2), Math.round((vh - cropH) / 2), cropW, cropH, { resizeWidth: w, resizeHeight: h, resizeQuality: q_RESIZE(w) });
    state.worker.postMessage({ type: 'frame', bitmap, timestamp: performance.now() }, [bitmap]);
  } catch (e) { state.busy = false; showError('frame capture', e); state.running = false; }
}

const q_RESIZE = (w) => (w <= 320 ? 'low' : 'medium');

async function openCamera(q) {
  const stream = await navigator.mediaDevices.getUserMedia({ audio: false, video: { facingMode: 'user', width: { ideal: q.capture.w }, height: { ideal: q.capture.h }, frameRate: { ideal: q.fps } } });
  video.srcObject = stream;
  await video.play();
}

async function start() {
  $('startCam').disabled = true;
  try {
    stopWorker();
    const q = QUALITIES[state.quality];
    await openCamera(q);
    const track = video.srcObject?.getVideoTracks?.()[0];
    const fpsGot = track?.getSettings?.().frameRate;
    state.capture = `${video.videoWidth}x${video.videoHeight}${fpsGot ? ` at ${Math.round(fpsGot)} fps` : ''}`;
    state.detectSent = `${q.detect.w}x${q.detect.h} (4:3 centre crop)`;
    state.delegate = '-'; state.delegateReason = 'loading';
    stats.dropped = 0; stats.handMs.v = []; stats.runs = 0; stats.lastRuns = 0; stats.lastAt = performance.now();
    state.cameraKey = `${track?.label ?? 'camera'}|${video.videoWidth}x${video.videoHeight}`;
    loadTuning($('useDefaults').checked);
    state.worker = new Worker('hand_worker.js');
    state.worker.onmessage = onWorkerMessage;
    state.worker.onerror = (ev) => showError('worker crashed', { name: 'WorkerError', message: ev.message });
    state.worker.postMessage({ type: 'init', options: q.options });
    $('startCam').textContent = 'Loading model';
  } catch (e) {
    showError('start failed', e);
    $('startCam').disabled = false;
  }
}

function stopWorker() {
  state.running = false;
  state.busy = false;
  state.hands = [];
  state.chosen = -1;
  state.lastVideoTime = -1;
  state.worker?.terminate();
  state.worker = null;
  stopStream(video);
}

$('startCam').onclick = start;
$('quality').onchange = () => {
  state.quality = $('quality').value;
  addEvent(`quality ${QUALITIES[state.quality].label}`);
  if (state.worker) start();
};
$('calibratePinch').onclick = () => {
  const c = state.pinchCal;
  Object.assign(c, c.phase === 'idle' ? { phase: 'pinch', since: now(), samples: [], note: '' } : { phase: 'idle', note: 'Cancelled.' });
};
$('record').onclick = () => {
  state.recording = !state.recording;
  $('record').textContent = `Record (${state.recording ? 'on' : 'off'})`;
  $('record').classList.toggle('on', state.recording);
  $('record').setAttribute('aria-pressed', String(state.recording));
  if (state.recording) state.frames = [];
};
$('save').onclick = download;
$('mark').onclick = () => addMarker();
$('markText').addEventListener('keydown', (ev) => { if (ev.key === 'Enter') addMarker(); ev.stopPropagation(); });
window.addEventListener('keydown', (ev) => { if (ev.key.toLowerCase() === 'm' && ev.target.tagName !== 'INPUT') addMarker(); });
$('twoHands').onchange = () => state.worker?.postMessage({ type: 'hands', count: $('twoHands').checked ? 2 : 1 });
$('useDefaults').onchange = () => loadTuning($('useDefaults').checked);
$('resetCounts').onclick = () => {
  state.gate.triggers = { palm: 0, thumb: 0, two: 0 };
  state.flickCount = 0;
  state.rub.reset();
  state.handle.resetObject();
  state.events = [];
  $('log').textContent = '';
};
// Gesture lab. Tests inject frames and time through window.__labFeed, so the lab runs without a camera.
const lab = new LabEngine();
const labClock = { injected: false, t: 0 };
const labNow = () => (labClock.injected ? labClock.t : now());
function labFeed(hands, t) {
  lab.feed(hands.map((h) => ({ gesture: h.gesture, score: h.score, side: h.side, facing: h.facing })), t);
}
window.__labFeed = (hands, t) => { labClock.injected = true; labClock.t = t; labFeed(hands, t); renderLab(); };
window.__lab = lab;
const labMeta = () => ({ mode: QUALITIES[state.quality].label, delegate: state.delegate, delegateReason: state.delegateReason, capture: state.capture, detectSent: state.detectSent, quality: state.quality, twoHands: $('twoHands').checked });
function labDownloadJson() {
  const blob = new Blob([JSON.stringify(lab.toJSON(labMeta()), null, 1)], { type: 'application/json' });
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = `gesture-lab-${new Date().toISOString().replace(/[:.]/g, '-')}.json`;
  a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 2000);
}
function renderLab() {
  const t = labNow();
  lab.tick(t);
  const step = lab.step;
  const rem = lab.remaining(t);
  const attemptsOfStep = lab.attempts.filter((a) => a.step === step.id).length;
  $('labStart').textContent = lab.phase === 'idle' || lab.phase === 'done' ? 'Start lab' : 'Restart lab';
  $('labRetry').disabled = lab.phase !== 'result';
  $('labNext').disabled = lab.phase !== 'result';
  $('labNext').textContent = lab.index + 1 >= LAB_STEPS.length ? 'Finish' : 'Next';
  const running = lab.phase === 'ready' || lab.phase === 'measure';
  $('labStepInfo').textContent = lab.phase === 'idle' || lab.phase === 'done' ? '' : `Step ${lab.index + 1} of ${LAB_STEPS.length}: ${step.id} (${step.kind === 'negative' ? 'must not trigger' : 'must read correctly'}), attempts so far ${attemptsOfStep}`;
  if (lab.phase === 'idle') $('labPrompt').textContent = 'Press Start lab. The camera must be on.';
  else if (lab.phase === 'done') $('labPrompt').textContent = 'Lab complete. Download the JSON or copy the summary.';
  else $('labPrompt').textContent = step.prompt;
  $('labClock').textContent = running ? `${rem.phase === 'ready' ? 'Get ready ' : 'Measuring '}${rem.seconds.toFixed(1)}` : '';
  const card = $('labCard');
  const last = lab.last;
  card.hidden = lab.phase !== 'result' || !last;
  if (!card.hidden) {
    card.className = last.verdict;
    $('labVerdict').textContent = `${last.step} attempt ${last.attempt}: ${last.verdict}`;
    $('labStats').textContent =
      `${last.kind === 'negative' ? 'Trigger frames' : 'Correct frames'}: ${last.hitPct}% of ${last.frames}\n` +
      `Score median ${last.medianScore}, min after 0.5 s ${last.minScore}\n` +
      `Longest correct run: ${last.runFrames} frames, ${last.runSeconds} s\n` +
      `Label changes: ${last.flicker}   Frames with no hand: ${last.noHandFrames} (${last.noHandPct}%)\n` +
      `Other labels: ${last.confusion.length ? last.confusion.map((c) => `${c.label} ${c.pct}%`).join(', ') : 'none'}`;
  }
  const body = $('labTable').tBodies[0];
  body.replaceChildren(...lab.rows().map((r) => {
    const tr = document.createElement('tr');
    const cells = [r.id, r.kind === 'negative' ? 'must not trigger' : 'positive', r.verdict, r.attempts, r.hitPct === null ? '-' : `${r.hitPct}%`, r.kind === 'negative' ? '-' : r.hold === null ? '-' : `${r.hold.toFixed(1)} s`];
    cells.forEach((c, i) => { const td = document.createElement('td'); td.textContent = c; if (i === 2) td.className = r.verdict; tr.append(td); });
    return tr;
  }));
}
$('labStart').onclick = () => { lab.reset(); lab.start(labNow()); $('labNote').textContent = state.running || labClock.injected ? '' : 'The camera is off. Press Start camera first.'; renderLab(); };
$('labRetry').onclick = () => { lab.retry(labNow()); renderLab(); };
$('labNext').onclick = () => { lab.next(labNow()); renderLab(); };
$('labSummary').onclick = () => { if (lab.phase === 'idle' || lab.phase === 'result') lab.showSummary(); renderLab(); };
$('labDownload').onclick = labDownloadJson;
$('labCopy').onclick = async () => {
  const text = lab.text(labMeta());
  try { await navigator.clipboard.writeText(text); $('labNote').textContent = 'Summary copied.'; }
  catch (e) { $('labNote').textContent = `Copy blocked (${e?.message ?? e}). Select the text below.\n${text}`; }
};
setInterval(renderLab, 100);
setInterval(render, 100);
requestAnimationFrame(draw);
requestAnimationFrame(pump);
const params = new URLSearchParams(location.search);
if (QUALITIES[params.get('quality')]) { state.quality = params.get('quality'); $('quality').value = state.quality; }
if (params.has('autostart')) start();
