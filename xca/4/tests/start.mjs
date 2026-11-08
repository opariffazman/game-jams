// Shared helpers that move the page through the intro the way a touch player does.
const HEROES = ['lis', 'sam', 'shaun', 'matt'];

// Centre of a start-screen button in CSS pixels. The layout moves, so the position is read, never hard-coded.
export async function buttonPoint(page, label) {
  await page.waitForFunction((n) => (window.railsBridge.godotUiRects || []).some((r) => r[0] === n), label, { timeout: 15000 });
  const r = await page.evaluate((n) => window.railsBridge.godotUiRects.find((q) => q[0] === n), label);
  return [r[1] + r[3] / 2, r[2] + r[4] / 2];
}

// Centre of a hero's pick area in CSS pixels. The camera circles the camp, so the position is read, never hard-coded.
export async function heroPoint(page, id) {
  await page.waitForFunction((n) => (window.railsBridge.godotUiRects || []).some((r) => r[0] === `card:${n}`), id, { timeout: 15000 });
  const r = await page.evaluate((n) => window.railsBridge.godotUiRects.find((q) => q[0] === `card:${n}`), id);
  return [r[1] + r[3] / 2, r[2] + r[4] / 2];
}

export async function waitForStartScreen(page) {
  await page.waitForFunction(() => window.railsBridge && window.railsBridge.godotFlow === 'select', null, { timeout: 90000 });
  await page.waitForTimeout(1000);
}

// Touch start: the first tap on a hero highlights it, the second confirms. A loaded machine drops taps, so keep tapping until the run starts.
export async function startByTouch(page, heroIndex = 0) {
  await waitForStartScreen(page);
  for (let attempt = 0; attempt < 8 && (await page.evaluate(() => window.railsBridge.godotFlow)) !== 'play'; attempt++) {
    await page.mouse.click(...(await heroPoint(page, HEROES[heroIndex])));
    await page.waitForTimeout(1200);
  }
  await page.waitForFunction(() => window.railsBridge.godotFlow === 'play', null, { timeout: 15000 });
}

// Hand start: taps the hands button, which unlocks audio.
export async function startWithHands(page) {
  await waitForStartScreen(page);
  await page.mouse.click(...(await buttonPoint(page, 'Hands')));
}
