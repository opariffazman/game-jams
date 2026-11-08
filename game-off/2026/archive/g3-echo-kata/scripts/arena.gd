class_name Arena
extends Node2D
## The room: draws floor, dummies, figures, strike smears, and resolves strikes.

## Emitted once per dummy that falls, with its world position.
signal dummy_killed(world_pos: Vector2)

## Strike radius in px.
const STRIKE_RANGE: float = 70.0
## Playable floor area in world space.
const ROOM: Rect2 = Rect2(20.0, 130.0, 500.0, 436.0)
## Fixed dummy layout, so every take and every ghost sees the same room.
const DUMMY_SPOTS: Array[Vector2] = [
	Vector2(110.0, 210.0), Vector2(430.0, 200.0), Vector2(270.0, 290.0),
	Vector2(90.0, 400.0), Vector2(450.0, 390.0), Vector2(270.0, 440.0),
]
const FALL_SECONDS: float = 0.4
const SMEAR_SECONDS: float = 0.25

## Figures drawn above the dummies.
var figures: Array[Figure] = []
## Pauses fall and smear animation during hit stop.
var frozen: bool = false
var _dummy_fall: PackedFloat32Array = PackedFloat32Array()
var _dummy_dir: PackedFloat32Array = PackedFloat32Array()
var _smears: Array[Dictionary] = []


func _ready() -> void:
	reset_dummies()


func _process(delta: float) -> void:
	if not frozen:
		for i: int in _dummy_fall.size():
			if _dummy_fall[i] >= 0.0:
				_dummy_fall[i] += delta
		for fig: Figure in figures:
			fig.animate(delta)
		for smear: Dictionary in _smears:
			smear["age"] = float(smear["age"]) + delta
		_smears = _smears.filter(func(s: Dictionary) -> bool: return float(s["age"]) < SMEAR_SECONDS)
	queue_redraw()


## Stand all dummies back up and clear smears.
func reset_dummies() -> void:
	_dummy_fall.resize(DUMMY_SPOTS.size())
	_dummy_dir.resize(DUMMY_SPOTS.size())
	_dummy_fall.fill(-1.0)
	_dummy_dir.fill(1.0)
	_smears.clear()


## Fire an arc strike from [param origin]. Returns how many dummies fell.
func strike_at(origin: Vector2, facing: float) -> int:
	_smears.append({"pos": origin, "ang": 0.0 if facing >= 0.0 else PI, "age": 0.0})
	var kills: int = 0
	for i: int in DUMMY_SPOTS.size():
		if _dummy_fall[i] < 0.0 and DUMMY_SPOTS[i].distance_to(origin) <= STRIKE_RANGE:
			_dummy_fall[i] = 0.0
			_dummy_dir[i] = 1.0 if DUMMY_SPOTS[i].x >= origin.x else -1.0
			kills += 1
			_spawn_burst(DUMMY_SPOTS[i] + Vector2(0.0, -10.0))
			dummy_killed.emit(DUMMY_SPOTS[i])
	return kills


## Number of dummies still standing.
func alive_count() -> int:
	return DUMMY_SPOTS.size() - fallen_count()


## Number of dummies that have been hit.
func fallen_count() -> int:
	var count: int = 0
	for fall: float in _dummy_fall:
		if fall >= 0.0:
			count += 1
	return count


## Position of the standing dummy closest to [param from], or [constant Vector2.INF] if none stand.
func nearest_alive(from: Vector2) -> Vector2:
	var best: Vector2 = Vector2.INF
	for i: int in DUMMY_SPOTS.size():
		if _dummy_fall[i] < 0.0 and (best == Vector2.INF or from.distance_to(DUMMY_SPOTS[i]) < from.distance_to(best)):
			best = DUMMY_SPOTS[i]
	return best


func _draw() -> void:
	_draw_room()
	for fig: Figure in figures:
		fig.draw(self)
	for i: int in DUMMY_SPOTS.size():
		var fall: float = _dummy_fall[i]
		var progress: float = 0.0 if fall < 0.0 else clampf(fall / FALL_SECONDS, 0.0, 1.0)
		var tint: Color = Color(Palette.MAGENTA, 1.0 if fall < 0.0 else lerpf(1.0, 0.45, progress))
		Figure.draw_pose(self, DUMMY_SPOTS[i], tint, 6.0, _dummy_dir[i], 0.0, 0.0, progress * progress, true)
	for smear: Dictionary in _smears:
		_draw_smear(smear)


func _draw_room() -> void:
	draw_rect(ROOM, Color(Palette.INK, 0.04), true)
	draw_rect(ROOM, Color(Palette.INK, 0.28), false, 2.0)
	for i: int in range(1, 5):
		var x: float = ROOM.position.x + ROOM.size.x * i / 5.0
		draw_line(Vector2(x, ROOM.position.y), Vector2(x, ROOM.end.y), Color(Palette.INK, 0.06), 1.0)
	for i: int in range(1, 4):
		var y: float = ROOM.position.y + ROOM.size.y * i / 4.0
		draw_line(Vector2(ROOM.position.x, y), Vector2(ROOM.end.x, y), Color(Palette.INK, 0.06), 1.0)


func _draw_smear(smear: Dictionary) -> void:
	var age: float = float(smear["age"])
	var origin: Vector2 = smear["pos"]
	var start: float = float(smear["ang"])
	var sweep: float = clampf(age / 0.1, 0.0, 1.0)
	var fade: float = 1.0 - age / SMEAR_SECONDS
	draw_arc(origin, STRIKE_RANGE, start, start + TAU * sweep, 40, Color(Palette.AMBER, fade * 0.45), 16.0 * fade, true)
	draw_arc(origin, STRIKE_RANGE, start, start + TAU * sweep, 40, Color(Palette.AMBER, fade), 5.0, true)
	draw_arc(origin, STRIKE_RANGE * 0.9, start + TAU * sweep * 0.6, start + TAU * sweep, 16, Color(Palette.INK, fade), 2.0, true)


func _spawn_burst(at: Vector2) -> void:
	for tint: Color in [Palette.AMBER, Palette.MAGENTA]:
		var burst: CPUParticles2D = CPUParticles2D.new()
		burst.position = at
		burst.one_shot = true
		burst.amount = 14
		burst.lifetime = 0.55
		burst.explosiveness = 1.0
		burst.direction = Vector2.UP
		burst.spread = 180.0
		burst.initial_velocity_min = 90.0
		burst.initial_velocity_max = 260.0
		burst.gravity = Vector2(0.0, 520.0)
		burst.scale_amount_min = 2.0
		burst.scale_amount_max = 4.5
		burst.color = tint
		burst.finished.connect(burst.queue_free)
		add_child(burst)
		burst.emitting = true
