// Turns palm positions into flick, slide, two-hand and scrub signals. No DOM access, so Node tests run it directly.
// Distances are in palm sizes, so the same gesture reads the same near the camera and far from it.
const ASPECT = 4 / 3;
const PALM_MIN = 0.1;
const PALM_MAX = 0.35;

export const DEFAULT_TUNING = {
  // A flick must cover this many palm sizes within windowMs. Vertical needs more, because tilting the hand fakes vertical motion.
  flickH: 1.7, flickV: 2.0, windowMs: 330,
  // The hand must also cover this share of the threshold between two samples at most compactMs apart.
  compactShare: 0.6, compactMs: 270,
  // After a flick nothing triggers for lockMs. The opposite direction waits for the hand to settle, but never longer than returnMs.
  lockMs: 350, returnMs: 1500, settleMs: 400, settlePath: 0.5,
  // Slide maps the palm x range [slideMin, slideMax] to 0..1. The position holds for slideHoldMs without a hand.
  slideMin: 0.2, slideMax: 0.8, slideHoldMs: 400,
  // Scrub: a reversal needs this many palm sizes of travel. The other hand must stay within holdPalms and move under 1/moverRatio of the mover over scrubWindowMs. A real rub drifts the still hand, so the limits are loose.
  scrubAmp: 0.25, holdPalms: 0.8, moverPalms: 0.5, moverRatio: 2, scrubWindowMs: 900,
};

const clampPalm = (size) => Math.min(PALM_MAX, Math.max(PALM_MIN, size));

// Mean of the wrist and the four knuckles. It stays put when fingers curl, unlike the fingertips.
export function palmCentre(points) {
  const ids = [0, 5, 9, 13, 17];
  let x = 0, y = 0;
  for (const i of ids) { x += points[i][0]; y += points[i][1]; }
  return [x / ids.length, y / ids.length];
}

export class GestureEngine {
  // OneEuro comes from the caller, because the page and Node load it from different paths.
  constructor({ OneEuro, tuning = {} } = {}) {
    this.tuning = { ...DEFAULT_TUNING, ...tuning };
    this.OneEuro = OneEuro;
    this.steer = 'flick';
    this.gn = 0;
    this.gk = '';
    this.reset();
  }

  setTuning(tuning) { Object.assign(this.tuning, tuning); }

  setSteer(mode) { this.steer = mode === 'slide' ? 'slide' : 'flick'; }

  reset() {
    this.hist = [];
    this.lockUntil = 0;
    this.blocked = '';
    this.blockedUntil = 0;
    this.settled = true;
    this.slideAt = -1e9;
    this.slideValue = -1;
    this.slideFilter = this.OneEuro ? new this.OneEuro({ minCutoff: 1.5, beta: 0.05 }) : null;
    this.tracks = [null, null];
    this.scrub = { count: 0, axis: null, dir: 0, extreme: 0, travel: 0 };
    this.th = null;
    this.thFilters = null;
    this.sr = 0;
  }

  // hands: [{ x, y, size }] with x mirrored, in frame shares. primary is the index of the playing hand, or -1.
  // Returns the flick direction ('l','r','u','d') or ''.
  update(hands, primary, t, { twoHands = false } = {}) {
    const flick = this._flickStep(hands[primary], t);
    this._slideStep(hands[primary], t);
    this._twoHandStep(hands, t, twoHands);
    return flick;
  }

  _flickStep(hand, t) {
    const k = this.tuning;
    if (!hand) { this._prune(t); return ''; }
    const cur = { t, x: hand.x * ASPECT, y: hand.y, size: clampPalm(hand.size) };
    this.hist.push(cur);
    this._prune(t);
    if (t < this.lockUntil) return '';
    if (!this.settled && this._isSettled()) this.settled = true;
    const size = this.hist.reduce((sum, s) => sum + s.size, 0) / this.hist.length;
    let best = null;
    let peak = 0;
    for (let i = 0; i < this.hist.length - 1; i++) {
      const from = this.hist[i];
      const nx = (cur.x - from.x) / size;
      const ny = (cur.y - from.y) / size;
      const sh = Math.abs(nx) / k.flickH;
      const sv = Math.abs(ny) / k.flickV;
      const score = Math.max(sh, sv);
      if (score > (best?.score ?? 0)) best = { score, horizontal: sh >= sv, nx, ny };
    }
    if (!best || best.score < 1) return '';
    const horizontal = best.horizontal;
    const share = k.compactShare * (horizontal ? k.flickH : k.flickV);
    for (let i = 0; i < this.hist.length - 1; i++) {
      const from = this.hist[i];
      if (cur.t - from.t > k.compactMs) continue;
      const d = horizontal ? Math.abs(cur.x - from.x) : Math.abs(cur.y - from.y);
      peak = Math.max(peak, d / size);
    }
    if (peak < share) return '';
    const dir = horizontal ? (best.nx > 0 ? 'r' : 'l') : (best.ny > 0 ? 'd' : 'u');
    if (dir === this.blocked && !this.settled && t < this.blockedUntil) return '';
    if (this.steer === 'slide' && horizontal) return '';
    this.lockUntil = t + k.lockMs;
    this.blocked = { l: 'r', r: 'l', u: 'd', d: 'u' }[dir];
    this.blockedUntil = t + k.returnMs;
    this.settled = false;
    this.hist = [cur];
    this.gn++;
    this.gk = dir;
    return dir;
  }

