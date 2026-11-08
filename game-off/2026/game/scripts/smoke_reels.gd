class_name SmokeReels
extends RefCounted
## Smoke checks of the reels and the share code: seed codes, URL parsing, best-chain tracking, the death reel, and a run that ends and reaches the Locker.

## Seeds tried in the round trip.
const ROUND_TRIP_SEEDS: int = 100
## Codes that must not decode.
const BAD_CODES: Array[String] = ["", "HS-", "HS-4F2K9", "HS-4F2K9AA", "HS-4F2K9U", "HS-!!!!!!", "seed", "HS-4F2 K9"]
## Most rooms scanned for a long failing attempt.
const SCAN_ROOMS: int = 178

var _smoke: Smoke
var _main: HotSwapMain


## Binds the checks to [param smoke], which owns the game and the input helpers.
func _init(smoke: Smoke) -> void:
	_smoke = smoke
	_main = smoke.main


## Runs every check. Returns false after the first error.
func run_all() -> bool:
	if not _check_codes() or not _check_tracker() or not _check_death_timeline():
		return false
	if not await _check_scripted_chain():
		return false
	return await _check_run_end_to_locker()


func _check_codes() -> bool:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 5
	var seeds: Array[int] = [1, 2, 31, 32, 777, 12345, RoomGen.daily_seed(), SeedCode.MAX_SEED]
	for i: int in ROUND_TRIP_SEEDS - seeds.size():
		seeds.append(RunState.new_seed(rng.randi()))
	for seed_value: int in seeds:
		var code: String = SeedCode.encode(seed_value)
		if SeedCode.decode(code) != seed_value or not code.begins_with("HS-") or code.length() != 9:
			_smoke.fail("seed %d gives code %s that decodes to %d" % [seed_value, code, SeedCode.decode(code)])
			return false
	for code: String in BAD_CODES:
		if SeedCode.decode(code) != 0:
			_smoke.fail("invalid code '%s' decoded to %d" % [code, SeedCode.decode(code)])
			return false
	var code: String = SeedCode.encode(424242)
	var queries: Array[String] = ["?seed=%s" % code, "?a=1&seed=%s&b=2" % code.to_lower(), "seed=%s" % code.replace("HS-", "")]
	for query: String in queries:
		if SeedCode.from_query(query) != 424242:
			_smoke.fail("query '%s' parsed to %d, not 424242" % [query, SeedCode.from_query(query)])
			return false
	for query: String in ["", "?", "?seed=", "?seed=zzzz", "?other=%s" % code, "?seed=HS-ÿÿÿÿÿÿ"]:
		if SeedCode.from_query(query) != 0:
			_smoke.fail("bad query '%s' parsed to %d" % [query, SeedCode.from_query(query)])
			return false
	_main.start_run(SeedCode.from_query("?seed=" + SeedCode.encode(31415)))
	if _main.run.seed != 31415 or _main.run.rooms[0]["id"] != RunState.new(31415).rooms[0]["id"]:
		_smoke.fail("a tower started from ?seed= has seed %d" % _main.run.seed)
		return false
	var fallback: int = SeedCode.from_query("?seed=nonsense")
	_main.start_run(fallback if fallback > 0 else RunState.new_seed())
	print("SHARE OK: %d seeds round-trip through HS-XXXXXX, %d invalid codes and 6 bad queries give 0, ?seed= starts that tower" % [ROUND_TRIP_SEEDS, BAD_CODES.size()])
	return true


func _check_tracker() -> bool:
	var tracker: ChainTracker = ChainTracker.new()
	var none: Array[int] = []
	var rooms: Array[Dictionary] = [{"id": "a"}, {"id": "b"}, {"id": "c"}, {"id": "d"}]
	for i: int in 4:
		tracker.consider([2, 3, 3, 1][i], rooms[i], [i, i], none, 1, i + 1)
	if tracker.kills != 3 or tracker.room["id"] != "b" or tracker.number != 2 or tracker.taps != [1, 1]:
		_smoke.fail("tracker kept kills %d in room %s, not the earlier 3 in b" % [tracker.kills, tracker.room.get("id")])
		return false
	print("CHAIN TRACKER OK: the highest count wins and a tie keeps the earlier shift")
	return true


