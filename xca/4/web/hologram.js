// Draws a hologram over the camera preview: glowing skeleton, palm trails, and a ring pulse with sparks on each flick.
// It reads only landmark data, so the cost per frame stays small and it never touches the game canvas.
const BONES = [
  [0, 1], [1, 2], [2, 3], [3, 4], [0, 5], [5, 6], [6, 7], [7, 8], [5, 9], [9, 10], [10, 11], [11, 12],
  [9, 13], [13, 14], [14, 15], [15, 16], [13, 17], [17, 18], [18, 19], [19, 20], [0, 17],
];
const TINTS = { idle: [80, 220, 255], l: [255, 170, 60], r: [255, 170, 60], u: [120, 255, 140], d: [120, 255, 140], two: [200, 140, 255], scrub: [255, 240, 120] };
const TRAIL_MS = 450;
const PULSE_MS = 600;
const SPARK_MS = 500;
const SPARK_COUNT = 18;
const STREAK = { l: [-1, 0], r: [1, 0], u: [0, -1], d: [0, 1] };

export class Hologram {
  constructor(canvas) {
    this.canvas = canvas;
    this.ctx = canvas.getContext('2d');
    this.enabled = true;
    this.hands = [];
    this.trail = [];
    this.pulses = [];
    this.sparks = [];
    this.tint = 'idle';
    this.tintUntil = 0;
    this.mirrored = true;
    this.running = false;
  }

  setEnabled(on) {
    this.enabled = !!on;
    this.canvas.style.display = this.enabled ? 'block' : 'none';
    if (!this.enabled) this.ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);
  }

  // hands: [{ points: [[x, y]...] }] in raw landmark space. The canvas is mirrored by CSS like the video.
  setHands(hands, t) {
    this.hands = hands;
    const first = hands[0];
    if (first) {
      const c = [(first.points[0][0] + first.points[9][0]) / 2, (first.points[0][1] + first.points[9][1]) / 2];
      this.trail.push({ t, x: c[0], y: c[1] });
    }
    while (this.trail.length && t - this.trail[0].t > TRAIL_MS) this.trail.shift();
  }

  flick(dir, t) {
    const c = this.trail[this.trail.length - 1];
    if (!c) return;
    // draw() prunes these, but it returns early while the hologram is off, so cap them here too.
    if (this.pulses.length > 8) this.pulses.splice(0, this.pulses.length - 8);
    if (this.sparks.length > SPARK_COUNT * 4) this.sparks.splice(0, this.sparks.length - SPARK_COUNT * 4);
    this.tint = dir;
    this.tintUntil = t + 500;
    this.pulses.push({ t, x: c.x, y: c.y, dir });
    const [dx, dy] = STREAK[dir];
    for (let i = 0; i < SPARK_COUNT; i++) {
      const spread = (Math.random() - 0.5) * 1.2;
      const speed = 0.25 + Math.random() * 0.5;
      const angle = Math.atan2(dy, dx) + spread;
      this.sparks.push({ t, x: c.x, y: c.y, vx: Math.cos(angle) * speed, vy: Math.sin(angle) * speed });
    }
  }

  setMode(name, t) {
    if (name === 'two' || name === 'scrub') { this.tint = name; this.tintUntil = t + 300; }
  }

  start() {
    if (this.running) return;
    this.running = true;
    const loop = (t) => { if (!this.running) return; requestAnimationFrame(loop); this.draw(t); };
    requestAnimationFrame(loop);
  }

  draw(t) {
    if (!this.enabled) return;
    const { ctx, canvas } = this;
    const w = canvas.width, h = canvas.height;
    ctx.clearRect(0, 0, w, h);
    if (!this.hands.length && !this.pulses.length && !this.sparks.length) return;
    const active = t < this.tintUntil ? this.tint : 'idle';
    const [r, g, b] = TINTS[active];
    const rgb = (a) => `rgba(${r},${g},${b},${a})`;
    ctx.globalCompositeOperation = 'lighter';
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';
    ctx.shadowColor = rgb(1);
    ctx.shadowBlur = 8;
    for (const hand of this.hands) {
      ctx.strokeStyle = rgb(0.85);
      ctx.lineWidth = 2;
      ctx.beginPath();
      for (const [a, c] of BONES) {
        ctx.moveTo(hand.points[a][0] * w, hand.points[a][1] * h);
        ctx.lineTo(hand.points[c][0] * w, hand.points[c][1] * h);
      }
      ctx.stroke();
      ctx.fillStyle = rgb(0.95);
      for (const i of [4, 8, 12, 16, 20]) {
        ctx.beginPath();
        ctx.arc(hand.points[i][0] * w, hand.points[i][1] * h, 3, 0, 7);
        ctx.fill();
      }
    }
    ctx.shadowBlur = 0;
    for (let i = 1; i < this.trail.length; i++) {
      const p = this.trail[i - 1], q = this.trail[i];
      const age = (t - q.t) / TRAIL_MS;
      if (age >= 1 || age < 0) continue;
      ctx.strokeStyle = rgb(0.7 * (1 - age));
      ctx.lineWidth = 6 * (1 - age) + 1;
      ctx.beginPath();
      ctx.moveTo(p.x * w, p.y * h);
      ctx.lineTo(q.x * w, q.y * h);
      ctx.stroke();
    }
    this.pulses = this.pulses.filter((p) => t - p.t < PULSE_MS);
    for (const p of this.pulses) {
      const k = (t - p.t) / PULSE_MS;
      const [pr, pg, pb] = TINTS[p.dir];
      ctx.strokeStyle = `rgba(${pr},${pg},${pb},${1 - k})`;
      ctx.lineWidth = 3;
      ctx.beginPath();
      ctx.arc(p.x * w, p.y * h, 8 + k * w * 0.18, 0, 7);
      ctx.stroke();
      const [dx, dy] = STREAK[p.dir];
      for (let i = -1; i <= 1; i++) {
        const ox = -dy * i * 8, oy = dx * i * 8;
        const len = (0.1 + 0.25 * k) * w;
        ctx.beginPath();
        ctx.moveTo(p.x * w + ox, p.y * h + oy);
        ctx.lineTo(p.x * w + ox + dx * len, p.y * h + oy + dy * len);
        ctx.stroke();
      }
    }
    this.sparks = this.sparks.filter((s) => t - s.t < SPARK_MS);
    ctx.fillStyle = rgb(1);
    for (const s of this.sparks) {
      const age = (t - s.t) / 1000;
      ctx.globalAlpha = 1 - (t - s.t) / SPARK_MS;
      ctx.fillRect((s.x + s.vx * age) * w - 1.5, (s.y + s.vy * age) * h - 1.5, 3, 3);
    }
    ctx.globalAlpha = 1;
    ctx.globalCompositeOperation = 'source-over';
  }
}
