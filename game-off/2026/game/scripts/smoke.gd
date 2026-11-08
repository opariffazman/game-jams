class_name Smoke
extends Node
## Headless self-play through the real input path: pool and tower checks, a bot that clears all 12 rooms, fail and retry, three fails, and the save.

## Rooms before the boss, whose ids the boss rooms must not repeat.
const ROOM_ID_SCAN: int = 11
## Longest wait for one resolution, in milliseconds.
const WAIT_MS: int = 8000
## Longest wait for a full replay, in milliseconds.
const REPLAY_WAIT_MS: int = 90000
## Slowest allowed reaction to a tap, in milliseconds.
const SKIP_LIMIT_MS: int = 200
## Expected swap slack per gate set, F1 to final.
const SLACK_BY_GATE: Array[int] = [2, 1, 1, 0, 0]
## A screen point that hits no gunman and no door.
const CORNER: Vector2 = Vector2(5, 5)

## Game under test.
var main: HotSwapMain

var _sim_boons: BoonSet = BoonSet.new()


## Runs the smoke test against [param target] and quits with a result.
func run(target: HotSwapMain) -> void:
	main = target
	await get_tree().process_frame
	if not _check_pool() or not _check_towers():
		return
	var rule_error: String = RuleChecks.run()
	if rule_error != "":
		fail(rule_error)
		return
	if not _check_timelines():
		return
	if main.has_replay_3d():
		fail("3D replay layer exists before the first replay")
		return
	if not await SmokeUndo.new(self).run():
		return
	if not await _play_full_run() or not _check_persistence() or not await SmokeLocker.new(self).win_to_new_tower():
		return
	if not await _check_fails_and_restart() or not await SmokeBoss.new(self).intro_auto():
		return
	if not await SmokeBoss.new(self).telegraph_input() or not await SmokeReels.new(self).run_all():
		return
	if not await SmokeLocker.new(self).upgrades():
		return
	DirAccess.remove_absolute(SaveData.path)
	print("SMOKE OK")
	get_tree().quit(0)


func _check_pool() -> bool:
	var rooms: Array[Dictionary] = Pool.rooms()
	var counts: Dictionary = {}
	for room: Dictionary in rooms:
		var level: int = int(room["floor"])
		counts[level] = int(counts.get(level, 0)) + 1
		var solved: int = HotSwapRules.solve(RoomState.from_room(room)).size()
		if solved == 0 or solved != int(room["par"]) or not room.has("motif") or not room.has("id"):
			fail("pool room %s: solver %d, par %s" % [room.get("id"), solved, room.get("par")])
			return false
		var mirrored: Dictionary = Rooms.mirror(room)
		if HotSwapRules.solve(RoomState.from_room(mirrored)).size() != solved:
			fail("mirrored copy of %s has another par" % room["id"])
			return false
	for level: int in range(1, RoomGen.FINAL_FLOOR + 1):
		if int(counts.get(level, 0)) < 10:
			fail("gate set %d has only %d rooms" % [level, counts.get(level, 0)])
			return false
	for level: int in range(1, RoomGen.FINAL_FLOOR + 1):
		var floor_rooms: Array[Dictionary] = Pool.of_floor(level)
		var traps: int = floor_rooms.filter(func(item: Dictionary) -> bool: return bool(item["trap"])).size()
		if float(traps) / floor_rooms.size() < float(RoomGen.GATES[level - 1]["trap_share"]) - 0.001:
			fail("gate set %d has trap share %d / %d, below its gate" % [level, traps, floor_rooms.size()])
			return false
	for room: Dictionary in rooms:
		if float(room["dead"]) > float(RoomGen.GATES[int(room["floor"]) - 1]["dead_share"]) + 0.001:
			fail("pool room %s has dead-end share %s above its gate" % [room["id"], room["dead"]])
			return false
	PoolGen.print_table(rooms)
	PoolGen.print_kind_table(rooms)
	print("POOL OK: %d rooms, par equals solver minimum, mirrored copies keep par" % rooms.size())
	return true


