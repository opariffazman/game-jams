class_name SmokeUndo
extends RefCounted
## Smoke checks of the undo, the dead-end banner, RETRY, and the detector, through the real input path.

## Detector samples compared with a brute force.
const SAMPLES: int = 20
## Node cap small enough to stop any search on a real room.
const TINY_CAP: int = 2
## A screen point that hits no gunman and no button.
const CORNER: Vector2 = Vector2(5, 5)

var _smoke: Smoke


## Binds the checks to [param smoke], which owns the game and the input helpers.
func _init(smoke: Smoke) -> void:
	_smoke = smoke


## Runs every check. Returns false after the first error.
func run() -> bool:
	return await _undo_restores() and await _boss_phase() and await _dead_end_banner() and _unknown_at_cap() and _matches_brute_force() and await _replay_after_undo()


## Returns the first pool room and tap whose first shift is safe, leaves gunmen, and satisfies [param want_dead] against the room budget. Empty when none.
func _find(want_dead: bool, boons: BoonSet = null, want_coat: bool = false) -> Dictionary:
	for room: Dictionary in Pool.rooms():
		var base: RoomState = RoomState.from_room(room)
		var budget: int = int(room["par"]) + RoomGen.slack_for(int(room["floor"]))
		for tap: int in base.guns.size():
			var next: RoomState = base.clone()
			var res: HotSwapRules.Resolution = HotSwapRules.resolve(next, tap, boons)
			if res.hero_dead or next.alive_count() == 0 or (want_coat and not res.coat_used):
				continue
			var dead: bool = DeadEnd.verdict(next, budget - 1, boons, DeadEnd.OFFLINE_CAP) == DeadEnd.Verdict.DEAD
			if dead == want_dead:
				return {"room": room, "tap": tap}
	return {}


func _same_state(a: RoomState, b: RoomState) -> bool:
	return a.hero == b.hero and a.guns == b.guns and a.alive == b.alive and a.turn == b.turn and a.coat_spent == b.coat_spent and a.kinds == b.kinds


func _undo_restores() -> bool:
	var main: HotSwapMain = _smoke.main
	main.start_run(901)
	main.run.add_boon(BoonSet.Boon.COAT)
	var found: Dictionary = _find(false, BoonSet.from_owned([BoonSet.Boon.COAT] as Array[int]), true)
	if found.is_empty():
		_smoke.fail("no room where the first shift spends the coat")
		return false
	var tap: int = found["tap"]
	main.play_room(found["room"])
	var before: RoomState = main.room_state().clone()
	if main.undo.left != 1 or main.controls.undo_at(Vector2(0, 0)) or not main.controls.undo_at(PlayControls.UNDO_RECT.get_center()):
		_smoke.fail("undo stock %d before the first shift" % main.undo.left)
		return false
	if main.undo_shift():
		_smoke.fail("undo ran before any shift")
		return false
	if not await _smoke.click_gun(tap) or main.phase != HotSwapMain.Phase.PLAN or not main.room_state().coat_spent or main.swaps != 1:
		_smoke.fail("setup shift: phase %d, coat %s, shifts %d" % [main.phase, main.room_state().coat_spent, main.swaps])
		return false
	_smoke.click(PlayControls.UNDO_RECT.get_center())
	await _smoke.get_tree().process_frame
	if not _same_state(main.room_state(), before) or main.swaps != 0 or not main.taps.is_empty() or main.undo.left != 0 or main.phase != HotSwapMain.Phase.PLAN:
		_smoke.fail("undo did not restore the room: swaps %d, taps %s, coat %s, undo left %d" % [main.swaps, main.taps, main.room_state().coat_spent, main.undo.left])
		return false
	var other: int = -1
	for i: int in before.guns.size():
		if i != tap and not HotSwapRules.resolve(before.clone(), i, main.play.boons).hero_dead and HotSwapRules.resolve(before.clone(), i, main.play.boons).kill_count() < before.alive_count():
			other = i
			break
	if other < 0 or not await _smoke.click_gun(other):
		_smoke.fail("no second shift to test the refused undo")
		return false
	var after: RoomState = main.room_state().clone()
	_smoke.key(KEY_U)
	_smoke.click(PlayControls.UNDO_RECT.get_center())
	await _smoke.get_tree().process_frame
	if main.swaps != 1 or not _same_state(main.room_state(), after) or main.undo.left != 0:
		_smoke.fail("a second undo in one room was not refused: swaps %d, undo left %d" % [main.swaps, main.undo.left])
		return false
	print("UNDO OK: one tap on UNDO restores positions, alive flags, turn, coat and the shift used, and a second undo in the room is refused")
	return true


