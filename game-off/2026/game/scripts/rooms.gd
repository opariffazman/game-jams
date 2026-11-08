class_name Rooms
extends RefCounted
## Room geometry and JSON helpers shared by the generator, the pool, and the run.
## Coordinates are world pixels inside the lower room area.

## Room bounds drawn as the floor.
const FLOOR: Rect2 = Rect2(30, 330, 480, 580)
## Switch for cover blocks. Cover is off until it gets one consistent rule.
## While off, generators build none, and [method RoomState.from_room] and the pool loader strip any cover from data.
## The cover rules in [HotSwapRules] stay and work on any state that holds cover.
const COVER_ENABLED: bool = false
## Grid columns.
const COLS: int = 7
## Grid rows.
const ROWS: int = 9


## Returns the size of one grid cell in pixels.
static func cell_size() -> Vector2:
	return Vector2(FLOOR.size.x / COLS, FLOOR.size.y / ROWS)


## Returns the world position of the center of [param cell].
static func cell_center(cell: Vector2i) -> Vector2:
	var size: Vector2 = cell_size()
	return FLOOR.position + Vector2((cell.x + 0.5) * size.x, (cell.y + 0.5) * size.y)


## Returns the grid cell that holds [param pos], clamped to the grid.
static func cell_of(pos: Vector2) -> Vector2i:
	var size: Vector2 = cell_size()
	return Vector2i(clampi(floori((pos.x - FLOOR.position.x) / size.x), 0, COLS - 1), clampi(floori((pos.y - FLOOR.position.y) / size.y), 0, ROWS - 1))


## Converts a room to a JSON-safe dictionary.
static func to_json(room: Dictionary) -> Dictionary:
	var guns: Array = []
	for gun_pos: Vector2 in room["guns"]:
		guns.append([gun_pos.x, gun_pos.y])
	var covers: Array = []
	for cover: Rect2 in room["covers"]:
		covers.append([cover.position.x, cover.position.y, cover.size.x, cover.size.y])
	var hero: Vector2 = room["hero"]
	var out: Dictionary = room.duplicate()
	out["hero"] = [hero.x, hero.y]
	out["guns"] = guns
	out["covers"] = covers
	var events: Array = []
	for event: Dictionary in room.get("events", []):
		var params: Dictionary = event["params"].duplicate()
		if params.has("pos"):
			var pos: Vector2 = params["pos"]
			params["pos"] = [pos.x, pos.y]
		events.append({"turn": event["turn"], "type": event["type"], "params": params})
	out["events"] = events
	return out


## Converts a JSON dictionary back to a room with Vector2 and Rect2 values.
static func from_json(data: Dictionary) -> Dictionary:
	var room: Dictionary = data.duplicate()
	var hero: Array = data["hero"]
	room["hero"] = Vector2(hero[0], hero[1])
	var guns: Array[Vector2] = []
	for item: Array in data["guns"]:
		guns.append(Vector2(item[0], item[1]))
	room["guns"] = guns
	var covers: Array[Rect2] = []
	for item: Array in data["covers"]:
		covers.append(Rect2(item[0], item[1], item[2], item[3]))
	room["covers"] = covers if COVER_ENABLED else ([] as Array[Rect2])
	room["kinds"] = _ints(data.get("kinds", []))
	room["facings"] = _ints(data.get("facings", []))
	var events: Array[Dictionary] = []
	var raw_events: Array = data.get("events", [])
	for item: Dictionary in raw_events:
		var params: Dictionary = item["params"].duplicate()
		if params.has("pos"):
			var pos: Array = params["pos"]
			params["pos"] = Vector2(pos[0], pos[1])
		if params.has("gun"):
			params["gun"] = int(params["gun"])
		events.append({"turn": int(item["turn"]), "type": str(item["type"]), "params": params})
	room["events"] = events
	return room


## Returns a horizontally mirrored copy of [param room]. The copy keeps the same id, so it counts as the same room.
static func mirror(room: Dictionary) -> Dictionary:
	var axis: float = FLOOR.position.x * 2.0 + FLOOR.size.x
	var copy: Dictionary = room.duplicate()
	var hero: Vector2 = room["hero"]
	copy["hero"] = Vector2(axis - hero.x, hero.y)
	var guns: Array[Vector2] = []
	for gun_pos: Vector2 in room["guns"]:
		guns.append(Vector2(axis - gun_pos.x, gun_pos.y))
	copy["guns"] = guns
	var covers: Array[Rect2] = []
	for cover: Rect2 in room["covers"]:
		covers.append(Rect2(axis - cover.end.x, cover.position.y, cover.size.x, cover.size.y))
	copy["covers"] = covers
	var facings: Array[int] = []
	for facing: int in room.get("facings", []):
		var flipped: int = facing
		if facing == RoomState.Facing.LEFT:
			flipped = RoomState.Facing.RIGHT
		elif facing == RoomState.Facing.RIGHT:
			flipped = RoomState.Facing.LEFT
		facings.append(flipped)
	copy["facings"] = facings
	var events: Array[Dictionary] = []
	for event: Dictionary in room.get("events", []):
		var params: Dictionary = event["params"].duplicate()
		if params.has("pos"):
			var pos: Vector2 = params["pos"]
			params["pos"] = Vector2(axis - pos.x, pos.y)
		events.append({"turn": event["turn"], "type": event["type"], "params": params})
	copy["events"] = events
	copy["mirrored"] = not bool(room.get("mirrored", false))
	return copy


static func _ints(items: Array) -> Array[int]:
	var out: Array[int] = []
	for item: Variant in items:
		out.append(int(item))
	return out
