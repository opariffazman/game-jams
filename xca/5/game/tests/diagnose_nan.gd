extends SceneTree
## Reproduces the NaN pass sandal. A flying pass sandal meets a sandal that a dying attacker drops on top of it.
## die() teleports the dropped sandal with global_position, while the pass sandal flies at full speed.
## Run: godot --headless --path game --fixed-fps 60 --script res://tests/diagnose_nan.gd
## Prints one line per variant and a summary. A trial fails when the sandal position or velocity is NaN.

const TRIALS: int = 40

var _results: Dictionary = {}


func _initialize() -> void:
	_run()


func _spawn(arena: Arena, tuning: Tuning, team: int, role: Character.Role, at: Vector2) -> Character:
	var character: Character = (load("res://scenes/character.tscn") as PackedScene).instantiate() as Character
	character.configure(team, role, tuning, SkinRef.get_visual_set())
	character.arena = arena
	character.stack = arena.stack
	character.position = at
	arena.add_child(character)
	arena.register_character(character)
	return character


func _trial(variant: String, rng: RandomNumberGenerator) -> bool:
	var tuning: Tuning = Tuning.load_default().duplicate() as Tuning
	tuning.match_countdown = false
	var stage: Node2D = Node2D.new()
	root.add_child(stage)
	var arena: Arena = (load("res://scenes/arena.tscn") as PackedScene).instantiate() as Arena
	arena.tuning = tuning
	stage.add_child(arena)
	var passer: Character = _spawn(arena, tuning, 1, Character.Role.DEFENDER, arena.centre_spot + Vector2(-260.0, 0.0))
	var attacker: Character = _spawn(arena, tuning, 0, Character.Role.ATTACKER, arena.centre_spot + Vector2(120.0, rng.randf_range(-12.0, 12.0)))
	attacker.pickup_enabled = false
	await physics_frame
	await physics_frame
	var carried: Sandal = null
	if variant != "dies_empty_handed":
		carried = Sandal.new()
		carried.tuning = tuning
		carried.position = attacker.position
		arena.add_child(carried)
		attacker.pick_up(carried)
	var sandal: Sandal = Sandal.new()
	sandal.tuning = tuning
	sandal.is_pass_sandal = true
	sandal.position = passer.position
	arena.add_child(sandal)
	passer.pick_up(sandal)
	await physics_frame
	passer.throw_sandal((attacker.global_position - passer.global_position).normalized(), 1.0)
	var bad: bool = false
	var died: bool = false
	for frame: int in 60:
		await physics_frame
		if not died and is_instance_valid(sandal) and sandal.global_position.distance_to(attacker.global_position) < 45.0 + rng.randf_range(0.0, 15.0):
			died = true
			attacker.die()
		if is_instance_valid(sandal) and (is_nan(sandal.global_position.x) or is_nan(sandal.linear_velocity.x)):
			bad = true
			break
	root.remove_child(stage)
	stage.free()
	return bad


func _run() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 5
	for variant: String in ["dies_carrying_a_sandal", "dies_empty_handed"]:
		var bad: int = 0
		for _t: int in TRIALS:
			if await _trial(variant, rng):
				bad += 1
		print("variant %-24s NaN in %2d of %d trials" % [variant, bad, TRIALS])
	quit(0)
