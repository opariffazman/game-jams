class_name RuleChecks
extends RefCounted
## Unit-style checks of the shield, knife, event, and boon rules on hand-built rooms. Each check prints one line.

const PISTOL: int = RoomState.Kind.PISTOL
const SHIELD: int = RoomState.Kind.SHIELD
const KNIFE: int = RoomState.Kind.KNIFE
const UP: int = RoomState.Facing.UP
const DOWN: int = RoomState.Facing.DOWN
const LEFT: int = RoomState.Facing.LEFT


## Runs every check. Returns an empty string on success, else the reason of the first error.
static func run() -> String:
	for check: Callable in [_shield_blocks_bullets, _shield_blocks_strike, _knife_steps_and_stabs, _jam, _advance, _reinforce, _boons, _boon_door, _pool_events]:
		var error: String = check.call()
		if error != "":
			return error
	return CoverChecks.run()


## Builds a room dictionary. Each gun is [cell, kind, facing].
static func room(hero: Vector2i, guns: Array, events: Array[Dictionary] = []) -> Dictionary:
	var positions: Array[Vector2] = []
	var kinds: Array[int] = []
	var facings: Array[int] = []
	for gun: Array in guns:
		positions.append(Rooms.cell_center(gun[0]))
		kinds.append(gun[1])
		facings.append(gun[2])
	var covers: Array[Rect2] = []
	return {"hero": Rooms.cell_center(hero), "guns": positions, "covers": covers, "kinds": kinds, "facings": facings, "events": events}


static func _event(turn: int, type: String, params: Dictionary = {}) -> Dictionary:
	return {"turn": turn, "type": type, "params": params}


static func _at(cell: Vector2i) -> Vector2:
	return Rooms.cell_center(cell)


static func _shield_blocks_bullets() -> String:
	var outcomes: Array[bool] = []
	for facing: int in [UP, LEFT, DOWN]:
		var state: RoomState = RoomState.from_room(room(Vector2i(3, 8), [[Vector2i(0, 8), PISTOL, UP], [Vector2i(1, 7), PISTOL, UP], [Vector2i(3, 5), SHIELD, facing], [Vector2i(3, 2), PISTOL, UP]]))
		var res: HotSwapRules.Resolution = HotSwapRules.resolve(state, 0)
		if res.hero_dead or res.target != 1:
			return "shield bullet setup: hero_dead %s, target %d" % [res.hero_dead, res.target]
		outcomes.append(state.alive[2])
	if outcomes != [true, false, false]:
		return "shield survives front/side/back bullet: %s, expected [true, false, false]" % [outcomes]
	print("CHECK shield: a bullet from the front is blocked, the same bullet from the side or back kills it")
	return ""


static func _shield_blocks_strike() -> String:
	var outcomes: Array[bool] = []
	for facing: int in [DOWN, UP]:
		var state: RoomState = RoomState.from_room(room(Vector2i(3, 8), [[Vector2i(6, 8), PISTOL, UP], [Vector2i(3, 5), SHIELD, facing]]))
		var res: HotSwapRules.Resolution = HotSwapRules.resolve(state, 0)
		outcomes.append(state.alive[1])
		if facing == DOWN and (res.blocked_strikes != [1] or not res.struck.is_empty()):
			return "blocked strike not recorded: %s" % [res.blocked_strikes]
	if outcomes != [true, false]:
		return "hero strike on a shield facing / away from him: %s, expected [true, false]" % [outcomes]
	print("CHECK strike: the hero's strike is blocked by a shield that faces him and kills one that does not")
	return ""


