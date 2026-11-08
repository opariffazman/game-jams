extends SceneTree
## Diagnosis probe for bug 1: what the ranged throw does in the frames around the first contact.
##
## Throws one centred sandal from the left ring slot with no defenders and prints speed, contact count,
## range left and the stack sandals' positions for every frame from 8 to 24. It writes nothing to the game.
## Run: godot --headless --path game --fixed-fps 60 --script res://tests/diagnose_impact.gd

const CHARACTER_SCENE: String = "res://scenes/character.tscn"
const ARENA_SCENE: String = "res://scenes/arena.tscn"


func _initialize() -> void:
	_run()


func _run() -> void:
	var tuning: Tuning = Tuning.load_default().duplicate() as Tuning
	tuning.match_countdown = false
	var arena: Arena = (load(ARENA_SCENE) as PackedScene).instantiate() as Arena
	arena.tuning = tuning
	root.add_child(arena)
	var attacker: Character = (load(CHARACTER_SCENE) as PackedScene).instantiate() as Character
	attacker.configure(0, Character.Role.ATTACKER, tuning, SkinRef.get_visual_set())
	attacker.arena = arena
	attacker.stack = arena.stack
	attacker.pickup_enabled = false
	attacker.position = arena.centre_spot + Vector2(-tuning.throw_radius, 0.0)
	arena.add_child(attacker)
	arena.register_character(attacker)
	await physics_frame
	await physics_frame
	var sandal: Sandal = Sandal.new()
	sandal.tuning = tuning
	sandal.position = attacker.position
	arena.add_child(sandal)
	attacker.pick_up(sandal)
	await physics_frame
	var spots: Array[Vector2] = []
	for standing: Sandal in arena.stack.standing_sandals:
		spots.append(standing.global_position)
	attacker.throw_sandal(Vector2.RIGHT, 1.0)
	print("frame  x_from_centre  speed  contacts  range_left  damp_mode  stack_disp(top,mid,bottom)  is_down")
	for frame: int in range(0, 40):
		await physics_frame
		if not is_instance_valid(sandal):
			break
		var stack_sandals: Array = arena.stack.get_children().filter(func(n: Node) -> bool: return n is Sandal)
		var disp: Array[String] = []
		for index: int in mini(stack_sandals.size(), 3):
			var other: Sandal = stack_sandals[index]
			disp.append("%.0f" % other.global_position.distance_to(spots[index]))
		if frame >= 8 and frame <= 30:
			print("%3d  %8.1f  %7.1f  %d  %7.1f  %d  %s  %s" % [frame, sandal.global_position.x - arena.centre_spot.x, sandal.linear_velocity.length(), sandal.get_contact_count(), sandal._range_left, sandal.linear_damp_mode, ",".join(disp), str(arena.stack.is_down)])
	quit(0)
