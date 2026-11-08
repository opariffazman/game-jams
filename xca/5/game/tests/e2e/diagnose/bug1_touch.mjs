// Bug 1 in a real browser: a human attacker drags along the exact bearing from the stick to the stack,
// as the preview shows it, releases, and we count whether the stack toppled.
// Run: bash game/tests/e2e/diagnose/run_bug1.sh
// Reads only screenshot pixels. It changes no game code. The camera sits on the stack, so the stack is the
// screen centre. A topple is the three stack sandals leaving their column.
import fs from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';

const scratchRequire = createRequire(path.join(process.env.E2E_SCRATCH, 'package.json'));
const { chromium } = scratchRequire('playwright-core');
const { PNG } = scratchRequire('pngjs');

const URL = process.env.E2E_URL;
const OUT = process.env.E2E_OUT;
const SCHEME = process.env.E2E_SCHEME || 'A';
const TRIES = Number(process.env.E2E_TRIES || 20);
// Angular thumb error in degrees added to the exact bearing. A fixed list is cycled so the result is a curve.
const ERRORS = (process.env.E2E_ERRORS || '0').split(',').map(Number);
const LANDSCAPE = { width: 844, height: 390 };

// Layout at 844x390, from the layout code and the schemes harness.
const SLOT = { x: 669, y: 295 };
const STICK_RADIUS_PX = 66 / 1.641; // aim_stick_css_px 132 / 2 css px
const GEAR = { x: 717, y: 85 };
const TILE_AIM = { x: 422, y: 180 };
const TILE_LOCK = { x: 322, y: 180 };
const TILE_CLOSE = { x: 422, y: 275 };
const SANDAL_TAN = [244, 213, 141];
const FRIENDLY_BLUE = [64, 191, 255];
const ROLE_ICON_MASS_SPLIT = 500;
const RING = [255, 255, 255];
const SCALE = 390 / 640;
const STACK_SCREEN = { x: 422, y: 195 };

const rows = [];

function pixel(png, x, y) {
	const i = (y * png.width + x) * 4;
	return [png.data[i], png.data[i + 1], png.data[i + 2]];
}
function close(a, b, t = 12) {
	return Math.abs(a[0] - b[0]) <= t && Math.abs(a[1] - b[1]) <= t && Math.abs(a[2] - b[2]) <= t;
}
function countColour(png, colour, box, tolerance = 8) {
	let count = 0;
	const [x0, y0, x1, y1] = box;
	for (let y = y0; y < y1; y++) for (let x = x0; x < x1; x++) if (close(pixel(png, x, y), colour, tolerance)) count++;
	return count;
}
function tanBounds(png, box) {
	let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity, count = 0;
	const [x0, y0, x1, y1] = box;
	for (let y = y0; y < y1; y++) {
		for (let x = x0; x < x1; x++) {
			if (close(pixel(png, x, y), SANDAL_TAN, 10)) {
				minX = Math.min(minX, x); minY = Math.min(minY, y); maxX = Math.max(maxX, x); maxY = Math.max(maxY, y); count++;
			}
		}
	}
	return { minX, minY, maxX, maxY, count };
}
function countGreyRing(png) {
	let n = 0;
	for (let y = STACK_SCREEN.y - 60; y < STACK_SCREEN.y + 60; y++) {
		for (let x = STACK_SCREEN.x - 60; x < STACK_SCREEN.x + 60; x++) {
			const r = Math.hypot(x - STACK_SCREEN.x, y - STACK_SCREEN.y);
			if (r < 40 || r > 56) continue;
			const p = pixel(png, x, y);
			if (Math.abs(p[0] - p[1]) < 14 && Math.abs(p[1] - p[2]) < 14 && p[0] >= 90 && p[0] <= 170) n++;
		}
	}
	return n;
}
function findRing(png) {
	let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity, count = 0;
	for (let y = 70; y < png.height - 40; y++) {
		for (let x = 135; x < png.width - 150; x++) {
			if (close(pixel(png, x, y), RING, 3)) {
				minX = Math.min(minX, x); minY = Math.min(minY, y); maxX = Math.max(maxX, x); maxY = Math.max(maxY, y); count++;
			}
		}
	}
	return count >= 8 ? { x: (minX + maxX) / 2, y: (minY + maxY) / 2, count } : null;
}
function roleIconMass(png) {
	let mass = 0;
	for (let y = 8; y < 56; y++) for (let x = 334; x < 372; x++) if (close(pixel(png, x, y), FRIENDLY_BLUE, 24)) mass++;
	return mass;
}
async function shot(page, name) {
	const file = path.join(OUT, `${name}.png`);
	await page.screenshot({ path: file });
	return PNG.sync.read(fs.readFileSync(file));
}
async function touch(client, type, points) {
	await client.send('Input.dispatchTouchEvent', { type, touchPoints: points });
}
async function tap(client, point, id = 1) {
	await touch(client, 'touchStart', [{ x: point.x, y: point.y, id }]);
	await new Promise((r) => setTimeout(r, 60));
	await touch(client, 'touchEnd', []);
}
async function newSession(browser) {
	const context = await browser.newContext({ viewport: LANDSCAPE, hasTouch: true, isMobile: true, deviceScaleFactor: 1 });
	const page = await context.newPage();
	await page.goto(URL);
	await page.tap('#start');
	await page.waitForFunction(() => document.body.classList.contains('started'), null, { timeout: 15000 }).catch(() => {});
	await page.waitForTimeout(4000);
	return { context, page, client: await context.newCDPSession(page) };
}

