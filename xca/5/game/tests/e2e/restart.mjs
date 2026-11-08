// End-to-end test of the restart button through real touch events.
// Run: E2E_URL=http://127.0.0.1:8091/ E2E_OUT=game/tests/e2e/out E2E_SCRATCH=/tmp/e2e-pw node game/tests/e2e/restart.mjs
// No game debug hook exists, so every check reads screenshot pixels.
import fs from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';

const scratchRequire = createRequire(path.join(process.env.E2E_SCRATCH, 'package.json'));
const { chromium } = scratchRequire('playwright-core');
const { PNG } = scratchRequire('pngjs');

const URL = process.env.E2E_URL;
const OUT = process.env.E2E_OUT;
const LANDSCAPE = { width: 844, height: 390 };

// The button centre in CSS pixels. The 1160x640 viewport maps to 844x390 with the expand aspect.
const BUTTON = { x: 812, y: 72 };
const RING_YELLOW = [255, 230, 140];
const HOLD_MS = 1300;
const TAP_MS = 80;

const results = [];
const consoleErrors = [];

function record(name, pass, detail) {
	results.push({ name, pass, detail });
	console.log(`${pass ? 'PASS' : 'FAIL'}  ${name}${detail ? ' - ' + detail : ''}`);
}

function pixel(png, x, y) {
	const i = (y * png.width + x) * 4;
	return [png.data[i], png.data[i + 1], png.data[i + 2]];
}

function close(a, b, tolerance) {
	return Math.abs(a[0] - b[0]) <= tolerance && Math.abs(a[1] - b[1]) <= tolerance && Math.abs(a[2] - b[2]) <= tolerance;
}

async function shot(page, name) {
	const file = path.join(OUT, `${name}.png`);
	await page.screenshot({ path: file });
	return PNG.sync.read(fs.readFileSync(file));
}

// Yellow pixels on the button ring show the fill. The idle ring is white, so yellow means progress.
function ringFill(png) {
	let count = 0;
	for (let y = BUTTON.y - 24; y <= BUTTON.y + 24; y++) {
		for (let x = BUTTON.x - 24; x <= BUTTON.x + 24; x++) {
			if (close(pixel(png, x, y), RING_YELLOW, 40)) count++;
		}
	}
	return count;
}

// The coin flip washes the whole screen lighter for about a second after a match starts.
function meanBrightness(png) {
	let sum = 0;
	let n = 0;
	for (let y = 120; y < 330; y += 5) {
		for (let x = 140; x < 700; x += 5) {
			const p = pixel(png, x, y);
			sum += p[0] + p[1] + p[2];
			n++;
		}
	}
	return sum / n / 3;
}

async function touch(client, type, points) {
	await client.send('Input.dispatchTouchEvent', { type, touchPoints: points });
}

async function newPage(browser) {
	const context = await browser.newContext({ viewport: LANDSCAPE, hasTouch: true, isMobile: true, deviceScaleFactor: 1 });
	const page = await context.newPage();
	page.on('console', (message) => {
		if (message.type() === 'error') consoleErrors.push(message.text());
	});
	page.on('pageerror', (error) => consoleErrors.push(`pageerror: ${error.message}`));
	await page.goto(URL);
	await page.tap('#start');
	await page.waitForFunction(() => document.body.classList.contains('started'), null, { timeout: 15000 }).catch(() => {});
	await page.waitForTimeout(4000);
	const client = await context.newCDPSession(page);
	return { context, page, client };
}

async function scenarioIdleButton(browser) {
	const { context, page } = await newPage(browser);
	const png = await shot(page, 'restart-1-idle');
	record('1a restart: the button draws a ring at the top right', pixel(png, BUTTON.x - 26, BUTTON.y)[0] > 150 || pixel(png, BUTTON.x + 26, BUTTON.y)[0] > 150, 'ring pixel read');
	record('1b restart: the idle ring has no fill', ringFill(png) < 20, `${ringFill(png)} yellow pixels`);
	await context.close();
}

async function scenarioQuickTap(browser) {
	const { context, page, client } = await newPage(browser);
	const before = await shot(page, 'restart-2-before');
	await touch(client, 'touchStart', [{ ...BUTTON, id: 0 }]);
	await page.waitForTimeout(TAP_MS);
	await touch(client, 'touchEnd', []);
	await page.waitForTimeout(400);
	const after = await shot(page, 'restart-2-after-tap');
	record('2a tap: a quick tap does not fill the ring for long', ringFill(after) < 40, `${ringFill(after)} yellow pixels after release`);
	record('2b tap: the match keeps running (no coin-flip wash)', meanBrightness(after) < meanBrightness(before) + 25, `${meanBrightness(before).toFixed(1)} -> ${meanBrightness(after).toFixed(1)}`);
	await context.close();
}