  _prune(t) {
    const cut = t - this.tuning.windowMs;
    while (this.hist.length > 1 && this.hist[0].t < cut) this.hist.shift();
    if (this.hist.length === 1 && this.hist[0].t < cut) this.hist.length = 0;
  }

  // Settled: the last samples spanning settleMs moved less than settlePath palm sizes in total.
  _isSettled() {
    const k = this.tuning;
    const h = this.hist;
    if (h.length < 2) return false;
    const last = h[h.length - 1];
    let path = 0;
    let i = h.length - 1;
    while (i > 0 && last.t - h[i - 1].t <= k.settleMs * 1.6) {
      path += Math.hypot(h[i].x - h[i - 1].x, h[i].y - h[i - 1].y) / last.size;
      i--;
    }
    return last.t - h[i].t >= k.settleMs && path < k.settlePath;
  }

  _slideStep(hand, t) {
    const k = this.tuning;
    if (hand) {
      const raw = Math.min(1, Math.max(0, (hand.x - k.slideMin) / (k.slideMax - k.slideMin)));
      this.slideValue = this.slideFilter ? this.slideFilter.filter(raw, t) : raw;
      this.slideAt = t;
    } else if (t - this.slideAt > k.slideHoldMs) {
      this.slideValue = -1;
      this.slideFilter?.reset();
    }
  }

  _twoHandStep(hands, t, enabled) {
    if (!enabled || hands.length < 2) {
      this.th = null;
      this.thFilters = null;
      this.tracks = [null, null];
      this.scrub.axis = null;
      return;
    }
    const sorted = [...hands].sort((a, b) => a.x - b.x);
    const [a, b] = sorted;
    const dx = (b.x - a.x) * ASPECT;
    const dy = b.y - a.y;
    const raw = [Math.hypot(dx, dy), Math.atan2(dy, dx), (a.x + b.x) / 2, (a.y + b.y) / 2];
    if (!this.thFilters && this.OneEuro) this.thFilters = raw.map(() => new this.OneEuro({ minCutoff: 2.5, beta: 0.3 }));
    this.th = this.thFilters ? raw.map((v, i) => +this.thFilters[i].filter(v, t).toFixed(4)) : raw.map((v) => +v.toFixed(4));
    this._scrubStep(sorted, t);
  }

  // Keeps each hand's identity by nearest position, so crossing hands do not swap the holder and the mover.
  _scrubStep(pair, t) {
    const k = this.tuning;
    const spot = (h) => ({ t, x: h.x * ASPECT, y: h.y, size: clampPalm(h.size) });
    let [p, q] = pair.map(spot);
    const [t0, t1] = this.tracks;
    if (t0 && t1) {
      const last0 = t0[t0.length - 1];
      const last1 = t1[t1.length - 1];
      const keep = Math.hypot(p.x - last0.x, p.y - last0.y) + Math.hypot(q.x - last1.x, q.y - last1.y);
      const swap = Math.hypot(q.x - last0.x, q.y - last0.y) + Math.hypot(p.x - last1.x, p.y - last1.y);
      if (swap < keep) [p, q] = [q, p];
    }
    this.tracks = [(t0 ?? []).concat(p), (t1 ?? []).concat(q)].map((tr) => tr.filter((s) => t - s.t <= k.scrubWindowMs));
    const travel = (tr) => {
      if (tr.length < 2) return 0;
      let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
      for (const s of tr) { minX = Math.min(minX, s.x); maxX = Math.max(maxX, s.x); minY = Math.min(minY, s.y); maxY = Math.max(maxY, s.y); }
      return Math.max(maxX - minX, maxY - minY) / tr[tr.length - 1].size;
    };
    const travels = this.tracks.map(travel);
    const holder = travels[0] <= travels[1] ? 0 : 1;
    const mover = 1 - holder;
    const scrubbing = this.tracks[holder].length >= 3 && travels[holder] < k.holdPalms && travels[mover] > k.moverPalms && travels[mover] >= k.moverRatio * travels[holder];
    if (!scrubbing) { this.scrub.axis = null; return; }
    const tr = this.tracks[mover];
    const cur = tr[tr.length - 1];
    const s = this.scrub;
    // The axis with the larger travel carries the stroke, so a diagonal scrub counts each reversal once.
    const rangeOf = (axis) => Math.max(...tr.map((v) => v[axis])) - Math.min(...tr.map((v) => v[axis]));
    const axis = rangeOf('x') >= rangeOf('y') ? 'x' : 'y';
    if (s.axis !== axis) { s.axis = axis; s.dir = 0; s.extreme = cur[axis]; return; }
    const v = cur[axis];
    const amp = k.scrubAmp * cur.size;
    if (s.dir === 0) {
      if (Math.abs(v - s.extreme) >= amp) { s.dir = Math.sign(v - s.extreme); s.extreme = v; }
      return;
    }
    if (s.dir > 0) {
      if (v > s.extreme) s.extreme = v;
      else if (s.extreme - v >= amp) { s.dir = -1; s.extreme = v; this.sr++; }
    } else if (v < s.extreme) s.extreme = v;
    else if (v - s.extreme >= amp) { s.dir = 1; s.extreme = v; this.sr++; }
  }
}
