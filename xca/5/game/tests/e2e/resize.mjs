// End-to-end test: the settings gear stays clickable after the window resizes mid match.
// Run: E2E_URL=http://127.0.0.1:8096/index.html E2E_OUT=game/tests/e2e/out E2E_SCRATCH=/tmp/e2e-pw node game/tests/e2e/resize.mjs
import fs from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';

const scratchRequire = createRequire(path.join(process.env.E2E_SCRATCH, 'package.json'));
const { chromium } = scratchRequire('playwright-core');
const { PNG } = scratchRequire('pngjs');
const URL = process.env.E2E_URL;
const OUT = process.env.E2E_OUT;
const START = { width: 1160, height: 640 };
// Sizes in CSS pixels. Portrait shows the rotate overlay, so it is not tapped.
const SIZES = [[844, 390], [1160, 640], [1920, 1080], [400, 300], [1000, 500]];
// Gear centre in CSS pixels. The viewport is 640 tall, so one CSS pixel covers p viewport pixels.
// Gear radius is 24 CSS px but never under 28 viewport px. The HUD row and gap take 52 CSS px. The edge margin is 16 viewport px.
const gearCentre = (w, h) => {
	const p = 640 / h;
	const r = Math.max(24 * p, 28);
	return { x: w - (16 + r) / p, y: (16 + 52 * p + r) / p };
};

let failed = 0;
function record(name, pass, detail) {
	if (!pass) failed++;
	console.log(`${pass ? 'PASS' : 'FAIL'}  ${name}${detail ? ' - ' + detail : ''}`);
}

async function brightness(page, name) {
	const file = path.join(OUT, `${name}.png`);
	await page.screenshot({ path: file });
	const png = PNG.sync.read(fs.readFileSync(file));
	let sum = 0;
	let n = 0;
	for (let y = 0; y < png.height; y += 7) {
		for (let x = 0; x < png.width; x += 7) {
			const i = (y * png.width + x) * 4;
			sum += png.data[i] + png.data[i + 1] + png.data[i + 2];
			n++;
		}
	}
	return sum / n / 3;
}

const browser = await chromium.launch({ executablePath: process.env.CHROME || '/usr/bin/google-chrome', headless: true,
	args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
fs.mkdirSync(OUT, { recursive: true });
for (const [w, h] of SIZES) {
	const page = await (await browser.newContext({ viewport: START })).newPage();
	await page.goto(URL);
	await page.click('#start').catch(() => {});
	await page.waitForTimeout(6000);
	await page.mouse.click(508, 486);
	await page.waitForTimeout(8000);
	await page.setViewportSize({ width: w, height: h });
	await page.waitForTimeout(1200);
	const before = await brightness(page, `resize-${w}x${h}-before`);
	const gear = gearCentre(w, h);
	await page.mouse.click(gear.x, gear.y);
	await page.waitForTimeout(700);
	const after = await brightness(page, `resize-${w}x${h}-panel`);
	record(`${w}x${h}: tapping the gear opens the settings panel`, after < before * 0.8, `${before.toFixed(1)} -> ${after.toFixed(1)}`);
	await page.context().close();
}
await browser.close();
process.exit(failed ? 1 : 0);
