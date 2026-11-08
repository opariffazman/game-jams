// Gesture lab logic. Pure functions and one state machine, no DOM and no camera, so Node tests can run it.
// The page feeds it one array of hands per tracker frame: [{ gesture, score, side, facing }].

export const READY_MS = 1000;
export const MEASURE_MS = 3000;
// Frames before this time are left out of the minimum score, because the hand is still settling.
export const SETTLE_MS = 500;
export const PASS_PCT = 90;
export const WARN_PCT = 70;
export const PASS_MIN_SCORE = 0.6;
export const PASS_MAX_FLICKER = 1;
export const NEGATIVE_PASS_PCT = 5;
// Share of attempts whose unbroken run must reach the reported hold time.
export const HOLD_COVERAGE = 0.95;
// The sign of the facing value when the palm faces the camera. Confirmed by a recording: a palm held to the camera reads about -0.010 on both hands.
export const PALM_SIGN = -1;
export const TRIGGER_LABELS = ['Open_Palm', 'Closed_Fist', 'Victory', 'Thumb_Up', 'Thumb_Down', 'Pointing_Up', 'Two_Fists', 'Two_Palms'];

export const STEPS = [
  { id: 'Open_Palm', kind: 'positive', correct: 'Open_Palm', prompt: 'Show an open palm to the camera for 3 s.' },
  { id: 'Closed_Fist', kind: 'positive', correct: 'Closed_Fist', prompt: 'Make a fist and hold it still for 3 s.' },
  { id: 'Pointing_Up', kind: 'positive', correct: 'Pointing_Up', prompt: 'Point one finger up and hold it for 3 s.' },
  { id: 'Victory', kind: 'positive', correct: 'Victory', prompt: 'Show a V sign with two fingers for 3 s.' },
  { id: 'Thumb_Up', kind: 'positive', correct: 'Thumb_Up', prompt: 'Show a thumbs up for 3 s.' },
  { id: 'Thumb_Down', kind: 'positive', correct: 'Thumb_Down', prompt: 'Show a thumbs down for 3 s.' },
  { id: 'ILoveYou', kind: 'positive', correct: 'ILoveYou', prompt: 'Show thumb, index and pinky out for 3 s.' },
  { id: 'Two_Fists', kind: 'positive', correct: 'Two_Fists', twoHands: true, prompt: 'Hold two fists together in view for 3 s.' },
  { id: 'Two_Palms', kind: 'positive', correct: 'Two_Palms', twoHands: true, prompt: 'Show two open palms to the camera for 3 s.' },
  { id: 'Hang', kind: 'negative', prompt: 'Let one hand hang relaxed in view for 3 s. Make no gesture.' },
  { id: 'Wave', kind: 'negative', prompt: 'Wave one hand side to side for 3 s.' },
  { id: 'Flick', kind: 'negative', prompt: 'Flick one hand left and right, fast, for 3 s.' },
  { id: 'Point_At_Camera', kind: 'negative', prompt: 'Point your index finger at the camera for 3 s.' },
  { id: 'Half_Curl', kind: 'negative', prompt: 'Hold one relaxed, half-curled hand in view for 3 s.' },
];

const normal = (g) => (g && g !== 'None' ? g : 'None');
const bestHand = (hands) => hands.reduce((a, b) => (b.score > a.score ? b : a));

function twoHandLabel(hands, palmSign) {
  if (hands.length === 0) return 'No_Hand';
  if (hands.length === 1) return 'One_Hand';
  const [a, b] = hands;
  const ga = normal(a.gesture);
  const gb = normal(b.gesture);
  if (ga === 'Closed_Fist' && gb === 'Closed_Fist') return 'Two_Fists';
  if (ga === 'Open_Palm' && gb === 'Open_Palm') {
    return Math.sign(a.facing) === palmSign && Math.sign(b.facing) === palmSign ? 'Two_Palms' : 'Two_Backs';
  }
  return `${ga}+${gb}`;
}

