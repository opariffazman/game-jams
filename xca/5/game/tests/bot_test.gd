extends SceneTree
## Headless test for [BotController] against the real world and character classes.
##
## Part one checks single behaviours with a real [Arena] and real [Character] bodies.
## Part two runs a full 3v3 match with bots on both teams. Run it through
## [code]tests/run_bot_test.sh[/code], which also fails on any engine or script error line.

const STEP: float = 1.0 / 60.0
const CHARACTER_SCENE: String = "res://scenes/character.tscn"
const ARENA_SCENE: String = "res://scenes/arena.tscn"
const SECONDS_PER_ROLE: float = 20.0
const MAX_MATCH_SECONDS: float = 240.0
const APPROACH_DISTANCE: float = 40.0
const BALANCE_ROUNDS: int = 30
const BALANCE_THROW_FRAMES: int = 150

var _failures: int = 0
var _checks: int = 0
var _stage: Node2D
var _arena: Arena
var _tuning: Tuning
var _manager: RoundManager
var _bots: Dictionary = {}


func _initialize() -> void:
	_run_all()


func _run_all() -> void:
	await _test_difficulty_scaling()
	await _test_attacker_throws_handed_sandal()
	await _test_defender_topple_positions()
	await _test_attacker_rebuild_and_avoidance()
	await _test_attacker_dodge()
	await _test_holder_pass_and_shot()
	await _test_support_and_loose_sandals()
	await _test_dead_bot_and_write_boundary()
	await _test_topple_balance()
	await _test_full_match()
	print("bot_test: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: " + label)


func _frames(count: int) -> void:
	for _i: int in count:
		await physics_frame


func _clear_stage() -> void:
	if is_instance_valid(_manager):
		_manager.free()
		_manager = null
	if _stage != null:
		root.remove_child(_stage)
		_stage.free()
	_stage = Node2D.new()
	root.add_child(_stage)
	_bots = {}


func _build(difficulty: float) -> void:
	_clear_stage()
	_tuning = Tuning.load_default().duplicate() as Tuning
	_tuning.match_countdown = false
	_tuning.bot_difficulty = difficulty
	_arena = (load(ARENA_SCENE) as PackedScene).instantiate() as Arena
	_arena.tuning = _tuning
	_stage.add_child(_arena)
	_manager = RoundManager.new()
	_manager.tuning = _tuning
	_manager.arena = _arena
	_manager.attacking_team = 0
	_manager.phase = RoundManager.TOPPLE


func _spawn(team: int, role: Character.Role, at: Vector2) -> Character:
	var character: Character = (load(CHARACTER_SCENE) as PackedScene).instantiate() as Character
	character.configure(team, role, _tuning, SkinRef.get_visual_set())
	character.arena = _arena
	character.stack = _arena.stack
	character.position = at
	_arena.add_child(character)
	_arena.register_character(character)
	var bot: BotController = BotController.new()
	bot.bind(_arena, _manager, _tuning)
	_stage.add_child(bot)
	bot.set_physics_process(false)
	bot.seed_rng(11)
	bot.attach(character)
	_bots[character] = bot
	return character


func _spawn_sandal(at: Vector2, pass_sandal: bool = false) -> Sandal:
	var sandal: Sandal = Sandal.new()
	sandal.tuning = _tuning
	sandal.is_pass_sandal = pass_sandal
	sandal.position = at
	_arena.add_child(sandal)
	return sandal


func _drive(bot: BotController, frames: int) -> void:
	for _i: int in frames:
		bot._physics_process(STEP)
		await physics_frame


func _test_difficulty_scaling() -> void:
	_build(0.0)
	var easy: BotController = BotController.new()
	easy.bind(_arena, _manager, _tuning)
	_build(1.0)
	var hard: BotController = BotController.new()
	hard.bind(_arena, _manager, _tuning)
	_check(easy.aim_error > hard.aim_error, "easy bot has more aim error")
	_check(easy.reaction_delay > hard.reaction_delay, "easy bot reacts slower")
	_check(easy.dodge_chance < hard.dodge_chance, "easy bot dodges less")
	easy.free()
	hard.free()
	await _frames(1)


