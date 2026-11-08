class_name Demo
extends Node
## Scripted tour for screen recordings (--run-demo): a floor 2 shield room, the door screen, boss intro, boss bar mid-fight, a knife danger zone, the Locker.

## Seconds each stop of the tour stays up.
const STOP_S: float = 1.5
## Seconds to wait for the boss intro card to end by itself.
const INTRO_WAIT: float = HotSwapMain.INTRO_S + 0.2


## Walks [param main] through the tour. Awaitable.
func run(main: HotSwapMain) -> void:
	main.run.hearts = 2
	await _shield_room_and_doors(main)
	main.run.tips = 20
	main.save = {"tips": 70, "best_floor": 4, "owned": [Upgrades.Id.HEARTS_1, Upgrades.Id.CYAN_COAT], "coat": Upgrades.Id.CYAN_COAT}
	main.run.room_index = RunState.ROOM_COUNT - 1
	main.enter_room()
	await _wait(INTRO_WAIT)
	main.run.boss_phase = 2
	main.enter_room()
	await _wait(STOP_S)
	main.run.room_index = 7
	main.play_room(_room_with(RoomState.Kind.KNIFE))
	await _wait(STOP_S)
	main.open_locker()


## Plays a floor 3 room into a dead end for the NO WAY OUT banner (--deadend-demo): the banner with UNDO lit, the undo, then the same shift again with RETRY showing.
func deadend_demo(main: HotSwapMain) -> void:
	var shown: Dictionary = _find_dead_end(3)
	main.play_room(shown["room"])
	await _wait(0.3)
	main._on_tap(main.gun_screen_position(int(shown["tap"])))
	while main.controls.dead_end_reason() == "":
		await _wait(0.05)
	await _wait(1.0)
	main.undo_shift()
	await _wait(0.4)
	main._on_tap(main.gun_screen_position(int(shown["tap"])))


## Returns the first pool room of gate set [param level] with a safe first tap that leaves a room the detector proves lost, and that tap.
func _find_dead_end(level: int) -> Dictionary:
	for room: Dictionary in Pool.of_floor(level):
		var base: RoomState = RoomState.from_room(room)
		var budget: int = int(room["par"]) + RoomGen.slack_for(level)
		for tap: int in base.guns.size():
			var next: RoomState = base.clone()
			if not HotSwapRules.resolve(next, tap).hero_dead and next.alive_count() > 0 and DeadEnd.verdict(next, budget - 1, null, DeadEnd.OFFLINE_CAP) == DeadEnd.Verdict.DEAD:
				return {"room": room, "tap": tap}
	return {}


## Plays a floor 2 shield room and one safe swap, then shows the door screen with its MONEY door.
func _shield_room_and_doors(main: HotSwapMain) -> void:
	var shown: Dictionary = _find_shield_swap()
	if not shown.is_empty():
		main.play_room(shown["room"])
		await _wait(0.5)
		main._on_tap(main.gun_screen_position(int(shown["tap"])))
		await _wait(STOP_S)
	main.play.visible = false
	main.hud.show_doors([RunState.Door.HEART, RunState.Door.TIPS] as Array[int])
	await _wait(STOP_S)


## Returns the first floor 2 pool room with a shield and a swap that does not kill the hero, or an empty dictionary.
func _find_shield_swap() -> Dictionary:
	for room: Dictionary in Pool.of_floor(2):
		if RoomState.Kind.SHIELD not in room["kinds"]:
			continue
		var base: RoomState = RoomState.from_room(room)
		for tap: int in base.guns.size():
			if not HotSwapRules.resolve(base.clone(), tap).hero_dead:
				return {"room": room, "tap": tap}
	return {}


## Plays a cleared-room replay with a shield block, then a death reel that ends on a hero hit. Awaitable.
func reels(main: HotSwapMain) -> void:
	var shown: Dictionary = _find_jam_clear() if "--jam" in OS.get_cmdline_user_args() else _find_block()
	main.demo_reel(HotSwapMain.Reel.REVIEW, shown["room"], shown["taps"])
	await _until_done(main, 9.0)
	var death: Dictionary = _find_death()
	main.demo_reel(HotSwapMain.Reel.DEATH, death["room"], death["taps"])
	await _until_done(main, 9.0)


## Returns the pool room and swap with the fewest cover blocks whose resolution shows a shield stopping the hero's strike, else a bullet.
func _find_block() -> Dictionary:
	var best: Dictionary = {}
	var best_score: int = -1
	for room: Dictionary in Pool.rooms():
		if RoomState.Kind.SHIELD not in room["kinds"]:
			continue
		var base: RoomState = RoomState.from_room(room)
		for tap: int in base.guns.size():
			var res: HotSwapRules.Resolution = HotSwapRules.resolve(base.clone(), tap)
			var stopped: int = 2 if not res.blocked_strikes.is_empty() else 0
			for shot: HotSwapRules.Shot in res.shots:
				stopped = maxi(stopped, 1 if shot.blocked_by >= 0 else 0)
			var score: int = stopped * 10 - base.covers.size()
			if stopped > 0 and not res.hero_dead and score > best_score:
				best_score = score
				best = {"room": room, "taps": [tap] as Array[int]}
	if best.is_empty():
		return {"room": Pool.rooms()[0], "taps": HotSwapRules.solve(RoomState.from_room(Pool.rooms()[0]))}
	return best


## Returns the pool room with a jam and the fewest swaps that clears it, to show the jam cue and the falling bodies.
func _find_jam_clear() -> Dictionary:
	var best: Dictionary = {}
	for room: Dictionary in Pool.rooms():
		var types: Array = room["events"].map(func(event: Dictionary) -> String: return event["type"])
		if "jam" not in types or int(room["par"]) > 2:
			continue
		best = {"room": room, "taps": HotSwapRules.solve(RoomState.from_room(room))}
		break
	return best if not best.is_empty() else _find_block()


## Returns a pool room and a short attempt that ends with a bullet in the hero.
func _find_death() -> Dictionary:
	for room: Dictionary in Pool.rooms():
		var base: RoomState = RoomState.from_room(room)
		for tap: int in base.guns.size():
			var next: RoomState = base.clone()
			var res: HotSwapRules.Resolution = HotSwapRules.resolve(next, tap)
			if res.hero_dead and not res.stabbed and base.guns.size() >= 3:
				return {"room": room, "taps": [tap] as Array[int]}
	return {"room": Pool.rooms()[0], "taps": [0] as Array[int]}


func _until_done(main: HotSwapMain, limit_s: float) -> void:
	var waited: float = 0.0
	while main.phase == HotSwapMain.Phase.REPLAY and waited < limit_s:
		await get_tree().process_frame
		waited += get_process_delta_time()


## Returns the first pool room of gate set 3 or more with a gunman of [param kind].
func _room_with(kind: int) -> Dictionary:
	for room: Dictionary in Pool.rooms():
		var kinds: Array = room["kinds"]
		if int(room["floor"]) >= 3 and kind in kinds:
			return room
	return Pool.rooms()[0]


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout
