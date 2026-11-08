// End-to-end test of both throw schemes and the settings. Run: E2E_SPEC=schemes bash scripts/e2e/run.sh
// Every touch is a real multi-touch CDP event, as in e2e.mjs. Checks read screenshot pixels.
import fs from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';

const scratchRequire = createRequire(path.join(process.env.E2E_SCRATCH, 'package.json'));
const { chromium } = scratchRequire('playwright-core');
const { PNG } = scratchRequire('pngjs');

const URL = process.env.E2E_URL + (process.env.E2E_URL.includes("?") ? "&" : "?") + "e2e=1";
const OUT = process.env.E2E_OUT;
const LANDSCAPE = { width: 844, height: 390 };

// Control centres at 844x390, from the layout code: the fire button and aim stick share one slot left of the dash button.
const SLOT = { x: 669, y: 295 };
const GEAR = { x: 717, y: 85 };
const TILE_LOCK = { x: 272, y: 180 };
const TILE_AIM = { x: 372, y: 180 };
const TILE_CLOSE = { x: 422, y: 275 };
const SANDAL_TAN = [244, 213, 141];
const FRIENDLY_BLUE = [64, 191, 255];
// Blue pixels in the HUD role icon at 844x390: the crosshair (attack) has about 294, the shield (defend) about 728.
const ROLE_ICON_MASS_SPLIT = 500;
const RING = [255, 255, 255];

const results = [];
const consoleErrors = [];

function record(name, pass, detail) {
	results.push({ name, pass, detail });
	console.log(`${pass ? 'PASS' : 'FAIL'}  ${name}${detail ? ' - ' + detail : ''}`);
}

function close(a, b, tolerance = 12) {
	return Math.abs(a[0] - b[0]) <= tolerance && Math.abs(a[1] - b[1]) <= tolerance && Math.abs(a[2] - b[2]) <= tolerance;
}

async function shot(page, name) {
	const file = path.join(OUT, `${name}.png`);
	await page.screenshot({ path: file });
	return PNG.sync.read(fs.readFileSync(file));
}

function pixel(png, x, y) {
	const i = (y * png.width + x) * 4;
	return [png.data[i], png.data[i + 1], png.data[i + 2]];
}

function countColour(png, colour, box, tolerance = 8) {
	let count = 0;
	const [x0, y0, x1, y1] = box;
	for (let y = y0; y < y1; y++) {
		for (let x = x0; x < x1; x++) {
			if (close(pixel(png, x, y), colour, tolerance)) count++;
		}
	}
	return count;
}

function changedPixels(a, b, box) {
	let count = 0;
	const [x0, y0, x1, y1] = box;
	for (let y = y0; y < y1; y++) {
		for (let x = x0; x < x1; x++) {
			const pa = pixel(a, x, y);
			const pb = pixel(b, x, y);
			if (Math.abs(pa[0] - pb[0]) + Math.abs(pa[1] - pb[1]) + Math.abs(pa[2] - pb[2]) > 60) count++;
		}
	}
	return count;
}

function findRing(png) {
	let minX = Infinity;
	let minY = Infinity;
	let maxX = -Infinity;
	let maxY = -Infinity;
	let count = 0;
	for (let y = 70; y < png.height - 40; y++) {
		for (let x = 135; x < png.width - 150; x++) {
			if (close(pixel(png, x, y), RING, 3)) {
				minX = Math.min(minX, x);
				minY = Math.min(minY, y);
				maxX = Math.max(maxX, x);
				maxY = Math.max(maxY, y);
				count++;
			}
		}
	}
	return count >= 8 ? { x: (minX + maxX) / 2, y: (minY + maxY) / 2, count } : null;
}

async function touch(client, type, points) {
	await client.send('Input.dispatchTouchEvent', { type, touchPoints: points });
}

async function tap(client, point, id = 1) {
	await touch(client, 'touchStart', [{ x: point.x, y: point.y, id }]);
	await new Promise((resolve) => setTimeout(resolve, 60));
	await touch(client, 'touchEnd', []);
}

async function drag(client, id, from, to, steps = 10) {
	await touch(client, 'touchStart', [{ x: from.x, y: from.y, id }]);
	for (let i = 1; i <= steps; i++) {
		await touch(client, 'touchMove', [{ x: from.x + ((to.x - from.x) * i) / steps, y: from.y + ((to.y - from.y) * i) / steps, id }]);
		await new Promise((resolve) => setTimeout(resolve, 16));
	}
}

async function newSession(browser, storageState) {
	const context = await browser.newContext({ viewport: LANDSCAPE, hasTouch: true, isMobile: true, deviceScaleFactor: 1, storageState });
	const page = await context.newPage();
	page.on('console', (message) => {
		if (message.type() === 'error') consoleErrors.push(message.text());
	});
	page.on('pageerror', (error) => consoleErrors.push(`pageerror: ${error.message}`));
	await page.goto(URL);
	await page.tap('#start');
	await page.waitForFunction(() => document.body.classList.contains('started'), null, { timeout: 15000 }).catch(() => {});
	await page.waitForTimeout(4000 + 5600);
	return { context, page, client: await context.newCDPSession(page) };
}

