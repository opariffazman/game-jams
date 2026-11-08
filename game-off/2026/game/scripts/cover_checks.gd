class_name CoverChecks
extends RefCounted
## Checks that cover rules still work on states built with cover, plus a scan that no pool room, mirrored room, or boss phase holds cover while [constant Rooms.COVER_ENABLED] is off.

const PISTOL: int = RoomState.Kind.PISTOL
const UP: int = RoomState.Facing.UP
## Half the side of the test cover blocks, in pixels.
const TEST_COVER_HALF: float = 20.0


## Runs every check. Returns an empty string on success, else the reason of the first error.
static func run() -> String:
	for check: Callable in [_wasted_strike, _nearest_visible, _quick_draw_one_visible, _grazing_strike_blocked, _adjacent_body_hit, _pool_scan]:
		var error: String = check.call()
		if error != "":
			return error
	return ""


static func _cover_at(cell: Vector2i) -> Rect2:
	var half: Vector2 = Vector2.ONE * TEST_COVER_HALF
	return Rect2(Rooms.cell_center(cell) - half, half * 2.0)


static func _state(guns: Array, cover_cells: Array[Vector2i]) -> RoomState:
	var state: RoomState = RoomState.from_room(RuleChecks.room(Vector2i(3, 8), guns))
	for cell: Vector2i in cover_cells:
		state.covers.append(_cover_at(cell))
	return state


static func _wasted_strike() -> String:
	var state: RoomState = _state([[Vector2i(6, 8), PISTOL, UP], [Vector2i(6, 4), PISTOL, UP]], [Vector2i(6, 6)])
	var res: HotSwapRules.Resolution = HotSwapRules.resolve(state, 0)
	var face: float = _cover_at(Vector2i(6, 6)).end.y + HotSwapRules.COVER_MARGIN
	if not res.wasted or res.target != -1 or not res.targets.is_empty() or not res.struck.is_empty():
		return "strike behind cover: wasted %s, target %d, struck %s" % [res.wasted, res.target, res.struck]
	if not state.alive[1] or absf(res.impact.y - face) > 0.5 or absf(res.impact.x - _cover_at(Vector2i(6, 6)).get_center().x) > 0.5:
		return "wasted strike did not stop on the cover face plus margin: impact %s, face y %.1f, gunman alive %s" % [res.impact, face, state.alive[1]]
	print("CHECK cover: a strike with no clear line is wasted, kills nothing, and stops on the first cover block")
	return ""


static func _nearest_visible() -> String:
	var state: RoomState = _state([[Vector2i(5, 8), PISTOL, UP], [Vector2i(5, 6), PISTOL, UP], [Vector2i(1, 8), PISTOL, UP]], [Vector2i(5, 7)])
	var res: HotSwapRules.Resolution = HotSwapRules.resolve(state, 0)
	if res.wasted or res.targets != [2] or res.struck != [2]:
		return "strike picked %s, struck %s, expected only the visible gunman 2 and not the nearer hidden gunman 1" % [res.targets, res.struck]
	print("CHECK cover: the strike picks the nearest visible gunman, not the nearest one")
	return ""


static func _quick_draw_one_visible() -> String:
	var boons: BoonSet = BoonSet.new()
	boons.quick_draw = true
	var state: RoomState = _state([[Vector2i(5, 8), PISTOL, UP], [Vector2i(5, 5), PISTOL, UP], [Vector2i(1, 8), PISTOL, UP], [Vector2i(5, 3), PISTOL, UP]], [Vector2i(5, 6)])
	var res: HotSwapRules.Resolution = HotSwapRules.resolve(state, 0, boons)
	if res.targets != [2] or res.struck != [2] or res.wasted:
		return "Quick Draw with one visible gunman: targets %s, struck %s" % [res.targets, res.struck]
	print("CHECK cover: Quick Draw with one visible gunman kills only that one")
	return ""