func _check_towers() -> bool:
	for seed_value: int in range(1, 61):
		var tower: RunState = RunState.new(seed_value)
		if not _tower_valid(tower, "seed %d" % seed_value):
			return false
		var offers: Array[int] = tower.door_offers()
		if offers[0] == offers[1] or offers != RunState.new(seed_value).door_offers():
			fail("doors for seed %d are equal or not seeded: %s" % [seed_value, offers])
			return false
	for seed_value: int in range(1, 31):
		var tower: RunState = RunState.new(seed_value)
		for index: int in 4:
			tower.apply_door(RunState.Door.TIPS)
		tower.apply_door(RunState.Door.ELITE)
		var elite: Dictionary = tower.current_room()
		if not bool(elite.get("elite")) or int(elite["floor"]) != RunState.gate_floor_of(5) + 1:
			fail("elite room has gate set %s after room 5" % elite.get("floor"))
			return false
		if not _tower_valid(tower, "elite seed %d" % seed_value):
			return false
	if not _check_boss_rooms():
		return false
	var last: RunState = RunState.new(5)
	last.room_index = RunState.ROOM_COUNT - 2
	if RunState.Door.ELITE in last.door_offers():
		fail("elite offered before the final room")
		return false
	print("TOWERS OK: 60 seeds, no repeated room, no repeated motif in a row, seeded doors, elite draws from the next gate set")
	return true


func _check_boss_rooms() -> bool:
	var exact: Array[int] = [0, 0, 0]
	for seed_value: int in range(1, 61):
		var tower: RunState = RunState.new(seed_value)
		var ids: Array[String] = []
		for room: Dictionary in tower.boss_rooms:
			ids.append(str(room["id"]))
			if int(room["floor"]) != RoomGen.FINAL_FLOOR:
				fail("boss room %s is not from the final gate set" % room["id"])
				return false
		for i: int in ROOM_ID_SCAN:
			ids.append(str(tower.rooms[i]["id"]))
		var distinct: Dictionary = {}
		for id: String in ids:
			distinct[id] = true
		if tower.boss_rooms.size() != 3 or distinct.size() != ids.size() or tower.rooms[11] != tower.boss_rooms[0]:
			fail("boss rooms of seed %d repeat a room: %s" % [seed_value, ids])
			return false
		var types: Array[Array] = []
		for room: Dictionary in tower.boss_rooms:
			var found: Array[String] = []
			for event: Dictionary in room["events"]:
				found.append(str(event["type"]))
			types.append(found)
		exact[0] += 1 if types[0].is_empty() else 0
		var reinforced: bool = false
		for event: Dictionary in tower.boss_rooms[1]["events"]:
			reinforced = reinforced or (event["type"] == "reinforce" and int(event["turn"]) == 1)
		exact[1] += 1 if reinforced else 0
		exact[2] += 1 if "jam" in types[2] and "advance" in types[2] else 0
	if exact != [60, 60, 60]:
		fail("boss phases that miss their event spec in 60 seeds: plain %d, reinforce turn 1 %d, jam+advance %d (of 60)" % [exact[0], exact[1], exact[2]])
		return false
	print("BOSS ROOMS OK: 60 seeds, three different final-gate rooms each, phase 1 plain, phase 2 reinforces on turn 1, phase 3 has jam and advance")
	return true


func _tower_valid(tower: RunState, label: String) -> bool:
	var seen: Dictionary = {}
	for i: int in tower.rooms.size():
		var room: Dictionary = tower.rooms[i]
		if seen.has(room["id"]):
			fail("%s repeats room %s" % [label, room["id"]])
			return false
		seen[room["id"]] = true
		if i > 0 and room["motif"] == tower.rooms[i - 1]["motif"]:
			fail("%s repeats motif %s at room %d" % [label, room["motif"], i])
			return false
	return tower.rooms.size() == RunState.ROOM_COUNT