// The coin flip decides the human's role, so reload until the human is an attacker, who holds a sandal.
async function bootAsAttacker(browser, tries = 8) {
	for (let attempt = 0; attempt < tries; attempt++) {
		const session = await newSession(browser);
		for (let i = 0; i < 24; i++) {
			const png = await shot(session.page, `probe-${attempt}`);
			const ring = findRing(png);
			const isAttacker = roleIconMass(png) < ROLE_ICON_MASS_SPLIT;
			if (isAttacker && ring && countColour(png, SANDAL_TAN, [Math.round(ring.x) - 36, Math.round(ring.y) - 36, Math.round(ring.x) + 36, Math.round(ring.y) + 36]) > 8) {
				return { ...session, ring };
			}
			if (!isAttacker) break;
			await session.page.waitForTimeout(500);
		}
		await session.context.close();
	}
	return null;
}

function roleIconMass(png) {
	let mass = 0;
	for (let y = 8; y < 56; y++) {
		for (let x = 334; x < 372; x++) {
			if (close(pixel(png, x, y), FRIENDLY_BLUE, 24)) mass++;
		}
	}
	return mass;
}

function handSandals(png, ring) {
	return countColour(png, SANDAL_TAN, [Math.round(ring.x) - 36, Math.round(ring.y) - 36, Math.round(ring.x) + 36, Math.round(ring.y) + 36]);
}

async function openSettings(client, page) {
	await tap(client, GEAR);
	await page.waitForTimeout(400);
}

async function closeSettings(client, page) {
	await tap(client, TILE_CLOSE);
	await page.waitForTimeout(400);
}

async function scenarioSchemeD(browser) {
	const session = await bootAsAttacker(browser);
	if (!session) return record('1 scheme D: could not boot as an attacker holding a sandal', false);
	const { context, page, client, ring } = session;
	const before = await shot(page, '01-d-before');
	await touch(client, 'touchStart', [{ x: SLOT.x, y: SLOT.y, id: 2 }]);
	await page.waitForTimeout(300);
	const held = await shot(page, '01-d-held');
	record('1a scheme D: holding the fire button shows the preview', changedPixels(before, held, [135, 40, 640, 350]) > 100);
	await touch(client, 'touchEnd', []);
	await page.waitForTimeout(350);
	const flight = await shot(page, '01-d-flight');
	const start = handSandals(before, ring);
	const end = handSandals(flight, ring);
	record('1b scheme D: releasing throws the sandal', end < start, `tan pixels near the ring ${start} -> ${end}`);
	await context.close();
}

async function scenarioCancel(browser) {
	const session = await bootAsAttacker(browser);
	if (!session) return record('2 cancel: could not boot as an attacker holding a sandal', false);
	const { context, page, client, ring } = session;
	const before = await shot(page, '02-cancel-before');
	const start = handSandals(before, ring);
	await touch(client, 'touchStart', [{ x: SLOT.x, y: SLOT.y, id: 2 }]);
	for (let i = 1; i <= 6; i++) {
		await touch(client, 'touchMove', [{ x: SLOT.x + i * 14, y: SLOT.y - i * 6, id: 2 }]);
		await page.waitForTimeout(16);
	}
	for (let i = 1; i <= 6; i++) {
		await touch(client, 'touchMove', [{ x: SLOT.x + 84 - i * 14, y: SLOT.y - 36 + i * 6, id: 2 }]);
		await page.waitForTimeout(16);
	}
	await touch(client, 'touchEnd', []);
	await page.waitForTimeout(350);
	const after = await shot(page, '02-cancel-after');
	const end = handSandals(after, ring);
	record('2 cancel: dragging back to the button and releasing keeps the sandal', end >= start - 4, `tan pixels near the ring ${start} -> ${end}`);
	await context.close();
}

