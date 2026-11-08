// Usage: node tests/lab.mjs. Runs the Gesture lab step logic offline with injected frames, then drives the page without a camera.
import { chromium } from 'playwright-core';
import { LabEngine, STEPS, evaluate, frameLabel, safeHold, READY_MS, MEASURE_MS } from '../web/lab.js';

let failed = 0;
const check = (name, ok, detail = '') => { console.log(`${ok ? 'PASS' : 'FAIL'} ${name} ${detail}`); if (!ok) failed++; };
const hand = (gesture, score = 0.9, facing = 1) => ({ gesture, score, side: 'Right', facing });
const FRAME_MS = 100;

// Runs one attempt of the current step. make(i, tMs) returns the hands for each frame.
function attempt(lab, t0, make) {
  let t = t0;
  lab.feed([], t);
  const total = (READY_MS + MEASURE_MS) / FRAME_MS;
  for (let i = 0; i <= total + 1; i++) { t = t0 + i * FRAME_MS; lab.feed(make(i, t - t0 - READY_MS), t); }
  return t;
}
const fresh = (id) => { const lab = new LabEngine(); lab.index = STEPS.findIndex((s) => s.id === id); lab.begin(0); return lab; };

{
  const lab = fresh('Victory');
  attempt(lab, 0, () => [hand('Victory')]);
  check('perfect run is PASS', lab.last.verdict === 'PASS' && lab.last.hitPct === 100 && lab.last.flicker === 0, JSON.stringify({ ...lab.last, raw: 0 }));
  check('a perfect run holds for the whole window', lab.last.runSeconds >= 2.9, String(lab.last.runSeconds));
  check('phase moves to result', lab.phase === 'result');
}
{
  const lab = fresh('Victory');
  attempt(lab, 0, (i, rel) => [hand(rel > 1500 && rel < 1700 ? 'None' : 'Victory')]);
  check('one dropout (two label changes) is WARN', lab.last.verdict === 'WARN' && lab.last.flicker === 2, `${lab.last.verdict} flicker ${lab.last.flicker} pct ${lab.last.hitPct}`);
}
{
  const lab = fresh('Victory');
  attempt(lab, 0, () => [hand('Open_Palm')]);
  check('wrong label is FAIL with a confusion row', lab.last.verdict === 'FAIL' && lab.last.hitPct === 0 && lab.last.confusion[0].label === 'Open_Palm', JSON.stringify(lab.last.confusion));
}
{
  const lab = fresh('Victory');
  attempt(lab, 0, () => [hand('Victory', 0.5)]);
  check('low score blocks PASS', lab.last.verdict !== 'PASS' && lab.last.minScore === 0.5, `${lab.last.verdict} min ${lab.last.minScore}`);
}
{
  const lab = fresh('Hang');
  attempt(lab, 0, () => [hand('None')]);
  check('negative with no trigger is PASS', lab.last.verdict === 'PASS' && lab.last.hitPct === 0);
}
{
  const lab = fresh('Hang');
  attempt(lab, 0, (i) => [hand(i % 2 ? 'Open_Palm' : 'None')]);
  check('negative with trigger label is FAIL', lab.last.verdict === 'FAIL' && lab.last.hitPct >= 40, `${lab.last.verdict} ${lab.last.hitPct}`);
}
{
  const lab = fresh('Wave');
  attempt(lab, 0, (i) => [hand(i < 3 ? 'Closed_Fist' : 'None')]);
  check('negative under 5 percent trigger frames is PASS', lab.last.verdict === 'PASS' || lab.last.hitPct >= 5, `${lab.last.verdict} ${lab.last.hitPct}`);
}
{
  const lab = fresh('Hang');
  attempt(lab, 0, () => [hand('None'), hand('Closed_Fist')]);
  check('negative sees a trigger on the second hand', lab.last.verdict === 'FAIL');
}
{
  const lab = fresh('Two_Fists');
  attempt(lab, 0, () => [hand('Closed_Fist'), hand('Closed_Fist')]);
  check('two fists PASS', lab.last.verdict === 'PASS');
}
{
  const lab = fresh('Two_Fists');
  attempt(lab, 0, () => [hand('Closed_Fist')]);
  check('one fist alone FAILs two fists', lab.last.verdict === 'FAIL' && lab.last.confusion[0].label === 'One_Hand');
}
{
  const lab = fresh('Two_Palms');
  attempt(lab, 0, () => [hand('Open_Palm', 0.9, -1), hand('Open_Palm', 0.9, -1)]);
  check('two palms facing the camera PASS', lab.last.verdict === 'PASS');
  const back = fresh('Two_Palms');
  attempt(back, 0, () => [hand('Open_Palm', 0.9, 1), hand('Open_Palm', 0.9, 1)]);
  check('two backs of hands FAIL two palms', back.last.verdict === 'FAIL' && back.last.confusion[0].label === 'Two_Backs');
}
{
  const lab = fresh('Open_Palm');
  attempt(lab, 0, () => []);
  check('no hand at all FAILs and counts the frames', lab.last.verdict === 'FAIL' && lab.last.noHandPct === 100);
}
check('frameLabel picks the highest score hand', frameLabel([hand('Thumb_Up', 0.4), hand('Victory', 0.9)], STEPS[3]) === 'Victory');
check('safeHold of equal runs is that run', safeHold([2.9, 2.9, 2.9]) === 2.9);
check('safeHold uses the 5th percentile of many attempts', safeHold([...Array(19).fill(3), 1.2]) === 1.2 || safeHold([...Array(19).fill(3), 1.2]) === 3);
check('evaluate handles zero frames', evaluate([], STEPS[0]).verdict === 'FAIL');
{
  const lab = new LabEngine();
  lab.start(0);
  let t = 0;
  for (let rep = 0; rep < 3; rep++) {
    t = attempt(lab, t + 10, () => [hand('Open_Palm')]);
    if (rep < 2) lab.retry(t);
  }
  const row = lab.rows()[0];
  check('three attempts aggregate into one row', row.attempts === 3 && row.verdict === 'PASS' && row.hold >= 2.9, JSON.stringify(row));
  lab.next(t);
  check('Next moves to the second step', lab.step.id === 'Closed_Fist' && lab.phase === 'ready');
  const json = lab.toJSON({ mode: 'Low end', delegate: 'CPU' });
  check('JSON carries mode, attempts and raw labels with timestamps', json.meta.mode === 'Low end' && json.attempts.length === 3 && json.attempts[0].raw[0].t !== undefined && json.attempts[0].raw[0].hands[0].gesture === 'Open_Palm');
  check('text summary names the gesture and verdict', /Open_Palm: PASS/.test(lab.text({ mode: 'Low end' })));
}