func _check_timelines() -> bool:
	for r: int in 3:
		var room: Dictionary = RunState.new(99).rooms[r]
		var taps: Array[int] = HotSwapRules.solve(RoomState.from_room(room))
		var timeline: TurnEvents = TurnEvents.build(room, taps)
		var live: RoomState = RoomState.from_room(room)
		var live_dead: Array[int] = []
		for tap: int in taps:
			var res: HotSwapRules.Resolution = HotSwapRules.resolve(live, tap)
			live_dead.append_array(res.struck)
			live_dead.append_array(res.killed)
		var timeline_dead: Array[int] = timeline.dead_guns()
		live_dead.sort()
		timeline_dead.sort()
		if timeline.turns.size() != taps.size() or timeline_dead != live_dead or timeline.final_state.alive != live.alive:
			fail("timeline victims %s differ from live %s in room %d" % [timeline_dead, live_dead, r + 1])
			return false
	var moving: Array[Dictionary] = Pool.rooms().filter(func(item: Dictionary) -> bool: return RoomState.Kind.KNIFE in item["kinds"] or "advance" in item["events"].map(func(event: Dictionary) -> String: return event["type"]))
	for item: Dictionary in moving.slice(0, 15):
		var taps: Array[int] = HotSwapRules.solve(RoomState.from_room(item))
		var timeline: TurnEvents = TurnEvents.build(item, taps)
		var live: RoomState = RoomState.from_room(item)
		for tap: int in taps:
			HotSwapRules.resolve(live, tap)
		if timeline.final_state.guns != live.guns:
			fail("replay steps of room %s end in other cells than the live rules" % item["id"])
			return false
	print("TIMELINES OK: 3 rooms, and the knife and advance steps of 15 more match the live rules")
	return true


func _play_full_run() -> bool:
	main.start_run(12345)
	var tower: RunState = main.run
	var played_ids: Array[String] = []
	for i: int in RunState.ROOM_COUNT:
		if i == RunState.ROOM_COUNT - 1:
			if not await SmokeBoss.new(self).play(played_ids):
				return false
			break
		var room: Dictionary = tower.current_room()
		played_ids.append(str(room["id"]))
		var gate: int = int(room["floor"])
		var spare: int = 1 if BoonSet.Boon.SPARE_CLIP in tower.boons else 0
		if main.budget != int(room["par"]) + SLACK_BY_GATE[gate - 1] + spare:
			fail("room %d budget %d, par %s, gate set %d" % [i + 1, main.budget, room["par"], gate])
			return false
		var plan: Array[int] = HotSwapRules.solve(main.room_state(), 6, tower.boon_set())
		if plan.is_empty():
			fail("room %d has no solution with boons %s" % [i + 1, tower.boons])
			return false
		for tap: int in plan:
			if not await click_gun(tap):
				return false
		if main.phase != HotSwapMain.Phase.REPLAY or main.swaps > main.budget:
			fail("room %d not cleared, phase %d, shifts %d / %d" % [i + 1, main.phase, main.swaps, main.budget])
			return false
		if not await finish_replay(i):
			return false
		if not await _check_replay_key_and_pick_door(i):
			return false
	if main.phase == HotSwapMain.Phase.REPLAY and main.last_reel == HotSwapMain.Reel.CHAIN_WIN:
		if not main.reel_card_title().begins_with("BEST CHAIN: "):
			fail("win chain card reads '%s'" % main.reel_card_title())
			return false
		click(CORNER)
		await get_tree().process_frame
	if main.phase != HotSwapMain.Phase.END or main.end_title() != "JOB COMPLETE" or not tower.won or tower.rooms_cleared != RunState.ROOM_COUNT:
		fail("run did not reach JOB COMPLETE: phase %d, title '%s', cleared %d" % [main.phase, main.end_title(), tower.rooms_cleared])
		return false
	var distinct: Dictionary = {}
	for id: String in played_ids:
		distinct[id] = true
	if distinct.size() != RunState.ROOM_COUNT + 2:
		fail("played rooms repeat: %s" % [played_ids])
		return false
	print("RUN OK: 12 rooms and the 3-phase boss cleared by taps, JOB COMPLETE, tips earned %d, hearts %d, boons %s" % [tower.tips, tower.hearts, tower.boons])
	return true