func _test_attacker_throws_handed_sandal() -> void:
	_build(0.5)
	_manager.phase = RoundManager.TOPPLE
	var ring_spot: Vector2 = _arena.centre_spot + Vector2(-_tuning.throw_radius, 0.0)
	var attacker: Character = _spawn(0, Character.Role.ATTACKER, ring_spot)
	var waiting: Character = _spawn(0, Character.Role.ATTACKER, ring_spot + Vector2(0.0, 90.0))
	attacker.hold_on_ring(_arena.centre_spot, _tuning.throw_radius, _tuning.move_speed)
	await _frames(2)
	var thrown: Array[Sandal] = []
	var throw_origin: Array[Vector2] = []
	var throw_heading: Array[Vector2] = []
	attacker.threw.connect(func(sandal: Sandal) -> void:
		thrown.append(sandal)
		throw_origin.append(attacker.global_position)
		throw_heading.append(sandal.linear_velocity.normalized()))
	waiting.threw.connect(func(sandal: Sandal) -> void: thrown.append(sandal))
	await _drive(_bots[attacker], 30)
	_check(thrown.is_empty(), "attacker with empty hands does not throw")
	attacker.pick_up(_spawn_sandal(attacker.position))
	await _drive(_bots[attacker], 120)
	_check(thrown.size() == 1, "attacker throws the sandal it was handed")
	if thrown.size() == 1:
		var heading: Vector2 = throw_heading[0]
		var wanted: Vector2 = (_arena.centre_spot - throw_origin[0]).normalized()
		_check(absf(heading.angle_to(wanted)) < deg_to_rad(40.0), "throw points at the stack")
		_check(absf(throw_origin[0].distance_to(_arena.centre_spot) - _tuning.throw_radius) < 1.0, "attacker throws from the throw ring")
	_check(attacker.move_intent == Vector2.ZERO, "attacker stands still after the throw")
	await _drive(_bots[attacker], 60)
	_check(thrown.size() == 1, "attacker never throws twice")
	await _drive(_bots[waiting], 60)
	_check(thrown.size() == 1, "queued attacker without a sandal waits")
	var held_ring: float = attacker.global_position.distance_to(_arena.centre_spot)
	_check(absf(held_ring - _tuning.throw_radius) < 1.0, "attacker stays on the throw ring")


func _test_defender_topple_positions() -> void:
	_build(0.5)
	_manager.phase = RoundManager.TOPPLE
	var defenders: Array[Character] = []
	for index: int in 3:
		var angle: float = PI * 0.5 + TAU * float(index) / 3.0
		var defender: Character = _spawn(1, Character.Role.DEFENDER, _arena.centre_spot + Vector2.from_angle(angle) * _tuning.orbit_radius)
		defender.hold_on_ring(_arena.centre_spot, _tuning.orbit_radius, _tuning.orbit_radius * _tuning.orbit_speed, true)
		defenders.append(defender)
	await _frames(1)
	var worst_radius_error: float = 0.0
	var worst_spacing_error: float = 0.0
	for _i: int in 240:
		for defender: Character in defenders:
			_bots[defender]._physics_process(STEP)
		await physics_frame
		for defender: Character in defenders:
			worst_radius_error = maxf(worst_radius_error, absf(defender.global_position.distance_to(_arena.centre_spot) - _tuning.orbit_radius))
		var a: float = (defenders[0].global_position - _arena.centre_spot).angle()
		var b: float = (defenders[1].global_position - _arena.centre_spot).angle()
		var c: float = (defenders[2].global_position - _arena.centre_spot).angle()
		worst_spacing_error = maxf(worst_spacing_error, absf(absf(angle_difference(a, b)) - TAU / 3.0))
		worst_spacing_error = maxf(worst_spacing_error, absf(absf(angle_difference(b, c)) - TAU / 3.0))
	_check(worst_radius_error < 2.0, "defenders stay on the orbit ring (worst error %.2f px)" % worst_radius_error)
	_check(worst_spacing_error < deg_to_rad(4.0), "defenders stay 120 degrees apart (worst error %.2f deg)" % rad_to_deg(worst_spacing_error))
	_check(defenders[0].carried == null and defenders[1].carried == null, "defenders hold nothing in the topple phase")
	var moved: float = defenders[0].global_position.distance_to(_arena.centre_spot + Vector2.from_angle(PI * 0.5) * _tuning.orbit_radius)
	_check(moved > 20.0, "defenders circle on their own")


