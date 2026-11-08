// End-to-end touch test. Run through scripts/e2e/run.sh, which exports the game, serves it and sets NODE_PATH.
// No game debug hook exists, so every check reads screenshot pixels: the white ring marks the human character.
// Friendly is always blue and enemy always red, so the role of the human shows in the body shape, never in the colour.
import fs from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';

// ES modules ignore NODE_PATH, so load the scratch-dir packages through require.
const scratchRequire = createRequire(path.join(process.env.E2E_SCRATCH, 'package.json'));
const { chromium } = scratchRequire('playwright-core');
const { PNG } = scratchRequire('pngjs');

const URL = process.env.E2E_URL + (process.env.E2E_URL.includes("?") ? "&" : "?") + "e2e=1";
const OUT = process.env.E2E_OUT;
const LANDSCAPE = { width: 844, height: 390 };
const PORTRAIT = { width: 390, height: 844 };

const FIRE_BUTTON = { x: 669, y: 295 };
const FIRE_RADIUS = 36;
const GEAR = { x: 717, y: 85 };
const RING = [255, 255, 255];
const ROLE_ICON_MASS_SPLIT = 500;
const FRIENDLY_BLUE = [64, 191, 255];
const SANDAL_TAN = [244, 213, 141];
const ENEMY_RED = [255, 82, 48];

const results = [];
const notes = [];

function note(text) {
	notes.push(text);
	console.log(`NOTE  ${text}`);
}
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

// Centre of the bounding box of pure-white pixels inside the arena. The ring pulses in size and a pixel centroid drifts with it.
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