async function scenarioSwitch(browser) {
	const session = await bootAsAttacker(browser);
	if (!session) return record('3 switch: could not boot as an attacker holding a sandal', false);
	const { context, page, client, ring } = session;
	const dBefore = await shot(page, '03-switch-d');
	await openSettings(client, page);
	const panel = await shot(page, '03-switch-panel');
	record('3a settings: the panel opens over the game', changedPixels(dBefore, panel, [250, 120, 600, 330]) > 2000);
	await tap(client, TILE_AIM);
	await page.waitForTimeout(400);
	const aimTile = await shot(page, '03-switch-aim-chosen');
	const lockRing = countColour(aimTile, [64, 191, 255], [240, 150, 305, 215], 40);
	const aimRing = countColour(aimTile, [64, 191, 255], [340, 150, 405, 215], 40);
	record('3b settings: choosing scheme A moves the active ring to the aim tile', aimRing > lockRing + 50, `lock ring ${lockRing} px, aim ring ${aimRing} px`);
	await closeSettings(client, page);
	const aStick = await shot(page, '03-switch-a');
	const fireIconGone = changedPixels(dBefore, aStick, [620, 255, 720, 340]) > 150;
	record('3c scheme A: the right control changes to the aim stick', fireIconGone);
	const aBefore = await shot(page, '03-a-before');
	await touch(client, 'touchStart', [{ x: SLOT.x, y: SLOT.y, id: 2 }]);
	for (let i = 1; i <= 8; i++) {
		await touch(client, 'touchMove', [{ x: SLOT.x - i * 9, y: SLOT.y - i * 4, id: 2 }]);
		await page.waitForTimeout(16);
	}
	await page.waitForTimeout(250);
	const aAiming = await shot(page, '03-a-aiming');
	record('3d scheme A: dragging draws the aim preview', changedPixels(aBefore, aAiming, [135, 40, 640, 350]) > 150);
	await touch(client, 'touchEnd', []);
	await page.waitForTimeout(350);
	const aFlight = await shot(page, '03-a-flight');
	const start = handSandals(aBefore, ring);
	const end = handSandals(aFlight, ring);
	record('3e scheme A: release throws the sandal', end < start, `tan pixels near the ring ${start} -> ${end}`);
	const storage = await context.storageState();
	await context.close();
	return storage;
}

async function scenarioPersist(browser) {
	// A reload of the same page keeps its IndexedDB, as a phone does. Godot writes user://settings.cfg there.
	const { context, page, client } = await newSession(browser);
	await openSettings(client, page);
	await tap(client, TILE_AIM);
	await page.waitForTimeout(1200);
	await closeSettings(client, page);
	const saved = await page.evaluate(() => new Promise((resolve) => {
		const open = indexedDB.open('/userfs');
		open.onerror = () => resolve(false);
		open.onsuccess = () => {
			const keys = open.result.transaction('FILE_DATA', 'readonly').objectStore('FILE_DATA').getAllKeys();
			keys.onsuccess = () => resolve(keys.result.some((key) => String(key).endsWith('/settings.cfg')));
		};
	}));
	record('4a persist: the browser stored settings.cfg in IndexedDB', saved);
	await page.reload();
	await page.tap('#start');
	await page.waitForFunction(() => document.body.classList.contains('started'), null, { timeout: 15000 }).catch(() => {});
	await page.waitForTimeout(4500);
	const reloaded = await context.newCDPSession(page);
	await openSettings(reloaded, page);
	const png = await shot(page, '04-persist-panel');
	const lockRing = countColour(png, [64, 191, 255], [240, 150, 305, 215], 40);
	const aimRing = countColour(png, [64, 191, 255], [340, 150, 405, 215], 40);
	record('4b persist: scheme A is still chosen after a page reload', aimRing > lockRing + 50, `lock ring ${lockRing} px, aim ring ${aimRing} px`);
	await tap(reloaded, TILE_LOCK);
	await page.waitForTimeout(800);
	await context.close();
}

async function scenarioPause(browser) {
	const session = await newSession(browser);
	const { context, page, client } = session;
	const before = await shot(page, '05-pause-before');
	await openSettings(client, page);
	const open1 = await shot(page, '05-pause-open1');
	await page.waitForTimeout(1500);
	const open2 = await shot(page, '05-pause-open2');
	record('5a settings: the round is paused while the panel is open', changedPixels(open1, open2, [135, 40, 640, 350]) < 200, `${changedPixels(open1, open2, [135, 40, 640, 350])} px moved in 1.5 s`);
	await closeSettings(client, page);
	await page.waitForTimeout(1200);
	const after = await shot(page, '05-pause-after');
	record('5b settings: the round resumes after the panel closes', changedPixels(before, after, [135, 40, 640, 350]) > 300);
	await context.close();
}

const browser = await chromium.launch({
	executablePath: process.env.CHROME_PATH || '/usr/bin/google-chrome',
	headless: true,
	args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'],
});

const scenarios = [scenarioSchemeD, scenarioCancel, scenarioSwitch, scenarioPersist, scenarioPause];
const only = (process.env.E2E_ONLY || '').split(',').filter(Boolean);
for (const scenario of scenarios) {
	if (only.length > 0 && !only.some((key) => scenario.name.toLowerCase().includes(key.toLowerCase()))) continue;
	try {
		await scenario(browser);
	} catch (error) {
		record(`${scenario.name}: threw`, false, error.message);
	}
}
await browser.close();

if (only.length === 0) record('6 console: no error messages during the run', consoleErrors.length === 0, consoleErrors.slice(0, 3).join(' | '));
fs.writeFileSync(path.join(OUT, 'schemes-report.json'), JSON.stringify({ results, consoleErrors }, null, 2));
const failed = results.filter((r) => !r.pass).length;
console.log(`\n${results.length - failed}/${results.length} checks pass. Screenshots and schemes-report.json are in ${OUT}`);
process.exit(failed === 0 ? 0 : 1);
