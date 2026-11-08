// Sends camera frames to a worker that runs MediaPipe on the CPU, then publishes one packed string for Godot.
import { RollingAvg, OneEuro } from './js/filters.js';
import { startStream, CAPTURE_SIZES } from './js/camera.js';
import { GestureEngine, palmCentre } from './gestures.js';
import { Hologram } from './hologram.js';

// Single player: one hand drives the game, so only one slot is ever published.
const SLOT_COUNT = 1;
const LOST_AFTER_MS = 1500;
// Matches the Godot hold time. Within it the tracker follows the hand nearest its last position, past it the nearest hand to the camera wins.
const STICKY_MS = 500;
// A worker that returns nothing for this long is stuck. The page replaces it.
const WORKER_STALL_MS = 4000;
// A camera that delivers no new frame for this long gets a play() nudge, then a fresh stream.
const VIDEO_STALL_MS = 3000;
// The log keeps the newest entries only, so a long session never grows it.
const LOG_MAX_SAMPLES = 600;
const LOG_MAX_EVENTS = 200;
const FIST_MIN_SCORE = 0.3;
const PALM_MIN_SCORE = 0.5;
// Between a fist (all fingertips closer to the wrist than their middle joint) and a spread hand, no gesture counts.
const PALM_MIN_RATIO = 1.3;
const LOG_INTERVAL_MS = 1000;
const FRAME_WIDTH = 320;
const FRAME_HEIGHT = 240;
const WRIST = 0;
const INDEX_MCP = 5;
const INDEX_PIP = 6;
const INDEX_TIP = 8;
const MIDDLE_MCP = 9;
const PINKY_MCP = 17;
// The aim runs from the index knuckle through the fingertip, extended. The knuckle barely moves when the hand
// closes, so a fist or open palm does not drag the aim away from the target. The extension stays small because Godot
// multiplies the offset by the air-trackpad gain, and a long ray lets finger tilt outweigh hand movement.
const AIM_RAY_EXTENSION = 0.5;
// Index tip farther from the wrist than the middle joint by this ratio means the finger points out.
const INDEX_EXTENDED_RATIO = 1.1;
// Share of a new ray direction taken per detection, so a changing finger pose bends the aim instead of jumping it.
const RAY_BLEND = 0.35;
const ACTION_NONE = 0;
const ACTION_PALM = 1;
const ACTION_FIST = 2;
const ACTION_NAMES = ['-', 'palm', 'fist'];
// Fingertip and PIP joint of index, middle, ring and pinky.
const FINGER_JOINTS = [[8, 6], [12, 10], [16, 14], [20, 18]];

// Godot reads only `seq` every frame, and parses `packed` when seq changes.
// The Godot side writes its own numbers back once per readout interval.
const bridge = {
  seq: 0, packed: '', magic: false, godotSeenSeq: -1, godotFps: 0, godotFrameMs: 0, godotShots: 0,
  cameraKey: '', godotCalibrating: false, godotFlow: '', godotHero: '', godotHearts: 0, visibleHands: 0, debugOn: false, godotAudio: 0, godotStepMax: 0, godotStepMean: 0, godotZombies: 0, godotHits: 0, godotAssist: 0, godotAimX: 0, godotAimY: 0, godotAssistX: 0, godotAssistY: 0, godotGrenadeCd: 0, godotPunchCd: 0,
  steerMode: 'flick', twoHands: false, twoPalms: false, hologramOn: true, gestureCount: 0, flickFps: 0,
  handCount: 0, trackOk: false, gesture: '-', score: 0, action: '-', fistRatio: 0, palmRatio: 0,
};
window.railsBridge = bridge;

const $ = (id) => document.getElementById(id);
const video = $('cam');
const slots = Array.from({ length: SLOT_COUNT }, () => ({ ray: null }));
const stats = { handMs: new RollingAvg(30), roundTripMs: new RollingAvg(30), runs: 0, fps: 0, lastRuns: 0, lastAt: performance.now() };
const diag = { handHits: 0, handRuns: 0, sent: 0, dropped: 0, restarts: 0 };
const log = { startedAt: new Date().toISOString(), samples: [], events: [] };
let worker = null;
let lastHandAt = 0;
let lastVideoMoveAt = 0;
let lastResultAt = 0;
let restartingWorker = false;
let lastVideoTime = -1;
let running = false;
let busy = false;
let starting = false;
let sentAt = 0;
let latest = { n: 0, ok: false, s: [], f: 0, t: 0, gn: 0, gk: '', sl: -1, th: null, sr: 0 };
let frameId = 0;
let lastChosen = null;
let lastChosenAt = 0;
const gestures = new GestureEngine({ OneEuro });
const holoCanvas = $('holo');
const hologram = holoCanvas ? new Hologram(holoCanvas) : null;
let lastFlickAt = 0;