// One label per tracker frame. A negative step reports a trigger label whenever any hand shows one.
export function frameLabel(hands, step, palmSign = PALM_SIGN) {
  if (step.twoHands) return twoHandLabel(hands, palmSign);
  if (hands.length === 0) return 'No_Hand';
  if (step.kind === 'negative') {
    const two = hands.length > 1 ? twoHandLabel(hands, palmSign) : '';
    if (TRIGGER_LABELS.includes(two)) return two;
    const hit = hands.find((h) => TRIGGER_LABELS.includes(normal(h.gesture)));
    if (hit) return normal(hit.gesture);
  }
  return normal(bestHand(hands).gesture);
}

const frameScore = (hands) => (hands.length ? Math.min(...hands.map((h) => h.score)) : 0);

function median(values) {
  if (!values.length) return 0;
  const s = [...values].sort((a, b) => a - b);
  const mid = s.length >> 1;
  return s.length % 2 ? s[mid] : (s[mid - 1] + s[mid]) / 2;
}

const round = (v, digits) => +v.toFixed(digits);

// frames: [{ t, label, score, hands }], t in ms from the start of the measured window.
export function evaluate(frames, step) {
  const n = frames.length;
  const isHit = step.kind === 'negative' ? (f) => TRIGGER_LABELS.includes(f.label) : (f) => f.label === step.correct;
  const hits = frames.filter(isHit).length;
  const hitPct = n ? (100 * hits) / n : 0;
  const withHand = frames.filter((f) => f.hands > 0);
  const lateScores = withHand.filter((f) => f.t >= SETTLE_MS).map((f) => f.score);
  const minScore = lateScores.length ? Math.min(...lateScores) : 0;
  let flicker = 0;
  for (let i = 1; i < n; i++) if (frames[i].label !== frames[i - 1].label) flicker++;
  let runFrames = 0;
  let runSeconds = 0;
  let start = -1;
  for (let i = 0; i <= n; i++) {
    if (i < n && isHit(frames[i])) {
      if (start < 0) start = i;
      continue;
    }
    if (start >= 0) {
      const len = i - start;
      if (len > runFrames) { runFrames = len; runSeconds = (frames[i - 1].t - frames[start].t) / 1000; }
      start = -1;
    }
  }
  const counts = {};
  frames.forEach((f) => { if (step.kind === 'negative' || f.label !== step.correct) counts[f.label] = (counts[f.label] ?? 0) + 1; });
  const confusion = Object.entries(counts).map(([label, c]) => ({ label, pct: round((100 * c) / n, 1) })).sort((a, b) => b.pct - a.pct);
  const noHandFrames = frames.filter((f) => f.hands === 0).length;
  let verdict;
  if (step.kind === 'negative') verdict = n && hitPct < NEGATIVE_PASS_PCT ? 'PASS' : 'FAIL';
  else if (hitPct >= PASS_PCT && minScore > PASS_MIN_SCORE && flicker <= PASS_MAX_FLICKER) verdict = 'PASS';
  else verdict = hitPct >= WARN_PCT ? 'WARN' : 'FAIL';
  return {
    kind: step.kind, frames: n, hitPct: round(hitPct, 1), medianScore: round(median(withHand.map((f) => f.score)), 3), minScore: round(minScore, 3),
    runFrames, runSeconds: round(runSeconds, 2), flicker, noHandFrames, noHandPct: n ? round((100 * noHandFrames) / n, 1) : 0, confusion, verdict,
  };
}

const RANK = { PASS: 0, WARN: 1, FAIL: 2 };

// The shortest hold that the unbroken run reaches in at least HOLD_COVERAGE of the attempts, rounded down to 0.1 s.
export function safeHold(runSeconds) {
  if (!runSeconds.length) return 0;
  const sorted = [...runSeconds].sort((a, b) => a - b);
  const index = Math.floor(sorted.length * (1 - HOLD_COVERAGE) + 1e-9);
  return Math.floor(sorted[index] * 10 + 1e-9) / 10;
}

export function summarize(attempts, steps = STEPS) {
  return steps.map((step) => {
    const mine = attempts.filter((a) => a.step === step.id);
    if (!mine.length) return { id: step.id, kind: step.kind, attempts: 0, verdict: 'NOT RUN', hitPct: null, hold: null };
    const verdict = mine.reduce((w, a) => (RANK[a.verdict] > RANK[w] ? a.verdict : w), 'PASS');
    const hitPct = round(mine.reduce((s, a) => s + a.hitPct, 0) / mine.length, 1);
    const hold = step.kind === 'positive' && verdict !== 'FAIL' ? safeHold(mine.map((a) => a.runSeconds)) : null;
    return { id: step.id, kind: step.kind, attempts: mine.length, verdict, hitPct, hold: hold > 0 ? hold : null };
  });
}

