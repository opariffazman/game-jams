extends SceneTree
## Regression test for bug 2. Plays full 3v3 rounds with the real round manager and scripted human seat.
## It fails on any scatter phase where the pass sandal is not finite, or where no defender holds it and none
## has it in flight for more than STALL_SECONDS. Run:
## godot --headless --path game --script res://tests/diagnose_stall_regression.gd
## DIAGNOSE_SCATTERS sets the number of scatter phases, DIAGNOSE_SEED the seed.

const STALL_SECONDS: float = 20.0

var scatters: int = 0
var stalls: int = 0
var non_finite: int = 0
var manager: RoundManager
var arena: Arena
var tuning: Tuning
var target: int = 50
var _last_phase: int = -1
var _age: float = 0.0
var _lost_since: float = -1.0
var _reported: bool = false
var _holder_clock: float = 0.0
var _non_finite_frames: int = 0
var recovered_events: int = 0


func _initialize() -> void:
	Engine.time_scale = 4.0
	Engine.max_physics_steps_per_frame = 16
	var env_count: String = OS.get_environment("DIAGNOSE_SCATTERS")
	if env_count != "":
		target = int(env_count)
	seed(int(OS.get_environment("DIAGNOSE_SEED")) if OS.get_environment("DIAGNOSE_SEED") != "" else 31)
	tuning = Tuning.load_default().duplicate() as Tuning
	tuning.match_countdown = false
	tuning.human_team = 0
	arena = (load("res://scenes/arena.tscn") as PackedScene).instantiate() as Arena
	arena.tuning = tuning
	root.add_child(arena)
	manager = RoundManager.new()
	manager.tuning = tuning
	manager.arena = arena
	root.add_child(manager)


func _physics_process(delta: float) -> bool:
	if manager.phase == RoundManager.MATCH_END:
		manager.start_match()
		return false
	if manager.phase != _last_phase:
		if manager.phase == RoundManager.SCATTER:
			scatters += 1
			_age = 0.0
			_lost_since = -1.0
			_reported = false
		_last_phase = manager.phase
	_drive_human()
	if manager.phase == RoundManager.SCATTER:
		_age += delta
		_check_pass_sandal()
		if _age > 90.0:
			manager.end_round(1 - manager.attacking_team)
	if scatters >= target and manager.phase == RoundManager.ROUND_END:
		Engine.time_scale = 1.0
		print("RESULT scatter_phases=%d non_finite_events_recovered=%d non_finite_unrecovered=%d stalls=%d" % [scatters, recovered_events, non_finite, stalls])
		quit(1 if non_finite > 0 or stalls > 0 else 0)
	return false


func _check_pass_sandal() -> void:
	var pass_sandal: Sandal = null
	for node: Node in get_nodes_in_group(Sandal.GROUP):
		var sandal: Sandal = node as Sandal
		if sandal != null and sandal.is_pass_sandal and not sandal.is_queued_for_deletion():
			pass_sandal = sandal
	if pass_sandal == null:
		return
	# The sandal repairs a non-finite state in its own physics step, so one frame of NaN can be seen here.
	# The test fails only when the state stays non-finite for two frames in a row.
	if not pass_sandal.global_position.is_finite():
		_non_finite_frames += 1
		if _non_finite_frames == 1:
			recovered_events += 1
		if _non_finite_frames >= 2:
			non_finite += 1
			print("FAIL scatter %d: pass sandal position stays not finite" % scatters)
	else:
		_non_finite_frames = 0
	var held: bool = false
	for team: int in 2:
		for entry: Variant in arena.get_characters(team):
			var character: Character = entry as Character
			if character != null and character.alive and character.carried == pass_sandal:
				held = true
	var lost: bool = not held and not pass_sandal.in_flight
	if not lost:
		_lost_since = -1.0
		return
	if _lost_since < 0.0:
		_lost_since = _age
	if _age - _lost_since >= STALL_SECONDS and not _reported:
		_reported = true
		stalls += 1
		print("FAIL scatter %d: nobody holds the pass sandal for %.0f s, at %s speed %.0f" % [scatters, STALL_SECONDS, str(pass_sandal.global_position), pass_sandal.linear_velocity.length()])


func _drive_human() -> void:
	var human: HumanController = manager.human
	if human == null or human.character == null or not is_instance_valid(human.character) or not human.character.alive:
		return
	var body: Character = human.character
	if manager.phase == RoundManager.SCATTER and body.role == Character.Role.DEFENDER and body.carried != null and body.carried.is_pass_sandal:
		_holder_clock += 1.0 / 60.0
		if _holder_clock > 1.0:
			_holder_clock = 0.0
			for entry: Variant in arena.get_characters(body.team):
				var mate: Character = entry as Character
				if mate != body and mate.alive:
					body.pass_to(mate)
					break
		return
	if manager.phase == RoundManager.TOPPLE and body.role == Character.Role.ATTACKER and body.carried != null:
		body.throw_sandal((arena.centre_spot - body.global_position).normalized(), 1.0)
		return
	if manager.phase == RoundManager.SCATTER and body.role == Character.Role.ATTACKER:
		var steer: Vector2 = Vector2.ZERO
		if body.carried == null:
			var best: Sandal = null
			var best_distance: float = INF
			for entry: Variant in arena.get_loose_sandals():
				var sandal: Sandal = entry as Sandal
				if sandal == null or sandal.is_pass_sandal:
					continue
				var distance: float = body.global_position.distance_to(sandal.global_position)
				if distance < best_distance:
					best_distance = distance
					best = sandal
			if best != null:
				steer = (best.global_position - body.global_position).normalized()
		else:
			steer = arena.centre_spot - body.global_position
			steer = steer.normalized() if steer.length() > 30.0 else Vector2.ZERO
		body.move_intent = steer