## Balance probe. Three bot attackers on the throw ring throw once each at three orbiting bot
## defenders, at a random orbit phase. The design sets no target for this rate, so the test prints it
## and only asserts that neither side is absolute: the defenders do not wall the stack off, and a
## topple is not guaranteed.
func _test_topple_balance() -> void:
	var rounds: int = BALANCE_ROUNDS
	var toppled: int = 0
	var first_throw_toppled: int = 0
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	for _round: int in rounds:
		_build(0.5)
		_manager.phase = RoundManager.TOPPLE
		var phase_offset: float = rng.randf() * TAU
		for index: int in 3:
			var angle: float = phase_offset + TAU * float(index) / 3.0
			var defender: Character = _spawn(1, Character.Role.DEFENDER, _arena.centre_spot + Vector2.from_angle(angle) * _tuning.orbit_radius)
			defender.hold_on_ring(_arena.centre_spot, _tuning.orbit_radius, _tuning.orbit_radius * _tuning.orbit_speed, true)
		var spacing: float = deg_to_rad(_tuning.throw_ring_spacing_degrees)
		var attackers: Array[Character] = []
		for index: int in 3:
			var angle: float = PI + (float(index) - 1.0) * spacing
			var attacker: Character = _spawn(0, Character.Role.ATTACKER, _arena.centre_spot + Vector2.from_angle(angle) * _tuning.throw_radius)
			attacker.hold_on_ring(_arena.centre_spot, _tuning.throw_radius, _tuning.move_speed)
			attackers.append(attacker)
		await _frames(2)
		for index: int in 3:
			attackers[index].pick_up(_spawn_sandal(attackers[index].position))
			for _i: int in BALANCE_THROW_FRAMES:
				for entry: Character in _bots.keys():
					_bots[entry]._physics_process(STEP)
				await physics_frame
			if _arena.stack.is_down:
				toppled += 1
				if index == 0:
					first_throw_toppled += 1
				break
	var rate: float = float(toppled) / float(rounds)
	print("  balance: bot attackers topple %d of %d rounds (%.0f percent), first throw %d percent" % [toppled, rounds, rate * 100.0, int(100.0 * float(first_throw_toppled) / float(rounds))])
	_check(toppled > 0, "orbiting defenders never wall the stack off from bot attackers")
	_check(toppled < rounds, "orbiting defenders stop some bot attackers")


func _test_attacker_rebuild_and_avoidance() -> void:
	_build(0.5)
	_manager.phase = RoundManager.SCATTER
	var attacker: Character = _spawn(0, Character.Role.ATTACKER, _arena.centre_spot + Vector2(-200.0, -100.0))
	var loose: Sandal = _spawn_sandal(attacker.position + Vector2(30.0, 0.0))
	await _frames(2)
	await _drive(_bots[attacker], 20)
	_check(attacker.carried == loose, "attacker picks up a nearby loose sandal")
	var start: float = attacker.global_position.distance_to(_arena.centre_spot)
	await _drive(_bots[attacker], 120)
	_check(attacker.global_position.distance_to(_arena.centre_spot) < start - 60.0, "carrier walks toward the centre spot")
	_build(0.5)
	_manager.phase = RoundManager.SCATTER
	var runner: Character = _spawn(0, Character.Role.ATTACKER, _arena.centre_spot + Vector2(-300.0, 0.0))
	var holder: Character = _spawn(1, Character.Role.DEFENDER, _arena.centre_spot + Vector2(500.0, 250.0))
	holder.pick_up(_spawn_sandal(holder.position, true))
	await _frames(2)
	_bots[runner]._physics_process(STEP)
	var free_x: float = runner.move_intent.x
	holder.global_position = runner.global_position + Vector2(60.0, 0.0)
	_bots[runner]._physics_process(STEP)
	_check(free_x > 0.5, "baseline: runner heads to the centre spot")
	_check(runner.move_intent.x < free_x - 0.5, "attacker steers away from a nearby pass holder")


func _launch_pass_at(target: Vector2, from: Vector2) -> Sandal:
	var pass_sandal: Sandal = _spawn_sandal(from, true)
	pass_sandal.launch((target - from).normalized(), 0.75)
	return pass_sandal