## A strike line that passes 4 px under a wall, inside the margin but outside the real rect, must be blocked.
static func _grazing_strike_blocked() -> String:
	var state: RoomState = _state([[Vector2i(1, 6), PISTOL, UP], [Vector2i(5, 6), PISTOL, UP]], [])
	var line_y: float = Rooms.cell_center(Vector2i(3, 6)).y
	state.covers.append(Rect2(Rooms.cell_center(Vector2i(3, 6)).x - 30.0, line_y - 40.0, 60.0, 36.0))
	var res: HotSwapRules.Resolution = HotSwapRules.resolve(state, 0)
	if not res.wasted or not res.struck.is_empty() or not state.alive[1]:
		return "a strike grazing a wall 4 px away was not blocked: wasted %s, struck %s" % [res.wasted, res.struck]
	if absf(res.impact.y - (line_y)) > 0.5 or res.impact.x > state.covers[0].position.x:
		return "the grazing strike did not stop at the grown wall edge: impact %s" % res.impact
	print("CHECK cover: a strike that grazes a wall within %.0f px is blocked and stops at the wall" % HotSwapRules.COVER_MARGIN)
	return ""


## A gunman standing 5 px from a wall, inside its margin, can still be hit from the open side.
static func _adjacent_body_hit() -> String:
	var state: RoomState = _state([[Vector2i(6, 6), PISTOL, UP], [Vector2i(5, 6), PISTOL, UP]], [])
	var body: Vector2 = Rooms.cell_center(Vector2i(5, 6))
	state.covers.append(Rect2(body.x - 45.0, body.y - 20.0, 40.0, 40.0))
	var res: HotSwapRules.Resolution = HotSwapRules.resolve(state, 0)
	if res.wasted or res.struck != [1]:
		return "a gunman 5 px from a wall was not hit from the open side: wasted %s, struck %s" % [res.wasted, res.struck]
	print("CHECK cover: a gunman next to a wall can still be hit from the side without cover between")
	return ""


## With cover off no pool room, raw pool file entry, mirrored room, or boss phase holds a cover block, and a state built from data with cover still drops it.
static func _pool_scan() -> String:
	if Rooms.COVER_ENABLED:
		return "COVER_ENABLED is true: the no-cover scan does not apply"
	var loaded: int = 0
	for room: Dictionary in Pool.rooms():
		loaded += 1
		var mirrored: Dictionary = Rooms.mirror(room)
		for item: Dictionary in [room, mirrored]:
			if not item["covers"].is_empty() or not RoomState.from_room(item).covers.is_empty():
				return "pool room %s has cover" % room["id"]
	var parser: JSON = JSON.new()
	if parser.parse(FileAccess.get_file_as_string(Pool.PATH)) != OK:
		return "pool.json does not parse"
	var raw_items: Array = parser.data
	for raw: Dictionary in raw_items:
		if not raw["covers"].is_empty():
			return "pool.json room %s stores cover" % raw["id"]
	print("CHECK no cover: %d pool rooms and %d raw entries have 0 cover blocks while COVER_ENABLED is off" % [loaded, raw_items.size()])
	return _strip_and_phases()


static func _strip_and_phases() -> String:
	var data: Dictionary = Rooms.to_json(RuleChecks.room(Vector2i(3, 8), [[Vector2i(6, 8), PISTOL, UP]]))
	data["covers"] = [[100.0, 500.0, 60.0, 28.0]]
	if not Rooms.from_json(data)["covers"].is_empty() or not RoomState.from_room(Rooms.from_json(data)).covers.is_empty():
		return "old data with a cover block kept it in the loader or the state"
	var forced: Dictionary = RuleChecks.room(Vector2i(3, 8), [[Vector2i(6, 8), PISTOL, UP]])
	forced["covers"] = [Rect2(100.0, 500.0, 60.0, 28.0)] as Array[Rect2]
	if not RoomState.from_room(forced).covers.is_empty():
		return "RoomState.from_room kept a cover block while the switch is off"
	var run: RunState = RunState.new(20260101)
	if run.boss_rooms.size() != RunState.BOSS_PHASES:
		return "boss has %d phases" % run.boss_rooms.size()
	for phase: Dictionary in run.boss_rooms:
		if not phase["covers"].is_empty() or not RoomState.from_room(Rooms.mirror(phase)).covers.is_empty():
			return "boss phase %s has cover" % phase["id"]
	print("CHECK no cover: from_room and the loader strip old cover data, a mirrored room and all %d boss phases have 0 cover blocks" % run.boss_rooms.size())
	return ""
