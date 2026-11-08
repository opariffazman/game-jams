class_name Motifs
extends RefCounted
## Parameterized room layouts on the 7 x 9 grid. Each build is mirrored at random, jittered by whole cells,
## and given cover blocks. Pure: no scene access.

## Motif names, also used as tags.
const NAMES: Array[String] = ["crossfire", "bodyguard", "pincer", "scatter", "shield_wall", "knife_charge", "flank", "reinforced_crossfire"]
## First floor on which each motif can appear, parallel to [constant NAMES].
const MIN_FLOOR: Array[int] = [1, 1, 1, 1, 2, 3, 2, 4]
## Grid columns.
const COLS: int = Rooms.COLS
## Grid rows.
const ROWS: int = Rooms.ROWS
## First grid row of the hero zone. Gunmen use the rows above it plus this one.
const HERO_ROW_MIN: int = 6
## Chance that one gunman moves a whole cell off its motif cell.
const JITTER_CHANCE: float = 0.25
## Cover thickness in pixels.
const COVER_THICKNESS: float = 28.0


## Returns the motifs that can appear on gate set [param level].
static func names_for(level: int) -> Array[String]:
	var out: Array[String] = []
	for i: int in NAMES.size():
		if MIN_FLOOR[i] <= level:
			out.append(NAMES[i])
	return out


## Builds a room of [param motif] with [param gun_count] gunmen and [param cover_count] cover blocks.
## [param gate] gives the allowed gunman kinds and event types.
static func build(rng: RandomNumberGenerator, motif: String, gun_count: int, cover_count: int, gate: Dictionary) -> Dictionary:
	var plan: Array[Dictionary] = MotifPieces.plan_events(rng, motif, gate)
	for event: Dictionary in plan:
		if event["type"] == "reinforce" and gun_count > 3:
			gun_count -= 1
	var hero_cell: Vector2i = Vector2i(rng.randi_range(2, 4), rng.randi_range(HERO_ROW_MIN + 1, ROWS - 1))
	if motif == "scatter":
		hero_cell.x = rng.randi_range(0, COLS - 1)
	var taken: Dictionary = {hero_cell: true}
	var lead: Array[Vector2i] = MotifPieces.lead_cells(motif, hero_cell, taken)
	var cells: Array[Vector2i] = _layout(rng, motif, gun_count, hero_cell, taken, lead)
	var mirrored: bool = rng.randf() < 0.5
	if mirrored:
		hero_cell.x = COLS - 1 - hero_cell.x
	taken = {hero_cell: true}
	var guns: Array[Vector2] = []
	for cell: Vector2i in cells:
		var placed: Vector2i = Vector2i(COLS - 1 - cell.x if mirrored else cell.x, cell.y)
		if rng.randf() < JITTER_CHANCE:
			placed = _jitter(rng, placed, taken)
		taken[placed] = true
		guns.append(cell_center(placed.x, placed.y))
	var covers: Array[Rect2] = _covers(rng, cover_count, taken)
	var hero: Vector2 = cell_center(hero_cell.x, hero_cell.y)
	var kinds: Array[int] = MotifPieces.kinds_for(rng, motif, guns.size(), lead.size(), gate["kinds"])
	MotifPieces.fill_events(rng, plan, kinds, taken)
	return {"hero": hero, "guns": guns, "covers": covers, "motif": motif, "kinds": kinds,
		"facings": MotifPieces.facings_for(rng, motif, kinds, guns, hero), "events": plan}


## Returns the world position of grid cell ([param col], [param row]).
static func cell_center(col: int, row: int) -> Vector2:
	return Rooms.cell_center(Vector2i(col, row))


## Returns gunman cells. Most motifs place chains of two or three gunmen on one ray from the hero. A tap on a
## gunman with another gunman behind him on the ray leaves the hero in that gunman's line of fire.
static func _layout(rng: RandomNumberGenerator, motif: String, count: int, hero: Vector2i, taken: Dictionary, lead: Array[Vector2i]) -> Array[Vector2i]:
	var out: Array[Vector2i] = lead.duplicate()
	var rays: Array[Vector2i] = _rays(motif)
	var tries: int = 0
	while out.size() + 1 < count and tries < 60 and motif != "scatter" and lead.is_empty():
		tries += 1
		var ray: Vector2i = rays[rng.randi_range(0, rays.size() - 1)]
		var length: int = mini(rng.randi_range(2, 3), count - out.size())
		var chain: Array[Vector2i] = []
		for step: int in range(1, length + 1):
			var cell: Vector2i = hero + ray * step
			if _in_zone(cell) and not taken.has(cell):
				chain.append(cell)
		if chain.size() < 2:
			continue
		for cell: Vector2i in chain:
			taken[cell] = true
			out.append(cell)
	while out.size() < count:
		var cell: Vector2i = free_cell(rng, taken)
		taken[cell] = true
		out.append(cell)
	return out


static func _rays(motif: String) -> Array[Vector2i]:
	match motif:
		"bodyguard":
			return [Vector2i(0, -2), Vector2i(0, -3), Vector2i(1, -2), Vector2i(-1, -2), Vector2i(1, -3), Vector2i(-1, -3)]
		"crossfire", "reinforced_crossfire":
			return [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, -2), Vector2i(1, -2), Vector2i(-1, -3), Vector2i(1, -3)]
		_:
			return [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-2, 0), Vector2i(2, 0)]