func _boss_phase() -> bool:
	var main: HotSwapMain = _smoke.main
	main.start_run(902)
	main.run.room_index = RunState.ROOM_COUNT - 1
	main.enter_room()
	_smoke.click(CORNER)
	await _smoke.get_tree().process_frame
	for phase_number: int in 2:
		var base: RoomState = main.room_state().clone()
		var tap: int = -1
		for i: int in base.guns.size():
			var probe: RoomState = base.clone()
			if not HotSwapRules.resolve(probe, i).hero_dead and probe.alive_count() > 0:
				tap = i
				break
		if tap < 0 or main.undo.left != 1 or not await _smoke.click_gun(tap):
			_smoke.fail("boss phase %d undo setup: tap %d, undo left %d" % [phase_number + 1, tap, main.undo.left])
			return false
		_smoke.key(KEY_U)
		await _smoke.get_tree().process_frame
		if main.swaps != 0 or not _same_state(main.room_state(), base) or main.undo.left != 0 or main.run.boss_phase != phase_number + 1:
			_smoke.fail("boss phase %d undo: swaps %d, undo left %d" % [phase_number + 1, main.swaps, main.undo.left])
			return false
		if phase_number == 0:
			for solve_tap: int in HotSwapRules.solve(main.room_state(), 6, main.run.boon_set()):
				if not await _smoke.click_gun(solve_tap):
					return false
			_smoke.click(CORNER)
			await _smoke.get_tree().process_frame
	print("UNDO BOSS OK: undo works in boss phases 1 and 2, and each phase starts with a fresh undo")
	return true


func _dead_end_banner() -> bool:
	var main: HotSwapMain = _smoke.main
	main.start_run(903)
	var found: Dictionary = _find(true)
	if found.is_empty():
		_smoke.fail("no pool room with a dead-end first shift")
		return false
	var tap: int = found["tap"]
	main.play_room(found["room"])
	var before: RoomState = main.room_state().clone()
	if not await _smoke.click_gun(tap):
		return false
	var reason: String = main.controls.dead_end_reason()
	if reason == "" or reason not in DeadEnd.REASONS or not main.controls.undo_lit() or main.controls.retry_shown():
		_smoke.fail("dead end shows reason '%s', lit %s, retry %s" % [reason, main.controls.undo_lit(), main.controls.retry_shown()])
		return false
	_smoke.key(KEY_U)
	await _smoke.get_tree().process_frame
	if main.controls.dead_end_reason() != "" or not _same_state(main.room_state(), before):
		_smoke.fail("the banner stayed or the room differs after undo")
		return false
	print("DEAD END OK: a known dead end shows NO WAY OUT with '%s', UNDO lights up, and undo clears the banner" % reason)
	var hearts: int = main.run.hearts
	if not await _smoke.click_gun(tap) or not main.controls.retry_shown() or main.controls.undo_lit():
		_smoke.fail("with undo spent the banner shows no RETRY")
		return false
	_smoke.click(PlayControls.RETRY_RECT.get_center())
	await _smoke.get_tree().process_frame
	if main.run.hearts != hearts - 1 or main.phase != HotSwapMain.Phase.PLAN or main.swaps != 0 or not _same_state(main.room_state(), before) or main.undo.left != 1 or main.controls.dead_end_reason() != "":
		_smoke.fail("RETRY: hearts %d (was %d), phase %d, shifts %d, undo left %d" % [main.run.hearts, hearts, main.phase, main.swaps, main.undo.left])
		return false
	print("RETRY OK: with undo spent RETRY costs one heart and reloads the same room with a fresh undo")
	return true