function countColour(png, colour, box) {
	let count = 0;
	const [x0, y0, x1, y1] = box;
	for (let y = y0; y < y1; y++) {
		for (let x = x0; x < x1; x++) {
			if (close(pixel(png, x, y), colour, 8)) count++;
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

// Friendly-blue pixels in the HUD role icon. Measured at 844x390: crosshair 294, shield 728.
function roleIconMass(png) {
	let mass = 0;
	for (let y = 8; y < 56; y++) {
		for (let x = 334; x < 372; x++) {
			if (close(pixel(png, x, y), FRIENDLY_BLUE, 24)) mass++;
		}
	}
	return mass;
}

// Greedy clustering of enemy red pixels. Returns cluster centres with at least minPixels pixels.
function findEnemyBodies(png, minPixels = 60) {
	const clusters = [];
	for (let y = 70; y < png.height - 40; y++) {
		for (let x = 135; x < png.width - 150; x++) {
			if (!close(pixel(png, x, y), ENEMY_RED, 14)) continue;
			const hit = clusters.find((c) => Math.hypot(c.x / c.n - x, c.y / c.n - y) < 22);
			if (hit) {
				hit.x += x;
				hit.y += y;
				hit.n++;
			} else {
				clusters.push({ x, y, n: 1 });
			}
		}
	}
	return clusters.filter((c) => c.n >= minPixels).map((c) => ({ x: c.x / c.n, y: c.y / c.n, n: c.n }));
}

async function touch(client, type, points) {
	await client.send('Input.dispatchTouchEvent', { type, touchPoints: points });
}

async function drag(client, id, from, to, steps = 10, holdMs = 16) {
	await touch(client, 'touchStart', [{ x: from.x, y: from.y, id }]);
	for (let i = 1; i <= steps; i++) {
		const x = from.x + ((to.x - from.x) * i) / steps;
		const y = from.y + ((to.y - from.y) * i) / steps;
		await touch(client, 'touchMove', [{ x, y, id }]);
		await new Promise((resolve) => setTimeout(resolve, holdMs));
	}
}

async function release(client) {
	await touch(client, 'touchEnd', []);
}

async function waitForRing(page, name, attempts = 20) {
	for (let i = 0; i < attempts; i++) {
		const png = await shot(page, name);
		const ring = findRing(png);
		if (ring) return { png, ring };
		await page.waitForTimeout(250);
	}
	return null;
}

async function newPage(browser) {
	const context = await browser.newContext({ viewport: LANDSCAPE, hasTouch: true, isMobile: true, deviceScaleFactor: 1 });
	const page = await context.newPage();
	page.on('console', (message) => {
		if (message.type() === 'error') consoleErrors.push(message.text());
	});
	page.on('pageerror', (error) => consoleErrors.push(`pageerror: ${error.message}`));
	await page.goto(URL);
	return { context, page };
}

async function boot(page) {
	await page.tap('#start');
	await page.waitForFunction(() => document.body.classList.contains('started'), null, { timeout: 15000 }).catch(() => {});
	// The match start (coin flip, intro, 3-2-1) holds the characters for about 5.1 s before play unlocks.
	await page.waitForTimeout(3500 + 5600);
}

// The human starts as attacker or defender by coin flip, so reload until the wanted role appears.
// The attacker holds a sandal that sits right next to the ring. The defender side has bots as attackers.
async function bootAsRole(browser, wantAttacker, maxTries = 8) {
	for (let attempt = 0; attempt < maxTries; attempt++) {
		const { context, page } = await newPage(browser);
		await boot(page);
		const found = await waitForRing(page, `role-probe-${attempt}`, 6);
		if (found) {
			const sandals = countColour(found.png, SANDAL_TAN, [
				Math.max(0, Math.round(found.ring.x) - 40),
				Math.max(0, Math.round(found.ring.y) - 40),
				Math.round(found.ring.x) + 40,
				Math.round(found.ring.y) + 40,
			]);
			// Colour no longer shows the role: the human is always blue. The HUD role icon does: the shield (defend) has
			// far more blue pixels than the crosshair (attack).
			const isAttacker = roleIconMass(found.png) < ROLE_ICON_MASS_SPLIT;
			if (isAttacker === wantAttacker) return { context, page, ring: found.ring, sandals };
		}
		await context.close();
	}
	return null;
}

async function scenarioBoot(browser) {
	const { context, page } = await newPage(browser);
	const startVisible = await page.isVisible('#start');
	record('1a boot: start overlay shows', startVisible);
	await boot(page);
	const png = await shot(page, '01-boot');
	const filled = countColour(png, [23, 33, 56], [135, 40, 710, 350]);
	record('1b boot: arena renders after tap', filled > 20000, `${filled} arena pixels`);
	const startHidden = !(await page.isVisible('#start'));
	record('1c boot: start overlay hidden', startHidden);
	await context.close();
}

async function scenarioJoystick(browser) {
	const session = await bootAsRole(browser, true);
	if (!session) return record('2 joystick: could not boot as attacker', false, 'no attacker ring found in 8 tries');
	const { context, page, ring } = session;
	const client = await context.newCDPSession(page);
	const before = await shot(page, '02-joystick-before');
	const start = { x: 120, y: 300 };
	const towardX = ring.x > 422 ? -60 : 60;
	const towardY = ring.y > 205 ? -60 : 60;
	await drag(client, 1, start, { x: start.x + towardX, y: start.y + towardY }, 8);
	await page.waitForTimeout(700);
	const during = await shot(page, '02-joystick-during');
	await release(client);
	const afterRing = findRing(during);
	const moved = afterRing ? Math.hypot(afterRing.x - ring.x, afterRing.y - ring.y) : 0;
	const knobVisible = countColour(during, [255, 255, 255], [20, 220, 220, 390]) > 10 || changedPixels(before, during, [20, 220, 220, 390]) > 50;
	record('2a joystick: ring character moved on drag', moved > 15, `moved ${moved.toFixed(1)} px, ring before (${ring.x.toFixed(0)},${ring.y.toFixed(0)})`);
	record('2b joystick: stick graphic drawn on touch', knobVisible);
	await page.waitForTimeout(1200);
	const rest1 = await shot(page, '02-joystick-rest1');
	await page.waitForTimeout(600);
	const rest2 = await shot(page, '02-joystick-rest2');
	const ring1 = findRing(rest1);
	const ring2 = findRing(rest2);
	const drift = ring1 && ring2 ? Math.hypot(ring1.x - ring2.x, ring1.y - ring2.y) : -1;
	record('2c joystick: character stops after release', drift >= 0 && drift < 4, `drift ${drift.toFixed(1)} px`);
	await context.close();
}

async function scenarioThrow(browser) {
	const session = await bootAsRole(browser, true);
	if (!session) return record('3a throw: could not boot as attacker', false, 'no attacker ring found in 8 tries');
	const { context, page, ring } = session;
	const client = await context.newCDPSession(page);
	// The first attacker in queue holds the sandal. If the human is not first, a bot throws first and the human waits.
	let held = false;
	for (let i = 0; i < 40 && !held; i++) {
		const png = await shot(page, '03-throw-wait');
		const r = findRing(png);
		held = r ? countColour(png, SANDAL_TAN, [Math.round(r.x) - 30, Math.round(r.y) - 30, Math.round(r.x) + 30, Math.round(r.y) + 30]) > 8 : false;
		if (!held) await page.waitForTimeout(500);
	}
	record('3a throw: human attacker holds a sandal', held);
	if (!held) return context.close();
	const before = await shot(page, '03-throw-before');
	// Scheme D: touch down on the fire button shows the lock and the dashed line, release fires.
	await touch(client, 'touchStart', [{ x: FIRE_BUTTON.x, y: FIRE_BUTTON.y, id: 2 }]);
	await page.waitForTimeout(250);
	const aiming = await shot(page, '03-throw-aiming');
	record('3b throw: preview line drawn while the button is held', changedPixels(before, aiming, [135, 40, 710, 350]) > 100);
	await touch(client, 'touchEnd', []);
	await page.waitForTimeout(350);
	const flight = await shot(page, '03-throw-flight');
	const r = findRing(before) || ring;
	const handSandals = countColour(before, SANDAL_TAN, [Math.round(r.x) - 30, Math.round(r.y) - 30, Math.round(r.x) + 30, Math.round(r.y) + 30]);
	const handSandalsAfter = countColour(flight, SANDAL_TAN, [Math.round(r.x) - 30, Math.round(r.y) - 30, Math.round(r.x) + 30, Math.round(r.y) + 30]);
	record('3c throw: sandal left the hand', handSandalsAfter < handSandals, `tan pixels near ring ${handSandals} -> ${handSandalsAfter}`);
	let advanced = false;
	for (let i = 0; i < 12 && !advanced; i++) {
		await page.waitForTimeout(500);
		const png = await shot(page, '03-throw-after');
		const hudThrows = countColour(png, [255, 255, 255], [370, 30, 480, 60]);
		advanced = hudThrows >= 0 && changedPixels(before, png, [370, 30, 480, 60]) > 60;
	}
	record('3d throw: round state advanced (throws-left HUD changed)', advanced);
	await context.close();
}

// One pass attempt toward the nearest teammate. Returns { tried, jumped, moved }. A try without the sandal does nothing.
async function tryPass(page, client, tag) {
	const before = await shot(page, `${tag}-before`);
	const me = findRing(before);
	const mates = findEnemyBodies(before).filter((m) => me && Math.hypot(m.x - me.x, m.y - me.y) > 25);
	if (!me || mates.length === 0) return { tried: false, jumped: false, moved: 0 };
	mates.sort((a, b) => Math.hypot(a.x - me.x, a.y - me.y) - Math.hypot(b.x - me.x, b.y - me.y));
	const dx = mates[0].x - me.x;
	const dy = mates[0].y - me.y;
	const length = Math.hypot(dx, dy) || 1;
	const from = { x: FIRE_BUTTON.x, y: FIRE_BUTTON.y };
	await drag(client, 3, from, { x: from.x + (dx / length) * 70, y: from.y + (dy / length) * 70 }, 8);
	await release(client);
	await page.waitForTimeout(700);
	const after = await shot(page, `${tag}-after`);
	const meAfter = findRing(after);
	const moved = meAfter ? Math.hypot(meAfter.x - me.x, meAfter.y - me.y) : 0;
	const jumped = !!meAfter && moved > 30 && Math.hypot(meAfter.x - mates[0].x, meAfter.y - mates[0].y) < 90;
	return { tried: true, jumped, moved };
}

async function scenarioDefenderPass(browser) {
	// A pass needs the scatter phase, and scatter needs a bot attacker to topple the stack. Try a few matches.
	let attempts = 0;
	let moved = 0;
	for (let match = 0; match < 4; match++) {
		const session = await bootAsRole(browser, false);
		if (!session) continue;
		const { context, page } = session;
		const client = await context.newCDPSession(page);
		for (let i = 0; i < 30; i++) {
			const result = await tryPass(page, client, '03-pass');
			if (result.tried) attempts++;
			moved = result.moved;
			if (result.jumped) {
				record('3e pass: control moved to the receiver after a pass', true, `match ${match + 1}, ${attempts} tries, ring moved ${moved.toFixed(1)} px`);
				return context.close();
			}
			await page.waitForTimeout(1000);
		}
		await context.close();
	}
	record('3e pass: control moved to the receiver after a pass', false, `${attempts} tries over 4 matches, last ring move ${moved.toFixed(1)} px`);
}

async function scenarioMultitouch(browser) {
	const session = await bootAsRole(browser, true);
	if (!session) return record('4 multitouch: could not boot as attacker', false, 'no attacker ring found');
	const { context, page } = session;
	const client = await context.newCDPSession(page);
	let held = false;
	let baseline = null;
	for (let i = 0; i < 40 && !held; i++) {
		baseline = await shot(page, '04-multi-wait');
		const r = findRing(baseline);
		held = r ? countColour(baseline, SANDAL_TAN, [Math.round(r.x) - 30, Math.round(r.y) - 30, Math.round(r.x) + 30, Math.round(r.y) + 30]) > 8 : false;
		if (!held) await page.waitForTimeout(500);
	}
	if (!held) return record('4 multitouch: human attacker never held a sandal', false), context.close();
	const ringStart = findRing(baseline);
	const left = { x: 110, y: 290 };
	await touch(client, 'touchStart', [{ x: left.x, y: left.y, id: 1 }]);
	for (let i = 1; i <= 8; i++) {
		await touch(client, 'touchMove', [{ x: left.x, y: left.y + i * 8, id: 1 }]);
		await page.waitForTimeout(16);
	}
	await touch(client, 'touchStart', [
		{ x: left.x, y: left.y + 64, id: 1 },
		{ x: FIRE_BUTTON.x, y: FIRE_BUTTON.y, id: 2 },
	]);
	for (let i = 1; i <= 6; i++) {
		await touch(client, 'touchMove', [
			{ x: left.x, y: left.y + 64, id: 1 },
			{ x: FIRE_BUTTON.x, y: FIRE_BUTTON.y, id: 2 },
		]);
		await page.waitForTimeout(16);
	}
	const both = await shot(page, '04-multi-both');
	const aimLine = changedPixels(baseline, both, [135, 40, 710, 350]);
	const stick = changedPixels(baseline, both, [20, 220, 220, 390]);
	record('4a multitouch: preview draws while stick held', aimLine > 100, `${aimLine} changed px in the arena`);
	record('4b multitouch: stick graphic stays while the fire button is held', stick > 50, `${stick} changed px on the left`);
	await touch(client, 'touchEnd', [{ x: left.x, y: left.y + 64, id: 1 }]);
	await page.waitForTimeout(500);
	const moving = await shot(page, '04-multi-released-throw');
	const ringNow = findRing(moving);
	const moved = ringStart && ringNow ? Math.hypot(ringNow.x - ringStart.x, ringNow.y - ringStart.y) : 0;
	record('4c multitouch: character moved while the other thumb aimed', moved > 15, `moved ${moved.toFixed(1)} px`);
	await touch(client, 'touchEnd', []);
	await context.close();
}

async function scenarioFullRound(browser) {
	// The human defends and the bots attack, so the human never has to throw for a round to be possible.
	const session = await bootAsRole(browser, false);
	if (!session) return record('5a full round: could not boot as defender', false);
	const { context, page } = session;
	const client = await context.newCDPSession(page);
	const pipBox = [95, 20, 175, 75];
	const start = await shot(page, '05-round-start');
	const startTint = countColour(start, FRIENDLY_BLUE, pipBox) + countColour(start, ENEMY_RED, pipBox);
	const pipsChanged = (png) => countColour(png, FRIENDLY_BLUE, pipBox) + countColour(png, ENEMY_RED, pipBox) > startTint + 15;
	let scored = false;
	for (let i = 0; i < 40 && !scored; i++) {
		await page.waitForTimeout(1000);
		scored = pipsChanged(await shot(page, '05-round-idle'));
	}
	note(scored ? 'idle human defender: the round ended on its own within 40 s' : 'idle human defender: no round end in 40 s, the round stalls while the human does nothing');
	let phase = 'idle';
	if (!scored) {
		phase = 'active';
		for (let i = 0; i < 50 && !scored; i++) {
			await tryPass(page, client, '05-round-active');
			await page.waitForTimeout(1200);
			scored = pipsChanged(await shot(page, '05-round-progress'));
		}
	}
	record('5a full round: a round ended and the score pips changed', scored, scored ? `ended after ${phase} play` : 'no pip change in 40 s idle plus about 100 s of passing');
	if (scored) {
		await page.waitForTimeout(3500);
		const next = await shot(page, '05-round-next');
		const ring = findRing(next);
		record('5b full round: next round started and the human ring is back', !!ring, ring ? '' : 'no ring found after round end');
	}
	await context.close();
}

async function scenarioIdleAttacker(browser) {
	const session = await bootAsRole(browser, true);
	if (!session) return note('idle attacker: could not boot as attacker');
	const { context, page } = session;
	let held = false;
	for (let i = 0; i < 20 && !held; i++) {
		const png = await shot(page, '05-idle-wait');
		const r = findRing(png);
		held = r ? countColour(png, SANDAL_TAN, [Math.round(r.x) - 30, Math.round(r.y) - 30, Math.round(r.x) + 30, Math.round(r.y) + 30]) > 8 : false;
		if (!held) await page.waitForTimeout(500);
	}
	if (!held) return note('idle attacker: human never got the sandal in 10 s'), context.close();
	await page.waitForTimeout(25000);
	const png = await shot(page, '05-idle-after-25s');
	const r = findRing(png);
	const stillHeld = r ? countColour(png, SANDAL_TAN, [Math.round(r.x) - 30, Math.round(r.y) - 30, Math.round(r.x) + 30, Math.round(r.y) + 30]) > 8 : false;
	note(stillHeld ? 'human attacker idle for 25 s still holds the sandal: no throw timer, an idle human stalls the round' : 'human attacker idle for 25 s: the sandal was thrown or the turn moved on');
	await context.close();
}

async function scenarioOrientation(browser) {
	const { context, page } = await newPage(browser);
	await boot(page);
	await page.setViewportSize(PORTRAIT);
	await page.waitForTimeout(800);
	const overlay = await page.isVisible('#rotate');
	await shot(page, '06-portrait');
	record('6a orientation: rotate overlay shows in portrait', overlay);
	await page.setViewportSize(LANDSCAPE);
	await page.waitForTimeout(1500);
	const overlayGone = !(await page.isVisible('#rotate'));
	const png = await shot(page, '06-landscape-again');
	const filled = countColour(png, [23, 33, 56], [135, 40, 710, 350]);
	record('6b orientation: overlay hides and arena redraws in landscape', overlayGone && filled > 15000, `${filled} arena pixels`);
	await context.close();
}

const browser = await chromium.launch({
	executablePath: process.env.CHROME_PATH || '/usr/bin/google-chrome',
	headless: true,
	args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'],
});

const scenarios = [scenarioBoot, scenarioJoystick, scenarioThrow, scenarioDefenderPass, scenarioMultitouch, scenarioFullRound, scenarioIdleAttacker, scenarioOrientation];
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

if (only.length === 0) record('7 console: no error messages during the run', consoleErrors.length === 0, consoleErrors.slice(0, 3).join(' | '));
fs.writeFileSync(path.join(OUT, 'report.json'), JSON.stringify({ results, notes, consoleErrors }, null, 2));
const failed = results.filter((r) => !r.pass).length;
console.log(`\n${results.length - failed}/${results.length} checks pass. Screenshots and report.json are in ${OUT}`);
process.exit(failed === 0 ? 0 : 1);