export function summaryText(rows, meta = {}) {
  const head = `Gesture lab. Mode: ${meta.mode ?? '-'}. Delegate: ${meta.delegate ?? '-'}. Capture: ${meta.capture ?? '-'}. Detection frame: ${meta.detectSent ?? '-'}.`;
  const lines = rows.map((r) => {
    if (r.verdict === 'NOT RUN') return `${r.id}: not run`;
    if (r.kind === 'negative') return `${r.id} (must not trigger): ${r.verdict}, trigger frames ${r.hitPct}%, ${r.attempts} attempt${r.attempts === 1 ? '' : 's'}`;
    return `${r.id}: ${r.verdict}, ${r.hitPct}% correct, safe hold ${r.hold === null ? 'none' : `${r.hold.toFixed(1)} s`}, ${r.attempts} attempt${r.attempts === 1 ? '' : 's'}`;
  });
  return [head, ...lines].join('\n');
}

export class LabEngine {
  constructor({ steps = STEPS, palmSign = PALM_SIGN } = {}) {
    this.steps = steps;
    this.palmSign = palmSign;
    this.reset();
  }

  reset() {
    this.index = 0;
    this.phase = 'idle';
    this.attempts = [];
    this.frames = [];
    this.raw = [];
    this.readyEnd = 0;
    this.measureEnd = 0;
  }

  get step() { return this.steps[this.index]; }

  get last() { return this.attempts[this.attempts.length - 1] ?? null; }

  start(t) {
    if (this.phase === 'idle' || this.phase === 'done') { this.index = 0; this.phase = 'idle'; this.begin(t); }
  }

  begin(t) {
    this.phase = 'ready';
    this.readyEnd = t + READY_MS;
    this.measureEnd = this.readyEnd + MEASURE_MS;
    this.frames = [];
    this.raw = [];
  }

  next(t) {
    if (this.phase !== 'result') return;
    if (this.index + 1 >= this.steps.length) { this.phase = 'done'; return; }
    this.index++;
    this.begin(t);
  }

  retry(t) {
    if (this.phase === 'result') this.begin(t);
  }

  showSummary() {
    this.frames = [];
    this.raw = [];
    this.phase = 'done';
  }

  tick(t) {
    if (this.phase === 'ready' && t >= this.readyEnd) this.phase = 'measure';
    if (this.phase === 'measure' && t >= this.measureEnd) this.finish();
  }

  feed(hands, t) {
    this.tick(t);
    if (this.phase !== 'measure') return;
    const rel = Math.round(t - this.readyEnd);
    const label = frameLabel(hands, this.step, this.palmSign);
    this.frames.push({ t: rel, label, score: frameScore(hands), hands: hands.length });
    this.raw.push({ t: rel, label, hands: hands.map((h) => ({ gesture: normal(h.gesture), score: round(h.score ?? 0, 3), side: h.side ?? '', facing: round(h.facing ?? 0, 5) })) });
  }

  finish() {
    const step = this.step;
    const stats = evaluate(this.frames, step);
    const number = this.attempts.filter((a) => a.step === step.id).length + 1;
    this.attempts.push({ step: step.id, attempt: number, ...stats, raw: this.raw });
    this.frames = [];
    this.raw = [];
    this.phase = 'result';
  }

  remaining(t) {
    if (this.phase === 'ready') return { phase: 'ready', seconds: Math.max(0, (this.readyEnd - t) / 1000) };
    if (this.phase === 'measure') return { phase: 'measure', seconds: Math.max(0, (this.measureEnd - t) / 1000) };
    return { phase: this.phase, seconds: 0 };
  }

  rows() { return summarize(this.attempts, this.steps); }

  text(meta) { return summaryText(this.rows(), meta); }

  toJSON(meta) {
    return { version: 1, meta, palmSign: this.palmSign, summary: this.rows(), summaryText: this.text(meta), attempts: this.attempts };
  }
}