## Skips or plays out the replay after room [param room_number] (0 based) and checks the skip is quick.
func finish_replay(room_number: int) -> bool:
	if room_number == 0:
		var deadline: int = Time.get_ticks_msec() + REPLAY_WAIT_MS
		while main.phase == HotSwapMain.Phase.REPLAY:
			if Time.get_ticks_msec() > deadline:
				fail("replay timed out")
				return false
			await get_tree().process_frame
		if main.replay_outcome != main.live_outcome:
			fail("replay differs from live: %s vs %s" % [main.replay_outcome, main.live_outcome])
			return false
		print("room 1 replay played to the end and reproduced the live outcome")
		return true
	await get_tree().create_timer(0.3, true, false, true).timeout
	var started: int = Time.get_ticks_msec()
	click(CORNER)
	await get_tree().process_frame
	var took: int = Time.get_ticks_msec() - started
	if (main.phase == HotSwapMain.Phase.REPLAY and main.last_reel == HotSwapMain.Reel.CLEAR) or took > SKIP_LIMIT_MS:
		fail("replay skip in room %d: phase %d, %d ms" % [room_number + 1, main.phase, took])
		return false
	return true


func _check_replay_key_and_pick_door(room_index: int) -> bool:
	if main.phase != HotSwapMain.Phase.DOOR:
		fail("no door screen after room %d (phase %d)" % [room_index + 1, main.phase])
		return false
	var offers: Array[int] = main.door_offers().duplicate()
	if room_index == 0:
		key(KEY_R)
		await get_tree().process_frame
		click(CORNER)
		await get_tree().process_frame
		if main.phase != HotSwapMain.Phase.DOOR or main.door_offers() != offers:
			fail("R replay did not return to the door screen")
			return false
		print("R replay and tap skip return to the door screen")
	var pick: int = offers.find(RunState.Door.BOON)
	if pick < 0:
		pick = maxi(offers.find(RunState.Door.TIPS), 0)
	var before: RunState = main.run
	if before.boons.size() == BoonSet.COUNT and RunState.Door.BOON in offers:
		fail("BOON door offered with every boon owned")
		return false
	var hearts: int = before.hearts
	var tips: int = before.tips
	var index: int = before.room_index
	if room_index % 2 == 0:
		click(Hud.DOOR_RECTS[pick].get_center())
	else:
		key(KEY_1 + pick)
	await get_tree().process_frame
	var reward: int = offers[pick]
	if reward == RunState.Door.BOON:
		return await _pick_boon_card(room_index, index)
	var gained_ok: bool = (reward != RunState.Door.HEART or before.hearts == mini(hearts + 1, before.max_hearts)) and (reward != RunState.Door.TIPS or before.tips == tips + RunState.TIPS_DOOR_REWARD)
	if main.phase != _phase_of_room(index + 1) or before.room_index != index + 1 or not gained_ok:
		fail("door pick %d after room %d: phase %d, room %d, reward ok %s" % [pick, room_index + 1, main.phase, before.room_index, gained_ok])
		return false
	return true


## Returns the screen a room opens with: the boss intro for the last room, else planning.
func _phase_of_room(index: int) -> HotSwapMain.Phase:
	return HotSwapMain.Phase.INTRO if index == RunState.ROOM_COUNT - 1 else HotSwapMain.Phase.PLAN


func _pick_boon_card(room_number: int, index: int) -> bool:
	var run: RunState = main.run
	var cards: Array[int] = main.boon_offers().duplicate()
	var owned: int = run.boons.size()
	if main.phase != HotSwapMain.Phase.BOON or cards != run.unowned_boons() or cards.size() != BoonSet.COUNT - owned or run.room_index != index:
		fail("boon screen after room %d: phase %d, cards %s, owned %s" % [room_number + 1, main.phase, cards, run.boons])
		return false
	var card: int = 0 if room_number % 4 < 2 else cards.size() - 1
	if room_number % 2 == 0:
		click(Hud.CARD_RECTS[card].get_center())
	else:
		key(KEY_1 + card)
	await get_tree().process_frame
	if main.phase != _phase_of_room(index + 1) or run.room_index != index + 1 or run.boons.size() != owned + 1 or run.boons[owned] != cards[card]:
		fail("boon card %d: phase %d, room %d, boons %s" % [card, main.phase, run.room_index, run.boons])
		return false
	print("boon screen: took %s with a %s" % [BoonSet.NAMES[cards[card]], "tap" if room_number % 2 == 0 else "key"])
	return true