function logEvent(type, data = {}) {
  log.events.push({ t: Math.round(performance.now()), type, ...data });
  if (log.events.length > LOG_MAX_EVENTS) log.events.shift();
}
function showError(label, e) {
  const box = $('err');
  box.style.display = 'block';
  box.textContent += `${label}: ${e?.name ?? ''} ${e?.message ?? e}\n`;
  logEvent('error', { label, name: e?.name, message: e?.message });
}
window.addEventListener('error', (ev) => showError('window error', ev.error ?? ev.message));
window.addEventListener('unhandledrejection', (ev) => showError('unhandled rejection', ev.reason));

// Per-player values that calibration replaces. The defaults apply until the recognition test measures the player.
const tuning = { fistScore: FIST_MIN_SCORE, fistRatio: 1.0, palmScore: PALM_MIN_SCORE, palmRatio: PALM_MIN_RATIO };

// Tip-to-middle-joint reach ratio per finger, measured from the wrist. Above 1 the finger points out, below 1 it curls.
function fingerRatios(points) {
  const wrist = points[WRIST];
  const reach = (i) => Math.hypot(points[i][0] - wrist[0], points[i][1] - wrist[1]);
  return FINGER_JOINTS.map(([tip, pip]) => reach(tip) / reach(pip));
}

// Palm size as a share of frame height. The frame is 4:3, so x distances are scaled by the aspect ratio.
function palmSize(points) {
  const dx = (points[WRIST][0] - points[MIDDLE_MCP][0]) * (FRAME_WIDTH / FRAME_HEIGHT);
  return Math.hypot(dx, points[WRIST][1] - points[MIDDLE_MCP][1]);
}

// A fist is the largest ratio below the limit (every finger curled). A palm is the smallest ratio above it (every finger out).
// The model label counts too, so either signal alone can trigger the action.
function classifyAction(hand, ratios) {
  const fist = (hand.gesture === 'Closed_Fist' && hand.score >= tuning.fistScore) || Math.max(...ratios) < tuning.fistRatio;
  if (fist) return ACTION_FIST;
  const palm = (hand.gesture === 'Open_Palm' && hand.score >= tuning.palmScore) || Math.min(...ratios) > tuning.palmRatio;
  return palm ? ACTION_PALM : ACTION_NONE;
}

// Either hand can play, so a tired player can switch. MediaPipe's handedness label misfires on a single hand, so it plays no part here.
// While a hand is tracked, the one nearest its last position wins, so crossing hands never swap the cursor.
// With no lock, the hand nearest the camera (largest palm) wins, because the resting hand sits farther back.
function chooseHand(found, now) {
  if (found.length === 0) return null;
  if (found.length === 1) return found[0];
  if (lastChosen && now - lastChosenAt < STICKY_MS) {
    const distance = (hand) => Math.hypot(hand.knuckleX - lastChosen.knuckleX, hand.knuckleY - lastChosen.knuckleY);
    return found.reduce((best, hand) => (distance(hand) < distance(best) ? hand : best));
  }
  return found.reduce((best, hand) => (hand.size > best.size ? hand : best));
}

// Cross product of the wrist-to-index and wrist-to-pinky directions, signed by MediaPipe's handedness label.
// Recordings show a palm held to the camera reads negative on both hands, and the back of the hand reads positive.
function facing(points, side) {
  const [wx, wy] = points[WRIST];
  const cross = (points[INDEX_MCP][0] - wx) * (points[PINKY_MCP][1] - wy) - (points[INDEX_MCP][1] - wy) * (points[PINKY_MCP][0] - wx);
  return cross * (side === 'Left' ? -1 : 1);
}