async function scenarioFillAndRelease(browser) {
	const { context, page, client } = await newPage(browser);
	await touch(client, 'touchStart', [{ ...BUTTON, id: 0 }]);
	await page.waitForTimeout(400);
	const filling = await shot(page, 'restart-3-filling');
	record('3a hold: the ring fills while the finger is down', ringFill(filling) >= 40, `${ringFill(filling)} yellow pixels`);
	await touch(client, 'touchEnd', []);
	await page.waitForTimeout(300);
	const released = await shot(page, 'restart-3-released');
	record('3b hold: releasing early resets the ring', ringFill(released) < 20, `${ringFill(released)} yellow pixels`);
	await context.close();
}

async function scenarioFullHold(browser) {
	const { context, page, client } = await newPage(browser);
	// Wait until the first coin flip has faded, so a bright frame after the hold can only come from a new match.
	await page.waitForTimeout(2500);
	const quiet = await shot(page, 'restart-4-before');
	const baseline = meanBrightness(quiet);
	await touch(client, 'touchStart', [{ ...BUTTON, id: 0 }]);
	// The restart fires 0.8 s into the hold, so probe during the hold and after it, and keep the finger down for the whole probe.
	let washed = false;
	let peak = baseline;
	const holdStart = Date.now();
	for (let i = 0; i < 40 && !washed; i++) {
		const png = await shot(page, `restart-4-probe-${i}`);
		peak = Math.max(peak, meanBrightness(png));
		washed = peak > baseline + 20;
		if (!washed && Date.now() - holdStart > 6000) break;
	}
	await touch(client, 'touchEnd', []);
	record('4a full hold: the match restarts (the coin flip shows again)', washed, `brightness ${baseline.toFixed(1)} -> peak ${peak.toFixed(1)}`);
	await page.waitForTimeout(2500);
	const after = await shot(page, 'restart-4-after');
	record('4b full hold: the new match renders after the restart', meanBrightness(after) > 15, `brightness ${meanBrightness(after).toFixed(1)}`);
	await context.close();
}

async function scenarioKeyHold(browser) {
	const { context, page } = await newPage(browser);
	await page.waitForTimeout(2500);
	const quiet = await shot(page, 'restart-5-before');
	const baseline = meanBrightness(quiet);
	await page.keyboard.down('KeyR');
	await page.waitForTimeout(HOLD_MS);
	let peak = baseline;
	for (let i = 0; i < 12 && peak <= baseline + 20; i++) {
		const png = await shot(page, `restart-5-probe-${i}`);
		peak = Math.max(peak, meanBrightness(png));
		if (peak <= baseline + 20) await page.waitForTimeout(120);
	}
	await page.keyboard.up('KeyR');
	record('5 key: holding R restarts the match', peak > baseline + 20, `brightness ${baseline.toFixed(1)} -> peak ${peak.toFixed(1)}`);
	await context.close();
}

const browser = await chromium.launch({
	channel: 'chrome',
	args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'],
});
const only = (process.env.E2E_ONLY || '').split(',').filter(Boolean);
const scenarios = [scenarioIdleButton, scenarioQuickTap, scenarioFillAndRelease, scenarioFullHold, scenarioKeyHold];
for (const scenario of scenarios) {
	if (only.length && !only.some((word) => scenario.name.toLowerCase().includes(word.toLowerCase()))) continue;
	try {
		await scenario(browser);
	} catch (error) {
		record(`${scenario.name} threw`, false, String(error).split('\n')[0]);
	}
}
await browser.close();

record('console: no errors', consoleErrors.length === 0, consoleErrors.slice(0, 3).join(' | '));
const failed = results.filter((r) => !r.pass);
console.log(`\n${results.length - failed.length}/${results.length} checks pass`);
console.log('NOTE  no match-end debug path exists. The overlay is covered by tests/restart_test.gd and by screenshots from a bot-played match.');
fs.writeFileSync(path.join(OUT, 'restart-report.json'), JSON.stringify(results, null, 2));
process.exit(failed.length ? 1 : 0);