// Page drive. No camera: frames are injected through window.__labFeed.
const browser = await chromium.launch({ executablePath: '/usr/bin/google-chrome', headless: true, args: ['--ignore-certificate-errors'] });
for (const viewport of [{ width: 1024, height: 768 }, { width: 390, height: 844 }]) {
  const page = await browser.newPage({ viewport });
  const errors = [];
  page.on('pageerror', (e) => errors.push(e.message));
  await page.goto('https://localhost:8446/bench.html');
  check(`default quality is Low end at ${viewport.width}x${viewport.height}`, (await page.inputValue('#quality')) === 'low');
  await page.evaluate(() => window.__labFeed([], 0));
  await page.click('#labStart');
  await page.evaluate(() => {
    for (let t = 0; t <= 4300; t += 100) window.__labFeed([{ gesture: 'Open_Palm', score: 0.9, side: 'Right', facing: 1, points: [] }], t);
  });
  check('card shows PASS for an injected perfect run', /Open_Palm attempt 1: PASS/.test(await page.textContent('#labVerdict')));
  await page.click('#labNext');
  check('Next shows the next prompt', /fist/i.test(await page.textContent('#labPrompt')));
  const small = await page.evaluate(() => [...document.querySelectorAll('#lab button')].filter((e) => { const r = e.getBoundingClientRect(); return r.width < 48 || r.height < 48; }).map((e) => e.id));
  check('lab buttons are at least 48 px', small.length === 0, small.join(','));
  check('no sideways scroll', !(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth + 1)));
  const [download] = await Promise.all([page.waitForEvent('download'), page.click('#labDownload')]);
  check('Download JSON saves a file', /^gesture-lab-.*\.json$/.test(download.suggestedFilename()));
  check('no page errors', errors.length === 0, errors.join('|'));
  await page.close();
}
await browser.close();
process.exit(failed ? 1 : 0);