func _check_death_timeline() -> bool:
	var found: int = 0
	var checked: int = 0
	for room: Dictionary in Pool.rooms().slice(0, SCAN_ROOMS):
		var taps: Array[int] = _long_fail(RoomState.from_room(room), 5)
		if taps.size() < 4:
			taps = _long_fail(RoomState.from_room(room), 4)
		if taps.size() < 4:
			continue
		checked += 1
		var timeline: TurnEvents = Reels.death_timeline(room, taps, BoonSet.new())
		var last: Array = timeline.turns[-1]["events"]
		var types: Array[String] = []
		for event: Dictionary in last:
			types.append(str(event["type"]))
		var skipped: RoomState = RoomState.from_room(room)
		for tap: int in taps.slice(0, taps.size() - Reels.DEATH_SWAPS):
			HotSwapRules.resolve(skipped, tap)
		if timeline.turns.size() != Reels.DEATH_SWAPS or not ("hero_hit" in types or "knife_contact" in types) or timeline.start_room["hero"] != skipped.hero or timeline.start_room["alive"] != skipped.alive:
			_smoke.fail("death timeline of room %s: %d turns, last events %s" % [room["id"], timeline.turns.size(), types])
			return false
		found += 1
		if found == 3:
			break
	if found == 0:
		_smoke.fail("no pool room has a failing attempt of 4 shifts for the death reel check")
		return false
	print("DEATH REEL TIMELINE OK: %d failing attempts of 4 or 5 shifts give 3 shifts that end in a hero hit, earlier shifts fast-forwarded" % found)
	return true


## Returns [param left] safe swaps then a fatal one, or a shorter fatal path when none is that long.
func _long_fail(state: RoomState, left: int) -> Array[int]:
	for tap: int in state.guns.size():
		if not state.alive[tap]:
			continue
		var next: RoomState = state.clone()
		var res: HotSwapRules.Resolution = HotSwapRules.resolve(next, tap)
		if res.hero_dead:
			if left == 1:
				return [tap]
			continue
		if left > 1 and next.alive_count() > 0:
			var rest: Array[int] = _long_fail(next, left - 1)
			if not rest.is_empty():
				var out: Array[int] = [tap]
				out.append_array(rest)
				return out
	return []


func _check_scripted_chain() -> bool:
	var pick: Dictionary = {}
	var best_index: int = 0
	var best_kills: int = 0
	var tied: bool = false
	for room: Dictionary in Pool.rooms():
		if int(room["par"]) < 2:
			continue
		var counts: Array[int] = _swap_kills(room, HotSwapRules.solve(RoomState.from_room(room)))
		var peak: int = counts.max()
		var ties: bool = counts.count(peak) > 1
		if pick.is_empty() or (ties and not tied):
			pick = room
			best_kills = peak
			best_index = counts.find(peak)
			tied = ties
		if tied:
			break
	_main.start_run(2468)
	_main.play_room(pick)
	var plan: Array[int] = HotSwapRules.solve(_main.room_state())
	for tap: int in plan:
		if not await _smoke.click_gun(tap):
			return false
	var chain: ChainTracker = _main.run.chain
	var expected: Array[int] = plan.slice(0, best_index + 1)
	if chain.kills != best_kills or chain.taps != expected or chain.room != pick:
		_smoke.fail("best chain of a scripted room: %d kills after taps %s, expected %d after %s" % [chain.kills, chain.taps, best_kills, expected])
		return false
	print("BEST CHAIN OK: scripted room %s picks shift %d of %d with %d kills (tie in the room: %s)" % [pick["id"], best_index + 1, plan.size(), best_kills, tied])
	await _smoke.finish_replay(1)
	return true


func _swap_kills(room: Dictionary, plan: Array[int]) -> Array[int]:
	var state: RoomState = RoomState.from_room(room)
	var counts: Array[int] = []
	for tap: int in plan:
		counts.append(HotSwapRules.resolve(state, tap).kill_count())
	return counts