// The inspect trigger. Two hands are far less likely than one to show open palms by accident while steering,
// and the facing check rejects the backs of the hands.
function twoPalmsUp(hands) {
  if (hands.length < 2) return false;
  return hands.slice(0, 2).every((h) => h.gesture === 'Open_Palm' && h.score >= PALM_MIN_SCORE && facing(h.points, h.side) < 0);
}

// The preview is mirrored, so flip x.
// The output is the raw aim point and the action. Godot applies the gain first and smooths after it.
function readHands(hands, now) {
  const visible = hands.map((hand) => {
    const ratios = fingerRatios(hand.points);
    const knuckle = hand.points[INDEX_MCP];
    const tip = hand.points[INDEX_TIP];
    return {
      knuckleX: 1 - knuckle[0], knuckleY: knuckle[1], rayX: -(tip[0] - knuckle[0]), rayY: tip[1] - knuckle[1],
      indexOut: ratios[0] > INDEX_EXTENDED_RATIO, action: classifyAction(hand, ratios),
      fistRatio: Math.max(...ratios), palmRatio: Math.min(...ratios),
      size: palmSize(hand.points), gesture: hand.gesture, score: hand.score,
      palmX: 1 - palmCentre(hand.points)[0], palmY: palmCentre(hand.points)[1],
    };
  });
  const chosen = chooseHand(visible, now);
  if (chosen) { lastChosen = chosen; lastChosenAt = now; }
  const found = chosen ? [chosen] : [];
  bridge.visibleHands = visible.length;
  const twoPalms = twoPalmsUp(hands);
  bridge.twoPalms = twoPalms;
  const out = [];
  for (let i = 0; i < SLOT_COUNT; i++) {
    const hand = found[i];
    const slot = slots[i];
    if (!hand) { slot.ray = null; out.push([0.5, 0.5, ACTION_NONE]); continue; }
    // The ray changes only while the finger points and no action pose is held, so closing or opening the hand freezes the aim direction.
    if (!slot.ray) {
      slot.ray = hand.indexOut ? [hand.rayX, hand.rayY] : [0, 0];
    } else if (hand.indexOut && hand.action === ACTION_NONE) {
      slot.ray = [slot.ray[0] + (hand.rayX - slot.ray[0]) * RAY_BLEND, slot.ray[1] + (hand.rayY - slot.ray[1]) * RAY_BLEND];
    }
    const aimX = hand.knuckleX + slot.ray[0] * AIM_RAY_EXTENSION;
    const aimY = hand.knuckleY + slot.ray[1] * AIM_RAY_EXTENSION;
    out.push([+aimX.toFixed(4), +aimY.toFixed(4), hand.action]);
  }
  const first = found[0];
  bridge.handCount = found.length;
  bridge.gesture = first?.gesture ?? '-';
  bridge.score = first?.score ?? 0;
  bridge.action = ACTION_NAMES[first?.action ?? ACTION_NONE];
  bridge.fistRatio = first?.fistRatio ?? 0;
  bridge.palmRatio = first?.palmRatio ?? 0;
  const flick = gestures.update(visible.map((h) => ({ x: h.palmX, y: h.palmY, size: h.size })), chosen ? visible.indexOf(chosen) : -1, now, { twoHands: bridge.twoHands });
  if (flick) { lastFlickAt = now; hologram?.flick(flick, now); }
  hologram?.setHands(hands, now);
  if (gestures.th) hologram?.setMode(gestures.scrub.axis ? 'scrub' : 'two', now);
  bridge.gestureCount = gestures.gn;
  const fistScore = first?.gesture === 'Closed_Fist' ? first.score : 0;
  const palmScore = first?.gesture === 'Open_Palm' ? first.score : 0;
  latest = {
    n: found.length, ok: now - lastHandAt < LOST_AFTER_MS || found.length > 0, s: out, f: ++frameId, t: Math.round(now),
    ps: +(first?.size ?? 0).toFixed(4), gs: +fistScore.toFixed(3), fr: +bridge.fistRatio.toFixed(3),
    tp: twoPalms ? 1 : 0, pg: +palmScore.toFixed(3), pr: +bridge.palmRatio.toFixed(3),
    gn: gestures.gn, gk: gestures.gk, sl: +gestures.slideValue.toFixed(4), th: gestures.th, sr: gestures.sr,
  };
  return found.length;
}

// Lets tests feed hands through the real selection code without a camera.
bridge.__test = { feed: (hands, now = performance.now()) => { readHands(hands, now); publish(); } };