static func _knife_steps_and_stabs() -> String:
	var base: Array = [[Vector2i(4, 7), PISTOL, UP], [Vector2i(4, 6), PISTOL, UP]]
	var inside: RoomState = RoomState.from_room(room(Vector2i(3, 8), base + [[Vector2i(5, 6), KNIFE, UP]]))
	var stab: HotSwapRules.Resolution = HotSwapRules.resolve(inside, 0)
	if not stab.stabbed or not stab.hero_dead:
		return "hero landed inside the knife zone and the room did not fail"
	var outside: RoomState = RoomState.from_room(room(Vector2i(3, 8), base + [[Vector2i(1, 5), KNIFE, UP]]))
	var safe: HotSwapRules.Resolution = HotSwapRules.resolve(outside, 0)
	if safe.hero_dead or safe.stabbed or safe.shots.size() != 1 or safe.steps.size() != 1:
		return "knife outside the zone: dead %s, shots %d, steps %d" % [safe.hero_dead, safe.shots.size(), safe.steps.size()]
	if Rooms.cell_of(outside.guns[2]) != Vector2i(1, 6):
		return "knife stepped to %s, not toward the start-of-turn hero cell (1, 6)" % Rooms.cell_of(outside.guns[2])
	var struck: RoomState = RoomState.from_room(room(Vector2i(3, 8), [[Vector2i(4, 7), PISTOL, UP], [Vector2i(5, 6), KNIFE, UP]]))
	if HotSwapRules.resolve(struck, 0).hero_dead:
		return "a knife killed by the strike still failed the room"
	for cell: Vector2i in [Vector2i(5, 6), Vector2i(3, 6), Vector2i(4, 8)]:
		if not TurnSteps.in_knife_zone(_at(Vector2i(4, 6)), _at(cell)):
			return "cell %s is outside the zone of a knife at (4, 6)" % cell
	if TurnSteps.in_knife_zone(_at(Vector2i(4, 6)), _at(Vector2i(1, 6))) or TurnSteps.knife_zone_cells(_at(Vector2i(0, 0))).size() != 6:
		return "knife zone has the wrong size"
	print("CHECK knife: hero inside the zone fails the room, outside does not, a dead knife has no zone, the step follows the start-of-turn hero cell")
	return ""


static func _jam() -> String:
	var jam: Array[Dictionary] = [_event(1, "jam", {"gun": 1})]
	var state: RoomState = RoomState.from_room(room(Vector2i(3, 8), [[Vector2i(0, 8), PISTOL, UP], [Vector2i(6, 0), PISTOL, UP], [Vector2i(0, 5), PISTOL, UP], [Vector2i(5, 3), PISTOL, UP]], jam))
	var first: Array[int] = _shooters(HotSwapRules.resolve(state, 0))
	var second: Array[int] = _shooters(HotSwapRules.resolve(state, 3))
	if first != [2, 3] or 1 not in second:
		return "jam: turn 1 shooters %s (want [2, 3]), turn 2 shooters %s (want gun 1)" % [first, second]
	print("CHECK jam: exactly the marked gunman is silent on the marked turn and fires on the next")
	return ""


static func _shooters(res: HotSwapRules.Resolution) -> Array[int]:
	var out: Array[int] = []
	for shot: HotSwapRules.Shot in res.shots:
		out.append(shot.shooter)
	return out


static func _advance() -> String:
	var guns: Array = [[Vector2i(4, 7), PISTOL, UP], [Vector2i(4, 6), PISTOL, UP], [Vector2i(1, 5), PISTOL, UP]]
	var plain: HotSwapRules.Resolution = HotSwapRules.resolve(RoomState.from_room(room(Vector2i(3, 8), guns)), 0)
	var state: RoomState = RoomState.from_room(room(Vector2i(3, 8), guns, [_event(1, "advance")]))
	var telegraph: Array[Dictionary] = TurnSteps.plan_steps(state)
	var res: HotSwapRules.Resolution = HotSwapRules.resolve(state, 0)
	if not plain.steps.is_empty() or telegraph.size() != 3 or res.steps.size() != 1:
		return "advance: %d telegraphed, %d played, %d without the event" % [telegraph.size(), res.steps.size(), plain.steps.size()]
	var step: Dictionary = res.steps[0]
	if int(step["gun"]) != 2 or Rooms.cell_of(step["to"]) != Vector2i(1, 6):
		return "advance step %s is not one cell toward the start-of-turn hero cell, expected gun 2 at (1, 6)" % [step]
	for line: Dictionary in telegraph:
		if int(line["gun"]) == 2 and line["to"] != step["to"]:
			return "the advance arrow and the played step differ"
	print("CHECK advance: survivors step one cell toward the start-of-turn hero cell, the arrow equals the step, the swapped and dead gunmen stay")
	return ""


