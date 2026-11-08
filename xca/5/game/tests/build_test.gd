extends SceneTree
## Headless test of the pyramid rebuild: QTE timing, carry rule, hit cancels a build, scatter timeout
## and bots that finish builds over seeded rounds.
##
## Run: godot --headless --path game --script res://tests/build_test.gd

const ARENA_SCENE: String = "res://scenes/arena.tscn"
const CHARACTER_SCENE: String = "res://scenes/character.tscn"
const SEEDED_ROUNDS: int = 10
const MAX_ROUND_FRAMES: int = 9000
const ROUND_SEED: int = 20261107

var _failures: int = 0
var _stage: Node2D
var _arena: Arena
var _tuning: Tuning


func _initialize() -> void:
	await _run()
	print("build_test: %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(_failures)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   ", label)
	else:
		print("  FAIL ", label)
		_failures += 1


func _frames(count: int) -> void:
	for _i: int in count:
		await physics_frame


func _run() -> void:
	_test_qte_windows()
	await _test_carry_one_at_a_time()
	await _test_hit_cancels_build()
	await _test_defender_bodies_never_move_sandals()
	await _test_scatter_timeout()
	await _test_bots_build_over_seeded_rounds()


func _build_stage() -> void:
	if _stage != null:
		root.remove_child(_stage)
		_stage.free()
	_stage = Node2D.new()
	root.add_child(_stage)
	_tuning = Tuning.load_default().duplicate() as Tuning
	_tuning.match_countdown = false
	_tuning.human_team = -1
	_arena = (load(ARENA_SCENE) as PackedScene).instantiate() as Arena
	_arena.tuning = _tuning
	_stage.add_child(_arena)


func _spawn(team: int, role: Character.Role, at: Vector2) -> Character:
	var character: Character = (load(CHARACTER_SCENE) as PackedScene).instantiate() as Character
	character.configure(team, role, _tuning)
	character.arena = _arena
	character.stack = _arena.stack
	character.position = at
	_arena.add_child(character)
	return character


## Topples the pyramid and puts all three sandals in the build zone.
func _prepare_down_pyramid() -> void:
	var stack: Stack = _arena.stack
	stack._topple()
	var free: Array[Sandal] = []
	for node: Node in get_nodes_in_group(Sandal.GROUP):
		if node.get_parent() == stack:
			free.append(node as Sandal)
	for index: int in free.size():
		free[index].halt()
		free[index].global_position = _arena.centre_spot + Vector2.from_angle(float(index) * 2.0) * 40.0


func _test_qte_windows() -> void:
	var tuning: Tuning = Tuning.load_default()
	var qte: BuildQte = BuildQte.new(tuning, 7)
	var passed: Array[int] = []
	var misses: Array[int] = [0]
	qte.step_passed.connect(func(step: int) -> void: passed.append(step))
	qte.missed.connect(func() -> void: misses[0] += 1)
	qte.start()
	_check(qte.kind == BuildQte.Kind.TAP, "the first prompt is a tap")
	qte.update(tuning.qte_tap_seconds * 0.3)
	qte.tap()
	_check(misses[0] == 1, "a tap while the ring is far out is a miss")
	_check(qte.penalty_left == tuning.miss_penalty_seconds, "a miss costs miss_penalty_seconds")
	qte.tap()
	_check(misses[0] == 1 and passed.is_empty(), "input during the penalty is ignored")
	qte.update(tuning.miss_penalty_seconds + 0.01)
	_check(qte.penalty_left == 0.0 and qte.step == 0, "the penalty ends and the step stays the same")
	qte.update(tuning.qte_tap_seconds)
	_check(qte.in_window(), "the window opens when the ring reaches the target")
	qte.tap()
	_check(passed == [0] and qte.step == 1, "a tap in the window passes step 0")
	_check(qte.kind == BuildQte.Kind.SWIPE, "the next prompt is a swipe")
	var wrong: Vector2 = -qte.direction
	qte.swipe(wrong)
	_check(misses[0] == 2, "a swipe the wrong way is a miss")
	qte.update(tuning.miss_penalty_seconds + 0.01)
	qte.swipe(qte.direction * 5.0)
	_check(qte.step == 2, "a swipe the right way passes step 1")
	qte.update(tuning.qte_tap_seconds + tuning.qte_window_seconds + 0.01)
	_check(misses[0] == 3, "a tap prompt that times out is a miss")
	qte.update(tuning.miss_penalty_seconds + 0.01)
	var finished: Array[bool] = [false]
	qte.finished.connect(func() -> void: finished[0] = true)
	qte.update(tuning.qte_tap_seconds)
	qte.tap()
	_check(finished[0] and not qte.active, "the last step ends the QTE")
	var again: BuildQte = BuildQte.new(tuning, 7)
	var other: BuildQte = BuildQte.new(tuning, 7)
	again.start(1)
	other.start(1)
	_check(again.direction == other.direction, "the same seed gives the same prompt")


