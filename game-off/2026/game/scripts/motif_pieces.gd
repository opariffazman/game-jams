class_name MotifPieces
extends RefCounted
## Gunman types, facings, and turn events for generated rooms. Pure: the helpers of [Motifs].

## Latest turn a generated event can fire on.
const MAX_EVENT_TURN: int = 3


## Returns the leading gunman cells that give [param motif] its shape, or an empty array for the plain motifs.
static func lead_cells(motif: String, hero: Vector2i, taken: Dictionary) -> Array[Vector2i]:
	var wanted: Array[Vector2i] = []
	var side: int = 1 if hero.x < Motifs.COLS / 2 else -1
	match motif:
		"shield_wall":
			var row: int = clampi(hero.y - 3, 2, 5)
			wanted = [Vector2i(hero.x - 1, row), Vector2i(hero.x + 1, row), Vector2i(hero.x, row - 2)]
		"knife_charge":
			wanted = [Vector2i(hero.x - 2, 0), Vector2i(hero.x + 2, 1)]
		"flank":
			wanted = [Vector2i(hero.x, hero.y - 3), Vector2i(hero.x, hero.y - 5), Vector2i(hero.x + 3 * side, hero.y - 2)]
	var out: Array[Vector2i] = []
	for cell: Vector2i in wanted:
		if cell.x >= 0 and cell.x < Motifs.COLS and cell.y >= 0 and cell.y <= Motifs.HERO_ROW_MIN and not taken.has(cell):
			taken[cell] = true
			out.append(cell)
	return out


## Returns a [enum RoomState.Kind] per gunman. The first [param lead] gunmen follow the motif, the rest are drawn at random.
static func kinds_for(rng: RandomNumberGenerator, motif: String, count: int, lead: int, allowed: Array) -> Array[int]:
	var kinds: Array[int] = []
	for i: int in count:
		kinds.append(RoomState.Kind.PISTOL)
	var shield_ok: bool = RoomState.Kind.SHIELD in allowed
	var knife_ok: bool = RoomState.Kind.KNIFE in allowed
	match motif:
		"shield_wall":
			for i: int in mini(2, lead):
				kinds[i] = RoomState.Kind.SHIELD
		"knife_charge":
			for i: int in mini(2, lead):
				kinds[i] = RoomState.Kind.KNIFE
		"flank":
			if lead > 0:
				kinds[0] = RoomState.Kind.SHIELD
		_:
			if shield_ok and rng.randf() < 0.65:
				kinds[rng.randi_range(0, count - 1)] = RoomState.Kind.SHIELD
			if shield_ok and rng.randf() < 0.25:
				kinds[rng.randi_range(0, count - 1)] = RoomState.Kind.SHIELD
			if knife_ok and rng.randf() < 0.5:
				kinds[rng.randi_range(0, count - 1)] = RoomState.Kind.KNIFE
	return kinds


## Returns a [enum RoomState.Facing] per gunman. Shields mostly face the hero, flank shields always do.
static func facings_for(rng: RandomNumberGenerator, motif: String, kinds: Array[int], guns: Array[Vector2], hero: Vector2) -> Array[int]:
	var facings: Array[int] = []
	for i: int in kinds.size():
		var facing: int = RoomState.Facing.UP
		if kinds[i] == RoomState.Kind.SHIELD:
			facing = toward(guns[i], hero) if motif == "flank" or rng.randf() < 0.75 else rng.randi_range(0, 3)
		facings.append(facing)
	return facings


## Returns the [enum RoomState.Facing] that points from [param from] toward [param target] along the larger axis.
static func toward(from: Vector2, target: Vector2) -> int:
	var gap: Vector2 = target - from
	if absf(gap.y) >= absf(gap.x) * 0.9:
		return RoomState.Facing.DOWN if gap.y > 0.0 else RoomState.Facing.UP
	return RoomState.Facing.RIGHT if gap.x > 0.0 else RoomState.Facing.LEFT