func _test_attacker_dodge() -> void:
	_build(1.0)
	_manager.phase = RoundManager.SCATTER
	var attacker: Character = _spawn(0, Character.Role.ATTACKER, _arena.centre_spot + Vector2(-200.0, 0.0))
	_bots[attacker].dodge_chance = 1.0
	await _frames(2)
	_launch_pass_at(attacker.position, attacker.position + Vector2(300.0, 0.0))
	_bots[attacker]._physics_process(STEP)
	_check(attacker.is_invulnerable(), "attacker dashes from an incoming pass sandal")
	_check(absf(attacker.move_intent.y) > 0.5, "dodge moves sideways to the sandal path")
	_build(0.0)
	_manager.phase = RoundManager.SCATTER
	var calm: Character = _spawn(0, Character.Role.ATTACKER, _arena.centre_spot + Vector2(-200.0, 0.0))
	_bots[calm].dodge_chance = 0.0
	await _frames(2)
	_launch_pass_at(calm.position, calm.position + Vector2(300.0, 0.0))
	_bots[calm]._physics_process(STEP)
	_check(not calm.is_invulnerable(), "a zero dodge chance never dashes")
	_build(1.0)
	_manager.phase = RoundManager.SCATTER
	var safe: Character = _spawn(0, Character.Role.ATTACKER, _arena.centre_spot + Vector2(-200.0, 200.0))
	_bots[safe].dodge_chance = 1.0
	await _frames(2)
	_launch_pass_at(_arena.centre_spot + Vector2(-200.0, 0.0), _arena.centre_spot + Vector2(100.0, 0.0))
	_bots[safe]._physics_process(STEP)
	_check(not safe.is_invulnerable(), "no dash when the sandal path misses")


func _setup_holder_scene(difficulty: float) -> Dictionary:
	_build(difficulty)
	_manager.phase = RoundManager.SCATTER
	var holder: Character = _spawn(1, Character.Role.DEFENDER, _arena.centre_spot + Vector2(250.0, 0.0))
	var mate_a: Character = _spawn(1, Character.Role.DEFENDER, _arena.centre_spot + Vector2(250.0, -200.0))
	var mate_b: Character = _spawn(1, Character.Role.DEFENDER, _arena.centre_spot + Vector2(250.0, 200.0))
	var attacker: Character = _spawn(0, Character.Role.ATTACKER, _arena.centre_spot + Vector2(-200.0, 0.0))
	holder.pick_up(_spawn_sandal(holder.position, true))
	return {"holder": holder, "mate_a": mate_a, "mate_b": mate_b, "attacker": attacker}


func _test_holder_pass_and_shot() -> void:
	var scene: Dictionary = _setup_holder_scene(1.0)
	var holder: Character = scene["holder"]
	var passes: Array[Character] = []
	holder.passed.connect(func(receiver: Character) -> void: passes.append(receiver))
	(scene["attacker"] as Character).global_position = _arena.centre_spot + Vector2(-480.0, 280.0)
	var bot: BotController = _bots[holder]
	bot.shot_chance = 0.0
	await _frames(2)
	await _drive(bot, 1)
	bot._hold_timer = 5.0
	await _drive(bot, 30)
	_check(passes.size() >= 1, "holder passes to an open teammate")
	_check(not passes.is_empty() and passes[0] != holder, "holder never passes to itself")
	scene = _setup_holder_scene(1.0)
	var shooter: Character = scene["holder"]
	var shots: Array[Sandal] = []
	var launch_velocities: Array[Vector2] = []
	shooter.threw.connect(func(sandal: Sandal) -> void:
		shots.append(sandal)
		launch_velocities.append(sandal.linear_velocity))
	var target: Character = scene["attacker"]
	target.global_position = shooter.global_position + Vector2(-300.0, 0.0)
	(scene["mate_a"] as Character).global_position = _arena.centre_spot + Vector2(300.0, -280.0)
	(scene["mate_b"] as Character).global_position = _arena.centre_spot + Vector2(300.0, 280.0)
	var shooter_bot: BotController = _bots[shooter]
	shooter_bot.shot_chance = 1.0
	shooter_bot.aim_error = 0.0
	await _frames(2)
	await _drive(shooter_bot, 1)
	shooter_bot._hold_timer = 5.0
	await _drive(shooter_bot, 30)
	_check(shots.size() == 1, "holder throws at an attacker in a clear lane")
	if shots.size() == 1:
		# The sandal bounces later, so only the launch velocity shows the aim.
		_check(launch_velocities[0].x < 0.0, "shot flies toward the attacker")
	scene = _setup_holder_scene(1.0)
	var blocked: Character = scene["holder"]
	var blocked_shots: Array[Sandal] = []
	blocked.threw.connect(func(sandal: Sandal) -> void: blocked_shots.append(sandal))
	(scene["attacker"] as Character).global_position = blocked.global_position + Vector2(-300.0, 0.0)
	(scene["mate_a"] as Character).global_position = blocked.global_position + Vector2(-150.0, 0.0)
	(scene["mate_b"] as Character).global_position = _arena.centre_spot + Vector2(300.0, 280.0)
	var blocked_bot: BotController = _bots[blocked]
	blocked_bot.shot_chance = 1.0
	await _frames(2)
	await _drive(blocked_bot, 1)
	blocked_bot._hold_timer = 5.0
	await _drive(blocked_bot, 4)
	_check(blocked_shots.is_empty(), "holder does not throw through a teammate")


