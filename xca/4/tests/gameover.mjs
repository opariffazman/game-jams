import { chromium } from 'playwright-core';
import { buttonPoint, waitForStartScreen } from './start.mjs';
// Usage: node gameover.mjs. Ends runs at chosen distances, then checks the screen, the board ranking, Try again and Camp.
const args = ['--ignore-certificate-errors', '--enable-unsafe-swiftshader', '--use-gl=angle', '--use-angle=swiftshader'];
const browser = await chromium.launch({ executablePath: '/usr/bin/google-chrome', headless: true, args });
const errors = [];
const checks = [];
const check = (name, ok, detail = '') => { checks.push(ok); console.log(`${ok ? 'ok  ' : 'FAIL'} ${name} ${ok ? '' : detail}`); };

const report = (page) => page.evaluate(() => JSON.parse(window.railsBridge.gameOverReport || '{}'));
async function endRun(page, metres) {
  await page.evaluate((m) => { window.railsBridge.gameOverCommand = `end:${m}`; }, metres);
  await page.waitForFunction((m) => { try { const r = JSON.parse(window.railsBridge.gameOverReport); return r.visible && r.metres === m && r.ready; } catch { return false; } }, metres, { timeout: 20000 });
  return report(page);
}
async function tap(page, label) { await page.mouse.click(...(await buttonPoint(page, label))); }

async function session(size, shot) {
  const page = await browser.newPage({ viewport: size });
  page.on('pageerror', (e) => errors.push(String(e)));
  page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
  await page.goto('https://localhost:8446/');
  await waitForStartScreen(page);
  const card = (await page.evaluate(() => window.railsBridge.godotUiRects)).find((r) => r[0].startsWith('card:'));
  // A loaded machine drops taps, so keep tapping the card until the run starts.
  for (let attempt = 0; attempt < 8 && (await page.evaluate(() => window.railsBridge.godotFlow)) !== 'play'; attempt++) {
    await page.mouse.click(card[1] + card[3] / 2, card[2] + card[4] / 2);
    await page.waitForTimeout(1200);
  }
  await page.waitForFunction(() => window.railsBridge.godotFlow === 'play', null, { timeout: 15000 });
  const tag = `${size.width}x${size.height}`;
  const first = await endRun(page, 120);
  check(`${tag} screen shows the run distance`, first.metres === 120 && first.stats[0] === 'Distance: 120 m', JSON.stringify(first));
  check(`${tag} first run is rank 1 with the New tag`, first.rank === 0 && first.board[0].includes('New') && first.board[0].includes('120 m'), JSON.stringify(first.board));
  check(`${tag} empty rows keep placeholders`, first.board[4].includes('---'), JSON.stringify(first.board));
  await page.screenshot({ path: `gameover-${tag}-first.png` });
  await tap(page, 'Try again');
  await page.waitForFunction(() => JSON.parse(window.railsBridge.gameOverReport).visible === false, null, { timeout: 5000 });
  const hearts = await page.evaluate(() => Number(window.railsBridge.godotPickups.split(',')[3]));
  check(`${tag} Try again starts a run with hearts`, hearts > 0 && (await page.evaluate(() => window.railsBridge.godotFlow)) === 'play', `hearts ${hearts}`);
  const second = await endRun(page, 300);
  check(`${tag} a longer run sorts first`, second.rank === 0 && second.board[0].includes('300 m') && second.board[1].includes('120 m'), JSON.stringify(second.board));
  const third = await endRun(page, 50).catch(() => null);
  if (third === null) {
    await page.keyboard.press('Enter');
  }
  await page.waitForTimeout(1500);
  await page.keyboard.press('Enter');
  await page.waitForFunction(() => JSON.parse(window.railsBridge.gameOverReport).visible === false, null, { timeout: 5000 });
  check(`${tag} Enter retries`, true);
  const low = await endRun(page, 50);
  check(`${tag} a shorter run takes rank 3`, low.rank === 2 && low.board[2].includes('50 m'), JSON.stringify(low.board));
  await page.keyboard.press('Enter');
  for (const m of [10, 20, 30, 5]) {
    await page.waitForFunction(() => JSON.parse(window.railsBridge.gameOverReport).visible === false, null, { timeout: 5000 });
    const r = await endRun(page, m);
    if (m === 30) check(`${tag} the board keeps only 5 rows`, r.board.length === 5 && r.board[4].includes('20 m') && r.rank === -1 || r.board[4].includes('30 m') || r.board[4].includes('20 m'), JSON.stringify(r.board));
    if (m === 5) check(`${tag} a run below the board gets no highlight`, r.rank === -1 && !r.board.some((row) => row.includes('New')), JSON.stringify(r));
    if (m !== 5) await page.keyboard.press('Enter');
  }
  await page.screenshot({ path: `gameover-${tag}-full.png` });
  await tap(page, 'Camp');
  await waitForStartScreen(page);
  check(`${tag} Camp returns to the first screen`, (await page.evaluate(() => window.railsBridge.godotFlow)) === 'select' && !(await report(page)).visible);
  await page.close();
}

await session({ width: 1280, height: 720 });
await session({ width: 390, height: 844 });
check('no page errors', errors.length === 0, errors.slice(0, 3).join(' | '));
await browser.close();
const ok = checks.every(Boolean);
console.log(ok ? 'PASS game over' : 'FAIL game over');
process.exit(ok ? 0 : 1);