static func _in_zone(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < COLS and cell.y >= 0 and cell.y <= HERO_ROW_MIN


static func _jitter(rng: RandomNumberGenerator, cell: Vector2i, taken: Dictionary) -> Vector2i:
	for attempt: int in 20:
		var next: Vector2i = Vector2i(
			clampi(cell.x + rng.randi_range(-1, 1), 0, COLS - 1),
			clampi(cell.y + rng.randi_range(-1, 1), 0, HERO_ROW_MIN))
		if not taken.has(next):
			return next
	return free_cell(rng, taken)


## Returns a random free cell of the gunman zone. Marks nothing.
static func free_cell(rng: RandomNumberGenerator, taken: Dictionary) -> Vector2i:
	while true:
		var cell: Vector2i = Vector2i(rng.randi_range(0, COLS - 1), rng.randi_range(0, HERO_ROW_MIN))
		if not taken.has(cell):
			return cell
	return Vector2i.ZERO


static func _covers(rng: RandomNumberGenerator, count: int, taken: Dictionary) -> Array[Rect2]:
	var covers: Array[Rect2] = []
	var cell_w: float = Rooms.FLOOR.size.x / COLS
	for i: int in count:
		var span: int = rng.randi_range(1, 2)
		var col: int = rng.randi_range(0, COLS - span)
		var row: int = rng.randi_range(2, ROWS - 3)
		var free: bool = true
		for c: int in span:
			free = free and not taken.has(Vector2i(col + c, row))
		if not free:
			continue
		for c: int in span:
			taken[Vector2i(col + c, row)] = true
		var left: Vector2 = cell_center(col, row)
		covers.append(Rect2(left.x - cell_w * 0.5, left.y - COVER_THICKNESS * 0.5, cell_w * span, COVER_THICKNESS))
	return covers


## Returns a copy of [param room] with one gunman, the hero, or one cover block moved by whole cells. The copy can be unplayable, so analyse it before use.
static func mutate(rng: RandomNumberGenerator, room: Dictionary) -> Dictionary:
	var out: Dictionary = room.duplicate()
	var guns: Array[Vector2] = []
	guns.assign(room["guns"])
	var covers: Array[Rect2] = []
	covers.assign(room["covers"])
	var hero: Vector2 = room["hero"]
	var step: Vector2 = Vector2(Rooms.FLOOR.size.x / COLS, Rooms.FLOOR.size.y / ROWS)
	var roll: float = rng.randf()
	if roll < 0.12 and (room.get("kinds", []).has(RoomState.Kind.SHIELD) or not room.get("events", []).is_empty()):
		return MotifPieces.mutate(rng, room)
	if roll < 0.7:
		var which: int = rng.randi_range(0, guns.size() - 1)
		guns[which] = _clamped(guns[which] + _cell_offset(rng, step), 0, HERO_ROW_MIN)
	elif roll < 0.8:
		hero = _clamped(hero + _cell_offset(rng, step), HERO_ROW_MIN + 1, ROWS - 1)
	elif Rooms.COVER_ENABLED and covers.size() < 3 and (covers.is_empty() or rng.randf() < 0.5):
		covers.append(_cover_at(rng.randi_range(0, COLS - 2), rng.randi_range(2, ROWS - 3), rng.randi_range(1, 2)))
	elif not covers.is_empty():
		var which: int = rng.randi_range(0, covers.size() - 1)
		if rng.randf() < 0.3:
			covers.remove_at(which)
		else:
			covers[which].position += _cell_offset(rng, step)
	out["guns"] = guns
	out["covers"] = covers
	out["hero"] = hero
	return out


## Returns true when no gunman or hero shares a cover block and no two figures share a cell.
static func is_layout_valid(room: Dictionary) -> bool:
	var points: Array[Vector2] = []
	points.assign(room["guns"])
	points.append(room["hero"])
	for i: int in points.size():
		for j: int in range(i + 1, points.size()):
			if points[i].distance_to(points[j]) < 40.0:
				return false
	for cover: Rect2 in room["covers"]:
		if not Rooms.FLOOR.encloses(cover):
			return false
		for point: Vector2 in points:
			if cover.grow(14.0).has_point(point):
				return false
	return true


static func _cell_offset(rng: RandomNumberGenerator, step: Vector2) -> Vector2:
	var cell: Vector2i = Vector2i.ZERO
	while cell == Vector2i.ZERO:
		cell = Vector2i(rng.randi_range(-2, 2), rng.randi_range(-2, 2))
	return Vector2(cell.x * step.x, cell.y * step.y)


static func _clamped(pos: Vector2, row_min: int, row_max: int) -> Vector2:
	var size: Vector2 = Rooms.cell_size()
	var col: int = clampi(roundi((pos.x - Rooms.FLOOR.position.x) / size.x - 0.5), 0, COLS - 1)
	var row: int = clampi(roundi((pos.y - Rooms.FLOOR.position.y) / size.y - 0.5), row_min, row_max)
	return cell_center(col, row)


static func _cover_at(col: int, row: int, span: int) -> Rect2:
	var cell_w: float = Rooms.FLOOR.size.x / COLS
	var left: Vector2 = cell_center(col, row)
	return Rect2(left.x - cell_w * 0.5, left.y - COVER_THICKNESS * 0.5, cell_w * span, COVER_THICKNESS)