static func _cell_gap(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


static func _reinforce() -> String:
	var marked: Array[Dictionary] = [_event(2, "reinforce", {"pos": _at(Vector2i(3, 3))})]
	var guns: Array = [[Vector2i(0, 8), PISTOL, UP], [Vector2i(1, 7), PISTOL, UP], [Vector2i(6, 1), PISTOL, UP], [Vector2i(5, 0), PISTOL, UP], [Vector2i(1, 0), PISTOL, UP]]
	var state: RoomState = RoomState.from_room(room(Vector2i(3, 8), guns, marked))
	var turn_one: HotSwapRules.Resolution = HotSwapRules.resolve(state, 0)
	var size_after_one: int = state.guns.size()
	var turn_two: HotSwapRules.Resolution = HotSwapRules.resolve(state, 2)
	if turn_one.hero_dead or turn_two.hero_dead or size_after_one != 5 or state.guns.size() != 6 or turn_two.spawns != [5]:
		return "reinforcement: sizes %d then %d, spawns %s" % [size_after_one, state.guns.size(), turn_two.spawns]
	if state.guns[5] != _at(Vector2i(3, 3)) or not state.alive[5] or state.kinds[5] != PISTOL:
		return "reinforcement stands at %s, not the marked cell" % state.guns[5]
	var crowded: RoomState = RoomState.from_room(room(Vector2i(3, 8), [[Vector2i(3, 3), PISTOL, UP]]))
	var moved: Vector2i = Rooms.cell_of(TurnSteps.spawn_position(crowded, _at(Vector2i(3, 3))))
	if _cell_gap(moved, Vector2i(3, 3)) != 1:
		return "reinforcement on an occupied cell landed %s" % moved
	var lone: RoomState = RoomState.from_room(room(Vector2i(3, 8), [[Vector2i(0, 8), PISTOL, UP]], [_event(1, "reinforce", {"pos": _at(Vector2i(3, 3))})]))
	HotSwapRules.resolve(lone, 0)
	if lone.alive_count() != 1:
		return "the reinforcement did not keep the room open: %d alive" % lone.alive_count()
	print("CHECK reinforce: it appears at the marked cell after the named turn, shifts when the cell is taken, and keeps the room open")
	return ""


static func _boons() -> String:
	var quick: BoonSet = BoonSet.from_owned([BoonSet.Boon.QUICK_DRAW])
	var coat: BoonSet = BoonSet.from_owned([BoonSet.Boon.COAT])
	var plain_guns: Array = [[Vector2i(0, 8), PISTOL, UP], [Vector2i(1, 7), PISTOL, UP], [Vector2i(2, 6), PISTOL, UP], [Vector2i(6, 0), PISTOL, UP]]
	var base: RoomState = RoomState.from_room(room(Vector2i(3, 8), plain_guns))
	var boosted: RoomState = base.clone()
	HotSwapRules.resolve(base, 0)
	HotSwapRules.resolve(boosted, 0, quick)
	if not base.alive[2] or boosted.alive[2] or boosted.alive[1]:
		return "Quick Draw: second gunman alive %s without, %s with" % [base.alive[2], boosted.alive[2]]
	var walled: RoomState = RoomState.from_room(room(Vector2i(3, 8), [[Vector2i(0, 8), PISTOL, UP], [Vector2i(1, 7), PISTOL, UP], [Vector2i(1, 5), SHIELD, DOWN], [Vector2i(6, 0), PISTOL, UP]]))
	HotSwapRules.resolve(walled, 0, quick)
	if walled.alive[1] or not walled.alive[2]:
		return "Quick Draw against a shield: near %s, shield alive %s" % [walled.alive[1], walled.alive[2]]
	var shot_room: Dictionary = room(Vector2i(3, 8), [[Vector2i(3, 5), PISTOL, UP], [Vector2i(2, 5), PISTOL, UP], [Vector2i(3, 1), PISTOL, UP]])
	if not HotSwapRules.resolve(RoomState.from_room(shot_room), 0).hero_dead:
		return "Coat setup: the bullet misses the hero"
	var covered: RoomState = RoomState.from_room(shot_room)
	var res: HotSwapRules.Resolution = HotSwapRules.resolve(covered, 0, coat)
	if res.hero_dead or not res.coat_used or not covered.coat_spent or RoomState.from_room(shot_room).coat_spent:
		return "Coat: dead %s, used %s, spent %s" % [res.hero_dead, res.coat_used, covered.coat_spent]
	var run: RunState = RunState.new(3)
	var before: int = run.budget()
	run.boons.append(BoonSet.Boon.SPARE_CLIP)
	if run.budget() != before + 1:
		return "Spare Clip budget %d, was %d" % [run.budget(), before]
	if HotSwapRules.solve(RoomState.from_room(Pool.rooms()[0])).size() != int(Pool.rooms()[0]["par"]):
		return "par changed with boons owned"
	print("CHECK boons: Quick Draw kills two (not through a shield), Spare Clip adds a shift, the Coat eats the first hit once per room")
	return ""


static func _boon_door() -> String:
	var with_boon: int = 0
	for seed_value: int in range(1, 41):
		var run: RunState = RunState.new(seed_value)
		for index: int in 11:
			run.room_index = index
			run.boons.clear()
			with_boon += 1 if RunState.Door.BOON in run.door_offers() else 0
			run.boons.assign([0, 1, 2])
			if RunState.Door.BOON in run.door_offers() or not run.unowned_boons().is_empty():
				return "BOON door offered with every boon owned (seed %d, room %d)" % [seed_value, index]
			run.boons.assign([0, 2])
			if run.unowned_boons() != [1]:
				return "unowned boons wrong: %s" % [run.unowned_boons()]
	if with_boon == 0:
		return "the BOON door never appears with no boon owned"
	print("CHECK boon door: appears only while a boon remains (%d offers in 440 doors), never with all three owned" % with_boon)
	return ""


static func _pool_events() -> String:
	var rooms: Array[Dictionary] = Pool.rooms().filter(func(item: Dictionary) -> bool: return not item.get("events", []).is_empty())
	if rooms.size() < 10:
		return "only %d pool rooms carry events" % rooms.size()
	for sample: int in 10:
		var item: Dictionary = rooms[sample * rooms.size() / 10]
		var brute: int = brute_force_par(item)
		var solved: int = HotSwapRules.solve(RoomState.from_room(item)).size()
		if brute != solved or solved != int(item["par"]):
			return "room %s: brute-force par %d, solver %d, stored %s" % [item["id"], brute, solved, item["par"]]
		var taps: Array[int] = HotSwapRules.solve(RoomState.from_room(item))
		var timeline: TurnEvents = TurnEvents.build(item, taps)
		var live: RoomState = RoomState.from_room(item)
		for tap: int in taps:
			HotSwapRules.resolve(live, tap)
		if timeline.final_state.alive != live.alive or timeline.final_state.guns != live.guns:
			return "timeline of %s ends in another state than the live rules" % item["id"]
	print("CHECK par: the solver matches a breadth-first replay on 10 pool rooms with events, and their timelines match the live rules")
	return ""


## Returns the fewest taps that clear [param item] by breadth-first search over every legal tap, or -1 within 7 taps.
static func brute_force_par(item: Dictionary) -> int:
	var layer: Array[RoomState] = [RoomState.from_room(item)]
	for depth: int in range(1, 8):
		var next_layer: Array[RoomState] = []
		for state: RoomState in layer:
			for tap: int in state.guns.size():
				if not state.alive[tap]:
					continue
				var next: RoomState = state.clone()
				if HotSwapRules.resolve(next, tap).hero_dead:
					continue
				if next.alive_count() == 0:
					return depth
				next_layer.append(next)
		layer = next_layer
	return -1