func _test_support_and_loose_sandals() -> void:
	var scene: Dictionary = _setup_holder_scene(0.5)
	var mate_a: Character = scene["mate_a"]
	var mate_b: Character = scene["mate_b"]
	(scene["attacker"] as Character).global_position = _arena.centre_spot + Vector2(-480.0, 280.0)
	await _frames(2)
	for _i: int in 120:
		_bots[mate_a]._physics_process(STEP)
		_bots[mate_b]._physics_process(STEP)
		await physics_frame
	var holder: Character = scene["holder"]
	_check(mate_a.global_position.distance_to(holder.global_position) > 60.0, "support defender does not crowd the holder")
	_check(mate_b.global_position.distance_to(holder.global_position) > 60.0, "second support defender does not crowd the holder")
	_build(0.5)
	_manager.phase = RoundManager.SCATTER
	var guard: Character = _spawn(1, Character.Role.DEFENDER, _arena.centre_spot + Vector2(150.0, 100.0))
	var holder_two: Character = _spawn(1, Character.Role.DEFENDER, _arena.centre_spot + Vector2(300.0, 200.0))
	holder_two.pick_up(_spawn_sandal(holder_two.position, true))
	var loose: Sandal = _spawn_sandal(_arena.centre_spot + Vector2(80.0, 0.0))
	await _frames(3)
	var before: float = guard.global_position.distance_to(loose.global_position)
	await _drive(_bots[guard], 20)
	_check(guard.global_position.distance_to(loose.global_position) < before, "a defender runs toward a loose sandal near the stack")
	_build(0.5)
	_manager.phase = RoundManager.SCATTER
	var nearest: Character = _spawn(1, Character.Role.DEFENDER, _arena.centre_spot + Vector2(300.0, -200.0))
	var dropped: Sandal = _spawn_sandal(nearest.position + Vector2(20.0, 0.0), true)
	await _frames(3)
	await _drive(_bots[nearest], 30)
	_check(nearest.carried == dropped, "the closest defender picks up a loose pass sandal")


func _test_dead_bot_and_write_boundary() -> void:
	_build(0.5)
	_manager.phase = RoundManager.TOPPLE
	var dead: Character = _spawn(1, Character.Role.DEFENDER, _arena.centre_spot + Vector2(200.0, 0.0))
	var neighbour: Character = _spawn(1, Character.Role.DEFENDER, _arena.centre_spot + Vector2(0.0, 200.0))
	await _frames(2)
	dead.die()
	neighbour.move_intent = Vector2(0.0, 0.123)
	_bots[dead]._physics_process(STEP)
	_check(dead.move_intent == Vector2.ZERO, "a dead bot stops moving")
	_check(neighbour.move_intent == Vector2(0.0, 0.123), "a bot never writes another character")
	_manager.phase = RoundManager.ROUND_END
	_bots[neighbour]._physics_process(STEP)
	_check(neighbour.move_intent == Vector2.ZERO, "bots idle outside topple and scatter")


