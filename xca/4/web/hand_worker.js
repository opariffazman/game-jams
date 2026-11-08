// Runs the MediaPipe gesture recognizer off the main thread, so Godot keeps rendering while it detects.
// Classic worker: the module bundle cannot be loaded here on every Chrome, the classic one can.
importScripts(new URL('./vendor/vision_bundle_classic.js', self.location.href).href);

const WASM_DIR = new URL('./vendor/wasm', self.location.href).href;
const MODEL = new URL('./models/gesture_recognizer.task', self.location.href).href;

let recognizer = null;
let lastTimestamp = 0;
let activeDelegate = 'CPU';
let delegateReason = 'default';
let firstFrameDone = false;
let initOptions = {};

function build(files, delegate, options) {
  return Vision.GestureRecognizer.createFromOptions(files, {
    baseOptions: { modelAssetPath: MODEL, delegate },
    runningMode: 'VIDEO',
    numHands: options.numHands ?? 1,
    ...(options.minHandDetectionConfidence !== undefined && { minHandDetectionConfidence: options.minHandDetectionConfidence }),
    ...(options.minHandPresenceConfidence !== undefined && { minHandPresenceConfidence: options.minHandPresenceConfidence }),
    ...(options.minTrackingConfidence !== undefined && { minTrackingConfidence: options.minTrackingConfidence }),
  });
}

// No options keeps the game's behaviour: CPU, one hand. A GPU request falls back to CPU when creation throws.
async function init(options = {}) {
  initOptions = options;
  const files = await Vision.FilesetResolver.forVisionTasks(WASM_DIR);
  firstFrameDone = false;
  if (options.delegate === 'GPU') {
    try {
      recognizer = await build(files, 'GPU', options);
      activeDelegate = 'GPU';
      delegateReason = 'GPU requested and created';
      return;
    } catch (e) {
      delegateReason = `GPU create failed (${e?.name ?? 'Error'}: ${e?.message ?? e}), using CPU`;
    }
  } else {
    delegateReason = 'CPU requested';
  }
  recognizer = await build(files, 'CPU', options);
  activeDelegate = 'CPU';
}

// The GPU delegate can create fine and still return nothing on some drivers. The first frame decides.
async function fallBackToCpu(why) {
  const files = await Vision.FilesetResolver.forVisionTasks(WASM_DIR);
  recognizer = await build(files, 'CPU', initOptions);
  activeDelegate = 'CPU';
  delegateReason = why;
  firstFrameDone = true;
  lastTimestamp = 0;
}

// Only the fields the page needs are copied, so the reply stays small.
function summarise(res) {
  return (res.landmarks ?? []).map((points, i) => {
    const gesture = res.gestures?.[i]?.[0];
    return {
      points: points.map((p) => [p.x, p.y]),
      gesture: gesture?.categoryName ?? 'None',
      score: gesture?.score ?? 0,
      side: res.handedness?.[i]?.[0]?.categoryName ?? '',
      world: (res.worldLandmarks?.[i] ?? []).map((p) => [p.x, p.y, p.z]),
    };
  });
}

self.onmessage = async (ev) => {
  const { type, bitmap, timestamp } = ev.data;
  if (type === 'init') {
    try {
      await init(ev.data.options ?? {});
      self.postMessage({ type: 'ready', delegate: activeDelegate, reason: delegateReason });
    } catch (e) {
      self.postMessage({ type: 'error', name: e?.name, message: e?.message ?? String(e) });
    }
    return;
  }
  if (type === 'hands') {
    // One hand is cheaper per frame. The page asks for two only while a two-hand mode runs.
    await recognizer?.setOptions({ numHands: ev.data.count });
    return;
  }
  if (type !== 'frame') return;
  try {
    const t0 = performance.now();
    // MediaPipe needs strictly increasing timestamps in VIDEO mode.
    lastTimestamp = Math.max(timestamp, lastTimestamp + 1);
    let res;
    try {
      res = recognizer.recognizeForVideo(bitmap, lastTimestamp);
    } catch (e) {
      if (activeDelegate !== 'GPU' || firstFrameDone) throw e;
      await fallBackToCpu(`GPU first frame threw (${e?.name ?? 'Error'}: ${e?.message ?? e}), using CPU`);
      self.postMessage({ type: 'delegate', delegate: activeDelegate, reason: delegateReason });
      res = recognizer.recognizeForVideo(bitmap, lastTimestamp + 1);
    }
    firstFrameDone = true;
    self.postMessage({ type: 'result', hands: summarise(res), ms: performance.now() - t0, timestamp, delegate: activeDelegate });
  } catch (e) {
    self.postMessage({ type: 'error', name: e?.name, message: e?.message ?? String(e) });
  } finally {
    // A thrown frame would otherwise keep its bitmap alive for good.
    bitmap.close();
  }
};