func _check_persistence() -> bool:
	var earned: int = main.run.tips
	var saved: Dictionary = SaveData.load_save()
	if int(saved["tips"]) != earned or int(saved["best_floor"]) != 4 or earned <= 0:
		fail("save after the run: %s, earned %d" % [saved, earned])
		return false
	main.save = SaveData.fresh()
	main.reload_save()
	if int(main.save["tips"]) != earned:
		fail("tips did not persist across a simulated restart")
		return false
	var file: FileAccess = FileAccess.open(SaveData.path, FileAccess.WRITE)
	file.store_string("{ not json")
	file.close()
	if SaveData.load_save() != SaveData.fresh():
		fail("a corrupt save did not start fresh")
		return false
	DirAccess.remove_absolute(SaveData.path)
	if SaveData.load_save() != SaveData.fresh():
		fail("a missing save did not start fresh")
		return false
	SaveData.record_run(4, earned)
	main.reload_save()
	print("PERSIST OK: tips %d survive a restart, corrupt and missing files start fresh" % earned)
	return true


func _check_fails_and_restart() -> bool:
	main.start_run(777)
	var first_seed: int = main.run.seed
	for attempt: int in 3:
		var room_before: Dictionary = main.run.current_room()
		var plan: Array[int] = failing_taps(attempt != 1)
		if plan.is_empty():
			fail("no failing tap sequence in room %s" % room_before["id"])
			return false
		for tap: int in plan:
			if not await click_gun(tap):
				return false
		var expected_hearts: int = 2 - attempt
		if main.run.hearts != expected_hearts or main.run.room_index != 0:
			fail("fail %d: hearts %d, room %d" % [attempt + 1, main.run.hearts, main.run.room_index])
			return false
		if attempt < 2:
			var started: int = Time.get_ticks_msec()
			click(CORNER)
			await get_tree().process_frame
			var took: int = Time.get_ticks_msec() - started
			var same: bool = main.room_state().guns == RoomState.from_room(room_before).guns
			if main.phase != HotSwapMain.Phase.PLAN or main.swaps != 0 or not same or took > SKIP_LIMIT_MS:
				fail("retry %d: phase %d, same room %s, %d ms" % [attempt + 1, main.phase, same, took])
				return false
			print("fail %d cost a heart, same room retried in %d ms" % [attempt + 1, took])
	if main.phase != HotSwapMain.Phase.REPLAY or main.last_reel != HotSwapMain.Reel.DEATH or main.reel_card_title() != "NIGHT OVER":
		fail("the last heart did not start the death reel: phase %d" % main.phase)
		return false
	click(CORNER)
	await get_tree().process_frame
	if main.phase != HotSwapMain.Phase.END or main.end_title() != "NIGHT OVER" or main.run.hearts != 0:
		fail("three fails did not end the run: phase %d, title '%s'" % [main.phase, main.end_title()])
		return false
	click(CORNER)
	await get_tree().process_frame
	if main.phase != HotSwapMain.Phase.END:
		fail("a stray tap skipped the end screen")
		return false
	await get_tree().create_timer(0.5, true, false, true).timeout
	click(CORNER)
	await get_tree().process_frame
	if main.phase != HotSwapMain.Phase.LOCKER:
		fail("a tap after the end screen did not open the Locker: phase %d" % main.phase)
		return false
	click(LockerView.CLOCK_RECT.get_center())
	await get_tree().process_frame
	if main.phase != HotSwapMain.Phase.PLAN or main.run.seed == first_seed or main.run.hearts != RunState.START_HEARTS or main.run.room_index != 0:
		fail("new tower: phase %d, seed %d (was %d), hearts %d" % [main.phase, main.run.seed, first_seed, main.run.hearts])
		return false
	print("END OK: three fails end the run, a stray tap is ignored, a tap after 400 ms opens the Locker, CLOCK IN starts a new tower with a new seed")
	return true