// Godot reads this one string whenever seq changes.
function publish() {
  bridge.packed = JSON.stringify({ m: bridge.magic ? 1 : 0, ce: bridge.camError ?? '', ...latest });
  bridge.seq++;
}

bridge.setTuning = (fistScore, fistRatioLimit, palmScore, palmRatioLimit) => {
  Object.assign(tuning, { fistScore, fistRatio: fistRatioLimit, palmScore, palmRatio: palmRatioLimit });
};

bridge.setSteerMode = (mode) => {
  if (mode !== 'flick' && mode !== 'slide') return;
  bridge.steerMode = mode;
  gestures.setSteer(mode);
};
// Two hands cost frame rate, so only the inspect and scrub modes ask for them.
bridge.setTwoHands = (on) => {
  bridge.twoHands = !!on;
  worker?.postMessage({ type: 'hands', count: bridge.twoHands ? 2 : 1 });
};
bridge.setHologram = (on) => {
  bridge.hologramOn = !!on;
  hologram?.setEnabled(bridge.hologramOn);
};
bridge.setGestureTuning = (t) => gestures.setTuning(t);

// Magic hands is the camera control toggle. Touch and mouse aim stay on either way.
bridge.setMagic = (on) => {
  bridge.magic = !!on;
  if (on) bridge.camError = '';
  video.style.opacity = bridge.magic ? '1' : '0';
  if (bridge.magic && !worker && !starting) start();
  publish();
};

function onWorkerMessage(ev) {
  const msg = ev.data;
  if (msg.type === 'ready') { running = true; lastResultAt = performance.now(); worker.postMessage({ type: 'hands', count: bridge.twoHands ? 2 : 1 }); hologram?.start(); $('startCam').textContent = 'Camera on'; logEvent('worker-ready'); return; }
  if (msg.type === 'error') { busy = false; showError('worker', msg); return; }
  if (msg.type !== 'result') return;
  const now = performance.now();
  lastResultAt = now;
  busy = false;
  stats.handMs.push(msg.ms);
  stats.roundTripMs.push(now - sentAt);
  stats.runs++;
  diag.handRuns++;
  if (readHands(msg.hands, now) > 0) { diag.handHits++; lastHandAt = now; }
  bridge.trackOk = now - lastHandAt < LOST_AFTER_MS;
  publish();
}

// Detect only when the previous result has returned. A busy worker drops the frame instead of queueing it.
async function pump() {
  requestAnimationFrame(pump);
  if (!bridge.magic || !running || video.readyState < 2) return;
  if (video.currentTime === lastVideoTime) return;
  lastVideoTime = video.currentTime;
  lastVideoMoveAt = performance.now();
  if (busy) { diag.dropped++; return; }
  busy = true;
  sentAt = performance.now();
  try {
    const bitmap = await createImageBitmap(video, { resizeWidth: FRAME_WIDTH, resizeHeight: FRAME_HEIGHT, resizeQuality: 'low' });
    diag.sent++;
    worker.postMessage({ type: 'frame', bitmap, timestamp: sentAt }, [bitmap]);
  } catch (e) {
    // One failed capture must not end tracking for the session. The next frame tries again.
    busy = false;
    logEvent('capture-error', { name: e?.name, message: e?.message });
  }
}

// A worker that stops answering leaves `busy` set for good, so every later frame drops and the hand never moves.
// Replace it, because MediaPipe cannot recover from inside.
function restartWorker(reason) {
  if (restartingWorker || !bridge.magic) return;
  restartingWorker = true;
  diag.restarts++;
  logEvent('worker-restart', { reason });
  running = false;
  busy = false;
  worker?.terminate();
  worker = new Worker('hand_worker.js');
  worker.onmessage = onWorkerMessage;
  worker.onerror = (ev) => { logEvent('worker-crash', { message: ev.message }); restartingWorker = false; restartWorker('crash'); };
  worker.postMessage({ type: 'init' });
  lastResultAt = performance.now();
  restartingWorker = false;
}

function watchdog() {
  if (!bridge.magic || !worker) return;
  const now = performance.now();
  if (running && busy && now - sentAt > WORKER_STALL_MS) { restartWorker('no result'); return; }
  if (!running && lastResultAt && now - lastResultAt > WORKER_STALL_MS * 5) { restartWorker('init stalled'); return; }
  // A frozen preview (camera slept, tab throttled) needs a nudge, or nothing reaches the worker.
  if (running && lastVideoMoveAt && now - lastVideoMoveAt > VIDEO_STALL_MS && video.paused) video.play().catch(() => {});
}
setInterval(watchdog, 1000);