func _unknown_at_cap() -> bool:
	var found: Dictionary = _find(true)
	var room: Dictionary = found["room"]
	var next: RoomState = RoomState.from_room(room)
	HotSwapRules.resolve(next, int(found["tap"]))
	var left: int = int(room["par"]) + RoomGen.slack_for(int(room["floor"])) - 1
	var capped: Dictionary = DeadEnd.analyze(next, left, null, TINY_CAP)
	if capped["verdict"] != DeadEnd.Verdict.UNKNOWN or capped.has("reason"):
		_smoke.fail("a capped search returned %s" % [capped])
		return false
	if DeadEnd.analyze(next, left)["verdict"] != DeadEnd.Verdict.DEAD:
		_smoke.fail("the default cap cannot prove the known dead end in room %s" % room["id"])
		return false
	print("DETECTOR CAP OK: a search stopped at %d nodes reports unknown with no banner, and the default cap still proves a real room" % TINY_CAP)
	return true


func _matches_brute_force() -> bool:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 77
	var rooms: Array[Dictionary] = Pool.rooms()
	var checked: int = 0
	var dead: int = 0
	while checked < SAMPLES:
		var state: RoomState = RoomState.from_room(rooms[rng.randi_range(0, rooms.size() - 1)])
		var boons: BoonSet = BoonSet.from_owned([BoonSet.Boon.QUICK_DRAW, BoonSet.Boon.COAT] as Array[int]) if checked % 4 == 3 else null
		var steps: int = rng.randi_range(0, 2)
		var alive_ok: bool = true
		for step: int in steps:
			var live: Array[int] = []
			for i: int in state.guns.size():
				if state.alive[i]:
					live.append(i)
			alive_ok = alive_ok and not HotSwapRules.resolve(state, live[rng.randi_range(0, live.size() - 1)], boons).hero_dead and state.alive_count() > 0
		if not alive_ok:
			continue
		var left: int = rng.randi_range(1, 4)
		var expected: bool = not HotSwapRules.solve(state, left, boons).is_empty()
		var got: DeadEnd.Verdict = DeadEnd.verdict(state, left, boons, DeadEnd.OFFLINE_CAP)
		if got == DeadEnd.Verdict.UNKNOWN or (got == DeadEnd.Verdict.WIN) != expected:
			_smoke.fail("detector says %d, brute force wins %s, sample %d, shifts left %d" % [got, expected, checked, left])
			return false
		checked += 1
		dead += 0 if expected else 1
	print("DETECTOR MATCH OK: %d sampled states (%d dead), the detector equals the brute force, with and without boons" % [checked, dead])
	return true


func _replay_after_undo() -> bool:
	var main: HotSwapMain = _smoke.main
	main.start_run(904)
	var found: Dictionary = _find(false)
	var room: Dictionary = found["room"]
	main.play_room(room)
	var slip: int = int(found["tap"])
	if not await _smoke.click_gun(slip):
		return false
	_smoke.key(KEY_U)
	await _smoke.get_tree().process_frame
	var plan: Array[int] = HotSwapRules.solve(main.room_state(), 6, main.run.boon_set())
	if plan.is_empty() or main.undo.left != 0:
		_smoke.fail("no plan after undo, or the stock is %d" % main.undo.left)
		return false
	for tap: int in plan:
		if not await _smoke.click_gun(tap):
			return false
	if main.phase != HotSwapMain.Phase.REPLAY or main.taps != plan:
		_smoke.fail("taps after undo are %s, plan %s, phase %d" % [main.taps, plan, main.phase])
		return false
	var deadline: int = Time.get_ticks_msec() + Smoke.REPLAY_WAIT_MS
	while main.phase == HotSwapMain.Phase.REPLAY:
		if Time.get_ticks_msec() > deadline:
			_smoke.fail("replay after undo timed out")
			return false
		await _smoke.get_tree().process_frame
	if main.replay_outcome != main.live_outcome:
		_smoke.fail("replay after undo differs from live: %s vs %s" % [main.replay_outcome, main.live_outcome])
		return false
	print("UNDO REPLAY OK: a clear that used undo records only the kept shifts and the replay reproduces the live outcome")
	return true