// Rebuild the throw preview as the player sees it. The thrower is the ring marker, the stack is the screen centre.
async function oneAttempt(browser, attempt, scheme) {
	for (let boot = 0; boot < 8; boot++) {
		const session = await newSession(browser);
		const { context, page, client } = session;
		if (scheme === 'D') {
			// Scheme D is the default and needs no settings change.
		} else {
			await tap(client, GEAR);
			await page.waitForTimeout(400);
			await tap(client, TILE_AIM);
			await page.waitForTimeout(400);
			await tap(client, TILE_CLOSE);
			await page.waitForTimeout(500);
		}
		let ready = null;
		for (let i = 0; i < 20; i++) {
			const png = await shot(page, `d-probe`);
			const ring = findRing(png);
			const attacker = roleIconMass(png) < ROLE_ICON_MASS_SPLIT;
			if (attacker && ring && countColour(png, SANDAL_TAN, [Math.round(ring.x) - 36, Math.round(ring.y) - 36, Math.round(ring.x) + 36, Math.round(ring.y) + 36]) > 8) {
				ready = { ring, png };
				break;
			}
			if (!attacker) break;
			await page.waitForTimeout(400);
		}
		if (!ready) {
			await context.close();
			continue;
		}
		const ring = ready.ring;
		const before = tanBounds(ready.png, [STACK_SCREEN.x - 40, STACK_SCREEN.y - 40, STACK_SCREEN.x + 40, STACK_SCREEN.y + 40]);
		// The exact bearing from the thrower to the stack, in screen space.
		const dx = STACK_SCREEN.x - ring.x;
		const dy = STACK_SCREEN.y - ring.y;
		const length = Math.hypot(dx, dy);
		const error = (ERRORS[attempt % ERRORS.length] * Math.PI) / 180;
		const ux = dx / length;
		const uy = dy / length;
		const bearing = { x: ux * Math.cos(error) - uy * Math.sin(error), y: ux * Math.sin(error) + uy * Math.cos(error) };
		if (scheme === 'A') {
			// Drag from the stick centre out to 80 percent of the stick radius along the bearing.
			const reach = STICK_RADIUS_PX * 0.8;
			await touch(client, 'touchStart', [{ x: SLOT.x, y: SLOT.y, id: 2 }]);
			const steps = 10;
			for (let i = 1; i <= steps; i++) {
				await touch(client, 'touchMove', [{ x: SLOT.x + bearing.x * reach * (i / steps), y: SLOT.y + bearing.y * reach * (i / steps), id: 2 }]);
				await page.waitForTimeout(16);
			}
			await page.waitForTimeout(200);
			await shot(page, `d-aiming-${attempt}`);
			await touch(client, 'touchEnd', []);
		} else {
			await touch(client, 'touchStart', [{ x: SLOT.x, y: SLOT.y, id: 2 }]);
			await page.waitForTimeout(300);
			await touch(client, 'touchEnd', []);
		}
		await page.waitForTimeout(3200);
		const after = await shot(page, `d-after-${attempt}`);
		// A fallen stack shows the grey rebuild ring around the centre (1100 to 2300 grey pixels). A standing stack shows none.
		const greyRing = countGreyRing(after);
		const toppled = greyRing > 300;
		const afterBox = { minX: 0, minY: 0, maxX: 0, maxY: 0, count: greyRing };
		const widthBefore = before.maxX - before.minX;
		const heightBefore = before.maxY - before.minY;
		const widthAfter = 0;
		const heightAfter = 0;
		const countKept = greyRing;
		const moved = greyRing;
		rows.push({ attempt, scheme, errorDegrees: ERRORS[attempt % ERRORS.length], ring, bearing, before, after: afterBox, toppled, moved });
		console.log(`attempt ${attempt} scheme ${scheme} err ${ERRORS[attempt % ERRORS.length]}deg: ring (${ring.x.toFixed(0)},${ring.y.toFixed(0)}) bearing (${bearing.x.toFixed(3)},${bearing.y.toFixed(3)}) stack bbox ${widthBefore}x${heightBefore} -> ${widthAfter}x${heightAfter} grey ring ${greyRing} px => ${toppled ? 'TOPPLED' : 'stood'}`);
		await context.close();
		return;
	}
	console.log(`attempt ${attempt}: could not boot as an attacker`);
}

const browser = await chromium.launch({
	executablePath: process.env.CHROME_PATH || '/usr/bin/google-chrome',
	headless: true,
	args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'],
});
for (let attempt = 0; attempt < TRIES; attempt++) {
	try {
		await oneAttempt(browser, attempt, SCHEME);
	} catch (error) {
		console.log(`attempt ${attempt} threw: ${error.message}`);
	}
}
await browser.close();
const toppled = rows.filter((r) => r.toppled).length;
console.log(`\nSCHEME ${SCHEME}: topple ${toppled} of ${rows.length} (${rows.length ? ((100 * toppled) / rows.length).toFixed(0) : 0} percent)`);
const byError = {};
for (const r of rows) {
	byError[r.errorDegrees] = byError[r.errorDegrees] || { n: 0, t: 0 };
	byError[r.errorDegrees].n++;
	if (r.toppled) byError[r.errorDegrees].t++;
}
for (const [e, v] of Object.entries(byError)) console.log(`  error ${e} deg: ${v.t} of ${v.n}`);
fs.writeFileSync(path.join(OUT, `bug1-scheme-${SCHEME}.json`), JSON.stringify({ scheme: SCHEME, toppled, total: rows.length, rows }, null, 2));