func _test_carry_one_at_a_time() -> void:
	_build_stage()
	await _frames(2)
	var attacker: Character = _spawn(0, Character.Role.ATTACKER, _arena.centre_spot + Vector2(-300.0, 0.0))
	await _frames(2)
	var first: Sandal = Sandal.new()
	first.tuning = _tuning
	first.position = attacker.position + Vector2(_tuning.pickup_radius * 3.0, 0.0)
	_arena.add_child(first)
	var second: Sandal = Sandal.new()
	second.tuning = _tuning
	second.position = attacker.position + Vector2(0.0, _tuning.pickup_radius * 3.0)
	_arena.add_child(second)
	await _frames(2)
	_check(attacker.pick_up(first), "attacker picks up one sandal")
	_check(not attacker.pick_up(second), "attacker cannot carry a second sandal")


func _test_hit_cancels_build() -> void:
	_build_stage()
	await _frames(2)
	_prepare_down_pyramid()
	var stack: Stack = _arena.stack
	var builder: Character = _spawn(0, Character.Role.ATTACKER, _arena.centre_spot)
	await _frames(2)
	_check(stack.can_build(), "three sandals in the zone allow a build")
	_check(builder.start_building(), "the builder starts")
	_check(builder.complete_build_step(), "the builder places the first sandal")
	var ended: Array[bool] = []
	stack.build_ended.connect(func(_who: Character, completed: bool) -> void: ended.append(completed))
	builder.die()
	_check(ended == [false], "a hit on the builder cancels the build")
	_check(stack.builder == null, "nobody builds after the hit")
	_check(stack.placed_count == 1, "the placed sandal stays placed")
	var flying: Sandal = Sandal.new()
	flying.tuning = _tuning
	flying.position = stack.to_global(stack.slot_positions[0]) + Vector2(_tuning.sandal_radius, 0.0)
	flying.collision_mask = 0
	_arena.add_child(flying)
	await _frames(2)
	flying.linear_velocity = Vector2.RIGHT * _tuning.knock_min_speed * 1.5
	flying.in_flight = true
	await _frames(2)
	_check(stack.placed_count == 0, "a flying sandal knocks the placed sandals loose")


func _test_scatter_timeout() -> void:
	_build_stage()
	var manager: RoundManager = RoundManager.new()
	manager.tuning = _tuning
	manager.arena = _arena
	_stage.add_child(manager)
	manager.start_match()
	await _frames(2)
	var winners: Array[int] = []
	manager.round_ended.connect(func(winner: int) -> void: winners.append(winner))
	var attackers: int = manager.attacking_team
	manager.phase = RoundManager.SCATTER
	manager.scatter_time_left = 0.05
	await _frames(10)
	_check(winners.size() == 1 and winners[0] == 1 - attackers, "the scatter timeout gives the defenders the round")


func _test_bots_build_over_seeded_rounds() -> void:
	_build_stage()
	seed(ROUND_SEED)
	var manager: RoundManager = RoundManager.new()
	manager.tuning = _tuning
	manager.arena = _arena
	_stage.add_child(manager)
	var tally: Array[int] = [0, 0]
	manager.round_ended.connect(func(winner: int) -> void:
		tally[0] += 1
		if winner == manager.attacking_team and _arena.stack.is_built:
			tally[1] += 1)
	manager.start_match()
	var frames: int = 0
	while tally[0] < SEEDED_ROUNDS and frames < MAX_ROUND_FRAMES * SEEDED_ROUNDS:
		if manager.phase == RoundManager.MATCH_END:
			manager.start_match()
		await physics_frame
		frames += 1
	_check(tally[0] >= SEEDED_ROUNDS, "%d seeded rounds finish (got %d)" % [SEEDED_ROUNDS, tally[0]])
	_check(tally[1] >= 1, "bot attackers finish at least one build in %d rounds (got %d)" % [SEEDED_ROUNDS, tally[1]])
	print("  builds %d of %d rounds" % [tally[1], tally[0]])


func _test_defender_bodies_never_move_sandals() -> void:
	_build_stage()
	await _frames(2)
	var defender: Character = _spawn(1, Character.Role.DEFENDER, _arena.centre_spot + Vector2(-300.0, 0.0))
	var spots: Array[Vector2] = [_arena.centre_spot + Vector2(-40.0, 0.0), _arena.centre_spot + Vector2(-200.0, 200.0)]
	var sandals: Array[Sandal] = []
	for spot: Vector2 in spots:
		var sandal: Sandal = Sandal.new()
		sandal.tuning = _tuning
		sandal.position = spot
		_arena.add_child(sandal)
		sandals.append(sandal)
	await _frames(3)
	for sandal: Sandal in sandals:
		sandal.halt()
	var starts: Array[Vector2] = [sandals[0].global_position, sandals[1].global_position]
	for index: int in 2:
		defender.global_position = starts[index] + Vector2(-100.0, 0.0)
		for _i: int in 60:
			defender.move_intent = Vector2.RIGHT
			await physics_frame
	defender.move_intent = Vector2.ZERO
	_check(sandals[0].global_position.distance_to(starts[0]) < 1.0, "a defender running through a zone sandal moves none of it")
	_check(sandals[1].global_position.distance_to(starts[1]) < 1.0, "a defender running through a sandal outside the zone moves none of it")