## Returns the event plan for a room: 0 to 2 events of the types in [code]gate["events"][/code], params still empty.
## A gate with a [code]force[/code] list gets exactly those event types instead, so the boss phases always have rooms.
static func plan_events(rng: RandomNumberGenerator, motif: String, gate: Dictionary) -> Array[Dictionary]:
	var allowed: Array = gate["events"]
	var plan: Array[Dictionary] = []
	if gate.has("force"):
		var forced: Array = gate["force"]
		for type: String in forced:
			plan.append({"turn": 1 if type == "reinforce" else rng.randi_range(1, 2), "type": type, "params": {}})
		return plan
	if allowed.is_empty():
		return plan
	var roll: float = rng.randf()
	var count: int = 0 if roll < 0.2 else (1 if roll < 0.6 else 2)
	if motif == "reinforced_crossfire":
		plan.append({"turn": rng.randi_range(1, 2), "type": "reinforce", "params": {}})
	for i: int in count:
		var type: String = allowed[rng.randi_range(0, allowed.size() - 1)]
		var turn: int = rng.randi_range(1, 2 if type == "reinforce" else MAX_EVENT_TURN)
		var duplicate: bool = false
		for event: Dictionary in plan:
			duplicate = duplicate or event["type"] == type and (type == "reinforce" or event["turn"] == turn)
		if not duplicate and plan.size() < 2:
			plan.append({"turn": turn, "type": type, "params": {}})
	return plan


## Fills the params of [param plan]: a jam picks a gunman who fires, a reinforcement picks a free cell.
static func fill_events(rng: RandomNumberGenerator, plan: Array[Dictionary], kinds: Array[int], taken: Dictionary) -> void:
	for event: Dictionary in plan:
		var params: Dictionary = event["params"]
		if event["type"] == "jam":
			params["gun"] = _firing_gun(rng, kinds)
		elif event["type"] == "reinforce":
			var cell: Vector2i = Motifs.free_cell(rng, taken)
			params["pos"] = Rooms.cell_center(cell)


## Returns a copy of [param room] with one shield turned or one event changed. The copy can be unplayable.
static func mutate(rng: RandomNumberGenerator, room: Dictionary) -> Dictionary:
	var out: Dictionary = room.duplicate()
	var kinds: Array = room["kinds"]
	var shields: Array[int] = []
	for i: int in kinds.size():
		if kinds[i] == RoomState.Kind.SHIELD:
			shields.append(i)
	var events: Array[Dictionary] = []
	for event: Dictionary in room["events"]:
		events.append({"turn": event["turn"], "type": event["type"], "params": event["params"].duplicate()})
	if not shields.is_empty() and (events.is_empty() or rng.randf() < 0.5):
		var facings: Array[int] = []
		facings.assign(room["facings"])
		facings[shields[rng.randi_range(0, shields.size() - 1)]] = rng.randi_range(0, 3)
		out["facings"] = facings
	elif not events.is_empty():
		var event: Dictionary = events[rng.randi_range(0, events.size() - 1)]
		var params: Dictionary = event["params"]
		var roll: float = rng.randf()
		if roll < 0.5:
			event["turn"] = clampi(int(event["turn"]) + (1 if rng.randf() < 0.5 else -1), 1, MAX_EVENT_TURN)
		elif event["type"] == "jam":
			var typed: Array[int] = []
			typed.assign(kinds)
			params["gun"] = _firing_gun(rng, typed)
		elif event["type"] == "reinforce":
			var pos: Vector2 = params["pos"]
			var step: Vector2 = Rooms.cell_size()
			params["pos"] = Rooms.cell_center(Rooms.cell_of(Vector2(pos.x + rng.randi_range(-2, 2) * step.x, pos.y + rng.randi_range(-2, 2) * step.y)))
	out["events"] = events
	return out


static func _firing_gun(rng: RandomNumberGenerator, kinds: Array[int]) -> int:
	var firing: Array[int] = []
	for i: int in kinds.size():
		if kinds[i] != RoomState.Kind.KNIFE:
			firing.append(i)
	return firing[rng.randi_range(0, firing.size() - 1)] if not firing.is_empty() else 0