## Returns taps that fail the current room: one shot, enough safe swaps to empty the budget, or safe swaps then a shot. Plays with [param boons], else the run's.
func failing_taps(prefer_shot: bool, boons: BoonSet = null) -> Array[int]:
	_sim_boons = boons if boons != null else main.run.boon_set()
	var state: RoomState = main.room_state()
	if prefer_shot:
		for tap: int in state.guns.size():
			if HotSwapRules.resolve(state.clone(), tap, _sim_boons).hero_dead:
				return [tap]
	var found: Array[int] = _budget_burn(state, main.budget)
	if found.is_empty() and not prefer_shot:
		return failing_taps(true, boons)
	return found if not found.is_empty() else _fatal_path(state, main.budget)


## Returns safe taps that end with one fatal tap within [param left] swaps, or an empty array.
func _fatal_path(state: RoomState, left: int) -> Array[int]:
	for tap: int in state.guns.size():
		if not state.alive[tap]:
			continue
		var next: RoomState = state.clone()
		if HotSwapRules.resolve(next, tap, _sim_boons).hero_dead:
			return [tap]
		if left > 1 and next.alive_count() > 0:
			var rest: Array[int] = _fatal_path(next, left - 1)
			if not rest.is_empty():
				var out: Array[int] = [tap]
				out.append_array(rest)
				return out
	return []


func _budget_burn(state: RoomState, left: int) -> Array[int]:
	for tap: int in state.guns.size():
		if not state.alive[tap]:
			continue
		var next: RoomState = state.clone()
		if HotSwapRules.resolve(next, tap, _sim_boons).hero_dead or next.alive_count() == 0:
			continue
		if left == 1:
			return [tap]
		var rest: Array[int] = _budget_burn(next, left - 1)
		if not rest.is_empty():
			var out: Array[int] = [tap]
			out.append_array(rest)
			return out
	return []


## Taps gunman [param index] through the real input path and waits for the resolution.
func click_gun(index: int) -> bool:
	if main.phase != HotSwapMain.Phase.PLAN:
		fail("not planning before tap (phase %d)" % main.phase)
		return false
	var pos: Vector2 = main.gun_screen_position(index)
	click(pos)
	await get_tree().process_frame
	if main.phase != HotSwapMain.Phase.RESOLVE:
		fail("tap at %s on gun %d did not start resolution in the next frame: phase %d, alive %s, guns %s" % [pos, index, main.phase, main.room_state().alive, main.room_state().guns])
		return false
	var deadline: int = Time.get_ticks_msec() + WAIT_MS
	while main.phase == HotSwapMain.Phase.RESOLVE:
		if Time.get_ticks_msec() > deadline:
			fail("resolution timed out")
			return false
		await get_tree().process_frame
	return true


## Sends a left click at [param pos], a point in game coordinates.
func click(pos: Vector2) -> void:
	for pressed: bool in [true, false]:
		var ev: InputEventMouseButton = InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		# Headless windows are tiny, so undo the stretch scaling the viewport applies to input.
		var window_pos: Vector2 = get_window().get_final_transform() * pos
		ev.position = window_pos
		ev.global_position = window_pos
		Input.parse_input_event(ev)
	Input.flush_buffered_events()


## Sends a key press at [param keycode].
func key(keycode: Key) -> void:
	for pressed: bool in [true, false]:
		var ev: InputEventKey = InputEventKey.new()
		ev.keycode = keycode
		ev.pressed = pressed
		Input.parse_input_event(ev)
	Input.flush_buffered_events()


## Prints [param reason] as a smoke error and quits with code 1.
func fail(reason: String) -> void:
	printerr("SMOKE FAIL: ", reason)
	get_tree().quit(1)
