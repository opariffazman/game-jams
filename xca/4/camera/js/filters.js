// One Euro filter (Casiez et al. 2012). Smooths hard when still, follows fast when moving.
class LowPass {
  constructor() { this.y = null; }
  filter(x, alpha) {
    this.y = this.y === null ? x : alpha * x + (1 - alpha) * this.y;
    return this.y;
  }
}

export class OneEuro {
  constructor({ minCutoff = 1.0, beta = 0.05, dCutoff = 1.0 } = {}) {
    this.minCutoff = minCutoff;
    this.beta = beta;
    this.dCutoff = dCutoff;
    this.reset();
  }
  reset() {
    this.x = new LowPass();
    this.dx = new LowPass();
    this.lastT = null;
    this.lastRaw = null;
  }
  static alpha(cutoff, dt) {
    const tau = 1 / (2 * Math.PI * cutoff);
    return 1 / (1 + tau / dt);
  }
  // tMs is a monotonic timestamp in milliseconds.
  filter(value, tMs) {
    if (this.lastT === null) {
      this.lastT = tMs;
      this.lastRaw = value;
      return this.x.filter(value, 1);
    }
    const dt = Math.max((tMs - this.lastT) / 1000, 1e-3);
    this.lastT = tMs;
    const rate = (value - this.lastRaw) / dt;
    this.lastRaw = value;
    const dxHat = this.dx.filter(rate, OneEuro.alpha(this.dCutoff, dt));
    const cutoff = this.minCutoff + this.beta * Math.abs(dxHat);
    return this.x.filter(value, OneEuro.alpha(cutoff, dt));
  }
}

export function applyDeadZone(v, zone) {
  const a = Math.abs(v);
  if (a <= zone) return 0;
  // Rescale so output still reaches +-1 and has no jump at the zone edge.
  return Math.sign(v) * Math.min(1, (a - zone) / (1 - zone));
}

export class RollingAvg {
  constructor(size = 30) { this.size = size; this.v = []; }
  push(x) { this.v.push(x); if (this.v.length > this.size) this.v.shift(); }
  get avg() { return this.v.length ? this.v.reduce((a, b) => a + b, 0) / this.v.length : 0; }
}
