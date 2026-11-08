extends SceneTree
## Diagnosis probe for bug 1: the angular window that topples the stack, and the effect of defenders.
##
## Part A sweeps the aim error in 1 degree steps at three ring angles with no defenders.
## Part B throws from the ring slot the round manager uses, at 0 and 4 degrees error, 40 times each
## with the three defenders orbiting at random phases. It writes nothing to the game.
## Run: godot --headless --path game --fixed-fps 60 --script res://tests/diagnose_window.gd

const CHARACTER_SCENE: String = "res://scenes/character.tscn"
const ARENA_SCENE: String = "res://scenes/arena.tscn"
const FLIGHT_FRAMES: int = 150

var _tuning: Tuning
var _arena: Arena
var _stage: Node2D


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


func _spawn(team: int, role: Character.Role, position: Vector2) -> Character:
	var character: Character = (load(CHARACTER_SCENE) as PackedScene).instantiate() as Character
	character.configure(team, role, _tuning, SkinRef.get_visual_set())
	character.arena = _arena
	character.stack = _arena.stack
	character.position = position
	character.pickup_enabled = false
	_arena.add_child(character)
	_arena.register_character(character)
	return character


func _throw(angle: float, error_degrees: float, orbit_phase: float, with_defenders: bool) -> bool:
	_build()
	if with_defenders:
		for index: int in 3:
			var orbit_angle: float = orbit_phase + TAU * float(index) / 3.0
			var defender: Character = _spawn(1, Character.Role.DEFENDER, _arena.centre_spot + Vector2.from_angle(orbit_angle) * _tuning.orbit_radius)
			defender.hold_on_ring(_arena.centre_spot, _tuning.orbit_radius, _tuning.orbit_radius * _tuning.orbit_speed, true)
	var attacker: Character = _spawn(0, Character.Role.ATTACKER, _arena.centre_spot + Vector2.from_angle(angle) * _tuning.throw_radius)
	await _frames(2)
	var sandal: Sandal = Sandal.new()
	sandal.tuning = _tuning
	sandal.position = attacker.position
	_arena.add_child(sandal)
	attacker.pick_up(sandal)
	await _frames(2)
	var to_stack: Vector2 = (_arena.centre_spot - attacker.global_position).normalized()
	attacker.throw_sandal(to_stack.rotated(deg_to_rad(error_degrees)), 1.0)
	await _frames(FLIGHT_FRAMES)
	return _arena.stack.is_down


func _run() -> void:
	print("PART A: topple by aim error (degrees), no defenders, ring angles 0, 90, 180 (each side of zero)")
	for ring_angle: float in [0.0, 90.0, 180.0, 156.0, 204.0]:
		var row: String = "ring %3d: " % int(ring_angle)
		var lowest: float = 99.0
		var highest: float = -99.0
		for error_tenths: int in range(-180, 181, 10):
			var error_degrees: float = float(error_tenths) / 10.0
			var toppled: bool = await _throw(deg_to_rad(ring_angle), error_degrees, 0.0, false)
			row += "%s" % ("#" if toppled else ".")
			if toppled:
				lowest = minf(lowest, error_degrees)
				highest = maxf(highest, error_degrees)
		print(row, "   (columns -18..+18 deg, # = topple)   window %.0f..%.0f deg" % [lowest, highest])
	print("PART B: orbiting defenders, ring slot angle 156 (the human slot, queue position 0), 40 phases each")
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 41
	for error_degrees: float in [0.0, 4.0, 8.0, 12.0]:
		var toppled: int = 0
		for _n: int in 40:
			var phase: float = rng.randf() * TAU
			if await _throw(deg_to_rad(156.0), error_degrees, phase, true):
				toppled += 1
		print("aim error %+.0f deg with 3 orbiting defenders: topple %d of 40 (%.0f percent)" % [error_degrees, toppled, 100.0 * float(toppled) / 40.0])
	quit(0)