## A tower: clear room 1, fail room 2 three times, watch the death reel, the chain and the copy button, then reach the Locker. Every reel is skipped by a tap.
func _check_run_end_to_locker() -> bool:
	_main.start_run(1357)
	var plan: Array[int] = HotSwapRules.solve(_main.room_state())
	for tap: int in plan:
		if not await _smoke.click_gun(tap):
			return false
	if not await _smoke.finish_replay(1) or _main.phase != HotSwapMain.Phase.DOOR:
		_smoke.fail("room 1 of the end-to-end tower did not reach the door screen: phase %d" % _main.phase)
		return false
	var offers: Array[int] = _main.door_offers()
	_smoke.click(Hud.DOOR_RECTS[0 if offers[0] != RunState.Door.BOON else 1].get_center())
	await _smoke.get_tree().process_frame
	if _main.phase != HotSwapMain.Phase.PLAN:
		_smoke.fail("door pick did not open room 2: phase %d" % _main.phase)
		return false
	var hearts: int = _main.run.hearts
	for attempt: int in hearts:
		for tap: int in _smoke.failing_taps(true):
			if not await _smoke.click_gun(tap):
				return false
		if attempt < hearts - 1:
			_smoke.click(Smoke.CORNER)
			await _smoke.get_tree().process_frame
	if not await _skip_reel(HotSwapMain.Reel.DEATH, "NIGHT OVER"):
		return false
	var timeline: TurnEvents = _main.last_timeline
	if timeline.turns.size() > Reels.DEATH_SWAPS or _main.phase != HotSwapMain.Phase.END or _main.end_title() != "NIGHT OVER":
		_smoke.fail("death reel: %d turns, phase %d, title '%s'" % [timeline.turns.size(), _main.phase, _main.end_title()])
		return false
	await _smoke.get_tree().create_timer(0.5, true, false, true).timeout
	_smoke.click(Hud.END_RECTS[0].get_center())
	await _smoke.get_tree().process_frame
	var kills: int = _main.run.chain.kills
	if not await _skip_reel(HotSwapMain.Reel.CHAIN_WATCH, "BEST CHAIN: %s" % Reels.counted(kills, "kill")) or _main.phase != HotSwapMain.Phase.END:
		return false
	_smoke.click(Hud.END_RECTS[1].get_center())
	await _smoke.get_tree().process_frame
	if _main.hud.copy_button_text() != "COPIED" and _main.hud.link_text() == "":
		_smoke.fail("COPY LINK showed neither COPIED nor the link text")
		return false
	_smoke.key(KEY_R)
	await _smoke.get_tree().process_frame
	if not await _skip_reel(HotSwapMain.Reel.REVIEW, "ROOM CLEAR") or _main.phase != HotSwapMain.Phase.END:
		return false
	_smoke.click(Smoke.CORNER)
	await _smoke.get_tree().process_frame
	var footer: String = _main.hud.locker.seed_text()
	if _main.phase != HotSwapMain.Phase.LOCKER or not footer.ends_with(SeedCode.encode(1357)):
		_smoke.fail("Locker after the death reel: phase %d, footer '%s'" % [_main.phase, footer])
		return false
	print("RUN END OK: death reel, WATCH BEST CHAIN (%s), COPY LINK (%s), R replay, each skipped by a tap, then the Locker shows '%s'" % [Reels.counted(kills, "kill"), _main.hud.copy_button_text() if _main.hud.link_text() == "" else "link text", footer])
	return true


## Checks a reel of [param kind] plays with [param card] on its title card, then skips it with a tap in time.
func _skip_reel(kind: HotSwapMain.Reel, card: String) -> bool:
	await _smoke.get_tree().process_frame
	if _main.phase != HotSwapMain.Phase.REPLAY or _main.last_reel != kind or _main.reel_card_title() != card:
		_smoke.fail("reel %d: phase %d, kind %d, card '%s' (wanted '%s')" % [kind, _main.phase, _main.last_reel, _main.reel_card_title(), card])
		return false
	await _smoke.get_tree().create_timer(0.3, true, false, true).timeout
	var started: int = Time.get_ticks_msec()
	_smoke.click(Smoke.CORNER)
	await _smoke.get_tree().process_frame
	if _main.phase == HotSwapMain.Phase.REPLAY or Time.get_ticks_msec() - started > Smoke.SKIP_LIMIT_MS:
		_smoke.fail("a tap did not skip reel %d in time: phase %d" % [kind, _main.phase])
		return false
	return true