func _test_full_match() -> void:
	_clear_stage()
	var tuning: Tuning = Tuning.load_default().duplicate() as Tuning
	tuning.match_countdown = false
	tuning.human_team = -1
	seed(20261107)
	var arena: Arena = (load(ARENA_SCENE) as PackedScene).instantiate() as Arena
	arena.tuning = tuning
	_stage.add_child(arena)
	var manager: RoundManager = RoundManager.new()
	manager.tuning = tuning
	manager.arena = arena
	_stage.add_child(manager)
	var probe: MatchProbe = MatchProbe.new()
	probe.manager = manager
	probe.arena = arena
	_stage.add_child(probe)
	while not probe.done() and probe.sim_time < MAX_MATCH_SECONDS:
		await physics_frame
	for team: int in 2:
		_check(probe.role_time[team] >= SECONDS_PER_ROLE, "team %d attacked for %.0f simulated seconds (got %.1f)" % [team, SECONDS_PER_ROLE, probe.role_time[team]])
		_check(probe.topple_throws[team] >= 1, "team %d threw at least once in the topple phase (got %d)" % [team, probe.topple_throws[team]])
	_check(probe.scatter_rounds >= 1, "a scatter phase happened (got %d)" % probe.scatter_rounds)
	_check(probe.approaching_attackers >= 1, "a scatter attacker moved toward the stack or a sandal (got %d of %d)" % [probe.approaching_attackers, probe.tracked_attackers])
	_check(probe.human_frames == 0, "no human seat exists, so bots drive every character")
	Engine.time_scale = 1.0
	print("  match: %.0f s simulated, rounds %d, scatter phases %d, throws %s, attackers approaching %d of %d" % [probe.sim_time, probe.rounds_seen, probe.scatter_rounds, str(probe.topple_throws), probe.approaching_attackers, probe.tracked_attackers])
	_clear_stage()
	await _frames(2)


class MatchProbe:
	extends Node
	## Counts what the bots do during a full match.

	var manager: RoundManager
	var arena: Arena
	var sim_time: float = 0.0
	var role_time: Array[float] = [0.0, 0.0]
	var topple_throws: Array[int] = [0, 0]
	var scatter_rounds: int = 0
	var rounds_seen: int = 0
	var tracked_attackers: int = 0
	var approaching_attackers: int = 0
	var human_frames: int = 0

	var _last_phase: int = -1
	var _connected: Dictionary = {}
	var _scatter_start: Dictionary = {}
	var _scatter_best: Dictionary = {}

	func done() -> bool:
		return role_time[0] >= 20.0 and role_time[1] >= 20.0 and scatter_rounds >= 1

	func _physics_process(delta: float) -> void:
		if manager.human != null and manager.human.character != null:
			human_frames += 1
		if manager.phase == RoundManager.MATCH_END:
			manager.start_match()
			return
		sim_time += delta
		if manager.phase == RoundManager.TOPPLE or manager.phase == RoundManager.SCATTER:
			role_time[manager.attacking_team] += delta
		if manager.phase != _last_phase:
			if manager.phase == RoundManager.COIN_FLIP or manager.phase == RoundManager.TOPPLE and _last_phase == RoundManager.ROUND_END:
				rounds_seen += 1
			if manager.phase == RoundManager.SCATTER:
				scatter_rounds += 1
				_scatter_start.clear()
				_scatter_best.clear()
			if _last_phase == RoundManager.SCATTER:
				_finish_scatter()
			_last_phase = manager.phase
		for team: int in 2:
			for entry: Variant in arena.get_characters(team):
				var character: Character = entry as Character
				if character != null and not _connected.has(character.get_instance_id()):
					_connected[character.get_instance_id()] = true
					character.threw.connect(_on_threw.bind(character))
		if manager.phase == RoundManager.SCATTER:
			_track_scatter()

	func _on_threw(_sandal: Sandal, character: Character) -> void:
		if manager.phase == RoundManager.TOPPLE and character.role == Character.Role.ATTACKER:
			topple_throws[character.team] += 1

	func _target_distance(character: Character) -> float:
		var best: float = character.global_position.distance_to(arena.centre_spot)
		if character.carried == null:
			for entry: Variant in arena.get_loose_sandals():
				var sandal: Sandal = entry as Sandal
				if sandal != null and not sandal.is_pass_sandal:
					best = minf(best, character.global_position.distance_to(sandal.global_position))
		return best

	func _track_scatter() -> void:
		for entry: Variant in arena.get_characters(manager.attacking_team):
			var attacker: Character = entry as Character
			if attacker == null or not attacker.alive:
				continue
			var id: int = attacker.get_instance_id()
			var distance: float = _target_distance(attacker)
			if not _scatter_start.has(id):
				_scatter_start[id] = distance
				_scatter_best[id] = distance
			_scatter_best[id] = minf(_scatter_best[id], distance)

	func _finish_scatter() -> void:
		for id: Variant in _scatter_start:
			tracked_attackers += 1
			if _scatter_start[id] - _scatter_best[id] >= 40.0:
				approaching_attackers += 1
