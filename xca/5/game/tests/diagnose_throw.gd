extends SceneTree
## Diagnosis probe for bug 1: can an attacker topple the stack with Character.throw_sandal?
##
## Parks every defender away from the lane, puts one attacker on the throw ring at 12 angles, throws
## at the stack centre and records what the sandal does. It repeats with an aim error. Writes nothing
## to the game. Run: godot --headless --path game --fixed-fps 60 --script res://tests/diagnose_throw.gd

const CHARACTER_SCENE: String = "res://scenes/character.tscn"
const ARENA_SCENE: String = "res://scenes/arena.tscn"
const ANGLES: int = 12
const ERRORS_DEGREES: Array[float] = [0.0, 3.0, 6.0, 10.0, 15.0]
const FLIGHT_FRAMES: int = 150

var _tuning: Tuning
var _arena: Arena
var _stage: Node2D
var _attacker: Character
var _thrown: Sandal
var _first_contact_speed: float = -1.0
var _contact_frame: int = -1
var _max_displacement: Array[float] = [0.0, 0.0, 0.0]
var _flight_frames: int = 0
var _halted_in_stack: bool = false


func _initialize() -> void:
	_run()


func _frames(count: int) -> void:
	for _i: int in count:
		await physics_frame


func _build() -> void:
	if _stage != null:
		root.remove_child(_stage)
		_stage.free()
	_stage = Node2D.new()
	root.add_child(_stage)
	_tuning = Tuning.load_default().duplicate() as Tuning
	_tuning.match_countdown = false
	_arena = (load(ARENA_SCENE) as PackedScene).instantiate() as Arena
	_arena.tuning = _tuning
	_stage.add_child(_arena)


func _spawn_attacker(angle: float) -> Character:
	var character: Character = (load(CHARACTER_SCENE) as PackedScene).instantiate() as Character
	character.configure(0, Character.Role.ATTACKER, _tuning, SkinRef.get_visual_set())
	character.arena = _arena
	character.stack = _arena.stack
	character.position = _arena.centre_spot + Vector2.from_angle(angle) * _tuning.throw_radius
	character.pickup_enabled = false
	_arena.add_child(character)
	_arena.register_character(character)
	return character


func _throw_once(angle: float, error_degrees: float) -> Dictionary:
	_build()
	_attacker = _spawn_attacker(angle)
	await _frames(2)
	var sandal: Sandal = Sandal.new()
	sandal.tuning = _tuning
	sandal.position = _attacker.position
	_arena.add_child(sandal)
	_attacker.pick_up(sandal)
	await _frames(2)
	_thrown = sandal
	var spots: Array[Vector2] = []
	for standing: Sandal in _arena.stack.standing_sandals:
		spots.append(standing.global_position)
	var to_stack: Vector2 = (_arena.centre_spot - _attacker.global_position).normalized()
	var direction: Vector2 = to_stack.rotated(deg_to_rad(error_degrees))
	_attacker.throw_sandal(direction, 1.0)
	var speed_at_contact: float = -1.0
	var contact_frame: int = -1
	var toppled_frame: int = -1
	var max_disp: Array[float] = [0.0, 0.0, 0.0]
	var halted_frame: int = -1
	var halted_position: Vector2 = Vector2.ZERO
	var path_min_distance: float = INF
	for frame: int in FLIGHT_FRAMES:
		await physics_frame
		if not is_instance_valid(sandal):
			break
		var speed: float = sandal.linear_velocity.length()
		path_min_distance = minf(path_min_distance, sandal.global_position.distance_to(_arena.centre_spot))
		if contact_frame < 0 and sandal.get_contact_count() > 0:
			contact_frame = frame
			speed_at_contact = speed
		if halted_frame < 0 and not sandal.in_flight:
			halted_frame = frame
			halted_position = sandal.global_position
		for index: int in mini(spots.size(), 3):
			var other: Sandal = _arena.stack.get_child(index) as Sandal if index < _arena.stack.get_child_count() else null
			if other != null and is_instance_valid(other):
				max_disp[index] = maxf(max_disp[index], other.global_position.distance_to(spots[index]))
		if toppled_frame < 0 and _arena.stack.is_down:
			toppled_frame = frame
	return {
		"toppled": _arena.stack.is_down,
		"toppled_frame": toppled_frame,
		"contact_frame": contact_frame,
		"speed_at_contact": speed_at_contact,
		"halted_frame": halted_frame,
		"halted_distance_from_centre": halted_position.distance_to(_arena.centre_spot) if halted_frame >= 0 else -1.0,
		"min_distance_to_centre": path_min_distance,
		"max_displacement": max_disp,
		"end_distance_from_centre": sandal.global_position.distance_to(_arena.centre_spot) if is_instance_valid(sandal) else -1.0,
	}


func _run() -> void:
	var tuning: Tuning = Tuning.load_default()
	var hand_offset: float = tuning.character_radius + 12.0
	print("geometry: throw_radius=%.0f hand_offset=%.0f ranged_distance=%.0f stack_sandal_radius=%.0f stack_gap=%.0f topple_distance=%.0f" % [tuning.throw_radius, hand_offset, tuning.throw_radius - hand_offset, tuning.sandal_radius, tuning.stack_gap, tuning.topple_distance])
	var step: float = tuning.sandal_radius * 2.0 + tuning.stack_gap
	print("stack spots (y offsets from centre): %.0f, 0, %.0f ; sandal reaches centre ring at %.0f px from thrower start" % [-step, step, tuning.throw_radius - hand_offset])
	for error_degrees: float in ERRORS_DEGREES:
		var toppled: int = 0
		var rows: Array[String] = []
		for index: int in ANGLES:
			var angle: float = TAU * float(index) / float(ANGLES)
			var result: Dictionary = await _throw_once(angle, error_degrees)
			if result["toppled"]:
				toppled += 1
			rows.append("  angle %3d toppled=%s contact_f=%d v_contact=%.0f halted_f=%d halted_at=%.0f min_dist=%.0f disp=[%.0f,%.0f,%.0f] end=%.0f" % [
				int(rad_to_deg(angle)), str(result["toppled"]), result["contact_frame"], result["speed_at_contact"], result["halted_frame"],
				result["halted_distance_from_centre"], result["min_distance_to_centre"],
				result["max_displacement"][0], result["max_displacement"][1], result["max_displacement"][2], result["end_distance_from_centre"]])
		print("aim error %+.0f deg: topple %d of %d" % [error_degrees, toppled, ANGLES])
		if error_degrees == 0.0 or error_degrees == 10.0:
			for row: String in rows:
				print(row)
	quit(0)