function updateReadout() {
  const now = performance.now();
  stats.fps = (stats.runs - stats.lastRuns) / ((now - stats.lastAt) / 1000);
  stats.lastRuns = stats.runs; stats.lastAt = now;
  $('hud').style.visibility = bridge.godotCalibrating || !bridge.debugOn ? 'hidden' : 'visible';
  $('hud').textContent =
    `Godot fps ${bridge.godotFps.toFixed(0)} (${bridge.godotFrameMs.toFixed(1)} ms)  shots ${bridge.godotShots} hits ${bridge.godotHits}  zombies ${bridge.godotZombies} assist ${bridge.godotAssist}  audio ${bridge.godotAudio}  step max ${bridge.godotStepMax.toFixed(1)} mean ${bridge.godotStepMean.toFixed(1)}px\n` +
    `Tracking fps ${stats.fps.toFixed(1)}  worker ms ${stats.handMs.avg.toFixed(0)}  hands ${bridge.visibleHands}  restarts ${diag.restarts}\n` +
    `Gesture ${bridge.gesture} ${bridge.score.toFixed(2)}  action ${bridge.action}  fist ratio ${bridge.fistRatio.toFixed(2)} palm ratio ${bridge.palmRatio.toFixed(2)}\n` +
    `Grenade cooldown ${bridge.godotGrenadeCd.toFixed(1)}s  melee cooldown ${bridge.godotPunchCd.toFixed(1)}s\n` +
    `Hits ${diag.handHits}/${diag.handRuns}  dropped ${diag.dropped}  Godot saw seq ${bridge.godotSeenSeq}/${bridge.seq}`;
}

setInterval(updateReadout, 250);
setInterval(() => {
  if (!running) return;
  log.samples.push({
    t: Math.round(performance.now()), godotFps: bridge.godotFps, trackFps: +stats.fps.toFixed(1),
    workerMs: +stats.handMs.avg.toFixed(1), roundTripMs: +stats.roundTripMs.avg.toFixed(1), trackOk: bridge.trackOk,
    handCount: bridge.handCount, gesture: bridge.gesture, score: +bridge.score.toFixed(2), action: bridge.action,
    godotShots: bridge.godotShots, handHits: diag.handHits, dropped: diag.dropped,
    godotSeenSeq: bridge.godotSeenSeq, seq: bridge.seq,
  });
  if (log.samples.length > LOG_MAX_SAMPLES) log.samples.shift();
}, LOG_INTERVAL_MS);

async function start() {
  starting = true;
  $('startCam').disabled = true;
  try {
    await startStream(video, 'user', CAPTURE_SIZES[0]);
    const track = video.srcObject?.getVideoTracks?.()[0];
    bridge.cameraKey = `${track?.label ?? 'camera'}|${video.videoWidth}x${video.videoHeight}`;
    publish();
    worker = new Worker('hand_worker.js');
    worker.onmessage = onWorkerMessage;
    worker.onerror = (ev) => showError('worker crashed', { name: 'WorkerError', message: ev.message });
    worker.postMessage({ type: 'init' });
    lastResultAt = performance.now();
    video.srcObject?.getVideoTracks?.()[0]?.addEventListener('ended', () => logEvent('camera-ended'));
    $('startCam').textContent = 'Loading model';
    logEvent('camera-open', { w: video.videoWidth, h: video.videoHeight });
  } catch (e) {
    showError('start failed', e);
    $('startCam').disabled = false;
    bridge.camError = e?.name ?? 'Error';
    bridge.magic = false;
    video.style.opacity = '0';
    publish();
  }
  starting = false;
}

$('startCam').onclick = () => bridge.setMagic(true);
$('dlLog').onclick = () => {
  const blob = new Blob([JSON.stringify({ ...log, userAgent: navigator.userAgent, screen: `${screen.width}x${screen.height}`, dpr: devicePixelRatio }, null, 1)], { type: 'application/json' });
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = `rails-log-${Date.now()}.json`;
  a.click();
};
requestAnimationFrame(pump);
