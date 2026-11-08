extends SceneTree
## Headless test of the world: stack topple, group, layers, loose sandals, round flow.
##
## Run: godot --headless --path game --script res://tests/world_test.gd

## Physics frames a whole round may take, 150 seconds at 60 frames per second.
const ROUND_FRAME_LIMIT: int = 9000
## Seed of the global random generator and of the bots in the full round.
const ROUND_SEED: int = 20261107
## Frames between two human moves.
const PLAY_STEP_FRAMES: int = 30

var _failures: int = 0
var _toppled: bool = false


func _initialize() -> void:
	await _run()
	print("world_test: %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
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
	var tuning: Tuning = Tuning.load_default()
	tuning.match_countdown = false
	var arena: Arena = (load("res://scenes/arena.tscn") as PackedScene).instantiate() as Arena
	root.add_child(arena)
	await _frames(3)
	var stack: Stack = arena.stack
	stack.toppled.connect(func() -> void: _toppled = true)

	_check(stack.standing_sandals.size() == tuning.stack_size, "stack builds %d sandals" % tuning.stack_size)
	_check(not stack.is_down, "stack stands at start")
	_check(get_nodes_in_group(Sandal.GROUP).size() == tuning.stack_size, "every sandal joins group sandals")
	_check(arena.get_loose_sandals().is_empty(), "standing sandals are not loose")
	for node: Node in get_nodes_in_group(Sandal.GROUP):
		_check((node as Sandal).collision_layer == 4, "sandal uses collision layer 4")
		break

	var thrower: Sandal = Sandal.new()
	thrower.position = arena.centre_spot + Vector2(-260.0, 0.0)
	arena.add_child(thrower)
	await _frames(2)
	thrower.launch(Vector2.RIGHT, 1.0)
	_check(thrower.in_flight, "launch sets in_flight")
	await _frames(90)
	_check(_toppled, "toppled fires when a sandal hits the stack")
	_check(stack.is_down, "is_down is true after the topple")
	_check(stack.placed_count == 0, "placed_count resets to 0")

	var loose: int = arena.get_loose_sandals().size()
	_check(loose >= 1, "toppled sandals count as loose (%d)" % loose)

	_check(stack.can_build() == (stack.zone_sandals().size() == stack.tuning.stack_size), "a build is allowed exactly when all sandals lie in the zone")
	var rebuilt: Array[bool] = [false]
	stack.rebuilt.connect(func() -> void: rebuilt[0] = true)
	await _test_stack_build(arena, stack, tuning, rebuilt)

	var miss: Sandal = Sandal.new()
	miss.position = arena.centre_spot + Vector2(0.0, 250.0)
	arena.add_child(miss)
	await _frames(2)
	miss.launch(Vector2.DOWN, 1.0)
	await _frames(200)
	var inside: bool = absf(miss.position.y - arena.centre_spot.y) < tuning.arena_half_extents.y
	_check(inside, "walls keep a sandal inside the arena")
	_check(not miss.in_flight, "damping ends the flight")

	_test_clean_lane(tuning)
	await _test_ranged_throw(tuning)
	await _test_rings_in_round()
	await _round_flow()


## Moves every free sandal into the zone by hand, then places them one by one.
func _test_stack_build(arena: Arena, stack: Stack, tuning: Tuning, rebuilt: Array[bool]) -> void:
	var free: Array[Sandal] = []
	for node: Node in get_nodes_in_group(Sandal.GROUP):
		if node.get_parent() == stack and not (node as Sandal).is_placed:
			free.append(node as Sandal)
	_check(free.size() == tuning.stack_size, "all %d pyramid sandals are free after the topple" % tuning.stack_size)
	for index: int in free.size():
		free[index].halt()
		free[index].global_position = arena.centre_spot + Vector2.from_angle(float(index) * 2.0) * 40.0
	free[0].global_position = arena.centre_spot + Vector2(tuning.build_zone_radius + 60.0, 0.0)
	await _frames(2)
	_check(not stack.can_build(), "no build with fewer than three sandals in the zone")
	free[0].global_position = arena.centre_spot + Vector2(0.0, 50.0)
	await _frames(2)
	_check(stack.can_build(), "build is possible with all three sandals in the zone")
	var body: Character = (load("res://scenes/character.tscn") as PackedScene).instantiate() as Character
	body.configure(0, Character.Role.ATTACKER, tuning)
	body.arena = arena
	body.stack = stack
	body.position = arena.centre_spot
	arena.add_child(body)
	await _frames(2)
	_check(body.start_building(), "attacker in the zone starts a build")
	for step: int in tuning.stack_size:
		_check(body.complete_build_step(), "build step %d places a sandal" % step)
		await _frames(1)
	_check(stack.slot_positions.size() == tuning.stack_size, "stack has one slot per sandal")
	for slot: int in tuning.stack_size:
		var sandal: Sandal = stack.standing_sandals[slot]
		var foot: Vector2 = stack.slot_positions[slot]
		_check(is_equal_approx(foot.length(), tuning.pyramid_base_radius), "slot %d lies on the base ring" % slot)
		_check(sandal.stack_slot == slot and sandal.is_placed, "sandal %d knows its slot" % slot)
		_check(sandal.lean_direction.distance_to(-foot.normalized()) < 0.001, "sandal %d leans toward the centre" % slot)
		_check(is_equal_approx(sandal.lean_angle, deg_to_rad(tuning.pyramid_lean_degrees)), "sandal %d uses the tuned lean angle" % slot)
		var next: Vector2 = stack.slot_positions[(slot + 1) % tuning.stack_size]
		_check(absf(foot.angle_to(next) - TAU / 3.0) < 0.001 or absf(foot.angle_to(next) + TAU / 3.0) < 0.001, "slot %d is 120 degrees from the next" % slot)
	_check(stack.is_built and stack.placed_count == tuning.stack_size, "pyramid is built after three steps")
	await _frames(int((tuning.build_stable_seconds + 0.3) * 60.0))
	_check(rebuilt[0], "rebuilt fires after the pyramid stood stable")
	body.queue_free()


## Balance check. A lane is clean when no defender body touches the straight line from an
## attacker on the throw ring to the stack centre. A throw lane is as wide as a defender plus a sandal.
func _test_clean_lane(tuning: Tuning) -> void:
	var steps: int = 360
	var hit_distance: float = tuning.character_radius + tuning.sandal_radius
	var period: float = TAU / tuning.orbit_speed
	var spacing: float = deg_to_rad(tuning.throw_ring_spacing_degrees)
	var clean: int = 0
	var total: int = 0
	var longest_gap: float = 0.0
	var gap: float = 0.0
	var dt: float = period / float(steps)
	for step: int in steps:
		var time: float = period * float(step) / float(steps)
		var step_clean: bool = true
		for slot: int in [-1, 0, 1]:
			var attacker: Vector2 = Vector2.from_angle(PI + float(slot) * spacing) * tuning.throw_radius
			var lane_clean: bool = true
			for index: int in tuning.team_size:
				var angle: float = tuning.orbit_speed * time + PI * 0.5 + TAU * float(index) / float(tuning.team_size)
				var defender: Vector2 = Vector2.from_angle(angle) * tuning.orbit_radius
				var closest: Vector2 = Geometry2D.get_closest_point_to_segment(defender, attacker, Vector2.ZERO)
				if closest.distance_to(defender) < hit_distance:
					lane_clean = false
			total += 1
			if lane_clean:
				clean += 1
			if slot == 0 and not lane_clean:
				step_clean = false
		gap = gap + dt if step_clean else 0.0
		longest_gap = maxf(longest_gap, gap)
	var ratio: float = float(clean) / float(total)
	print("  clean lane ratio %.3f, longest gap of the middle attacker %.2f s (needs %.2f)" % [ratio, longest_gap, tuning.min_clean_lane_ratio])
	_check(ratio >= tuning.min_clean_lane_ratio, "orbit leaves a clean lane for at least %d percent of the time" % int(tuning.min_clean_lane_ratio * 100.0))
	var width: float = 2.0 * asin(minf(tuning.character_radius / tuning.orbit_radius, 1.0))
	var cluster_share: float = width * float(tuning.team_size) / TAU
	_check(cluster_share < 0.4, "three defenders cover under 40 percent of the ring (%.1f percent)" % (cluster_share * 100.0))
	_check(tuning.orbit_radius < tuning.throw_radius, "orbit ring is inside the throw ring")


func _test_ranged_throw(tuning: Tuning) -> void:
	for child: Node in root.get_children():
		if child is Arena:
			child.queue_free()
	await _frames(2)
	var arena: Arena = (load("res://scenes/arena.tscn") as PackedScene).instantiate() as Arena
	root.add_child(arena)
	await _frames(2)
	var ok: bool = true
	var worst: float = 0.0
	for angle_degrees: int in [0, 90, 200]:
		var direction: Vector2 = Vector2.from_angle(deg_to_rad(float(angle_degrees)))
		var start: Vector2 = arena.centre_spot + direction * 110.0
		var sandal: Sandal = Sandal.new()
		sandal.position = start
		arena.add_child(sandal)
		await _frames(2)
		sandal.launch_ranged(direction, 150.0)
		await _frames(120)
		var travelled: float = sandal.global_position.distance_to(start)
		worst = maxf(worst, absf(travelled - 150.0))
		ok = ok and not sandal.in_flight
		sandal.queue_free()
	_check(worst < 6.0, "ranged throw lands at its fixed distance (worst error %.2f px)" % worst)
	_check(ok, "ranged throw ends its flight")
	arena.queue_free()
	await _frames(2)


func _test_rings_in_round() -> void:
	var tuning: Tuning = Tuning.load_default()
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _frames(5)
	var manager: RoundManager = main.get_node("RoundManager") as RoundManager
	var arena: Arena = main.get_node("Arena") as Arena
	await _frames(int(tuning.coin_flip_time * 60.0) + 10)
	_check(manager.phase == RoundManager.TOPPLE, "round reaches the topple phase for the ring checks")
	var attacker_error: float = 0.0
	var defender_error: float = 0.0
	var inside_throw_ring: bool = false
	for _i: int in 90:
		await _frames(2)
		if manager.phase != RoundManager.TOPPLE:
			break
		for team: int in 2:
			for entry: Variant in arena.get_characters(team):
				var character: Character = entry as Character
				var distance: float = character.global_position.distance_to(arena.centre_spot)
				if character.role == Character.Role.ATTACKER:
					attacker_error = maxf(attacker_error, absf(distance - tuning.throw_radius))
					inside_throw_ring = inside_throw_ring or distance < tuning.throw_radius - 1.0
				else:
					defender_error = maxf(defender_error, absf(distance - tuning.orbit_radius))
	_check(not inside_throw_ring, "no attacker ever stands inside the throw ring")
	_check(attacker_error < 1.0, "attackers stay on the throw ring (worst error %.2f px)" % attacker_error)
	_check(defender_error < 2.0, "defenders stay on the orbit ring during the topple phase (worst error %.2f px)" % defender_error)
	var human: Character = manager.human.character
	if human != null and human.role == Character.Role.DEFENDER:
		var start_ring: float = human.global_position.distance_to(arena.centre_spot)
		human.move_intent = Vector2(0.0, -1.0)
		var worst_drift: float = 0.0
		for _i: int in 30:
			await _frames(2)
			if manager.phase != RoundManager.TOPPLE:
				break
			worst_drift = maxf(worst_drift, absf(human.global_position.distance_to(arena.centre_spot) - start_ring))
		_check(worst_drift < 2.0, "human defender cannot leave the ring (worst drift %.2f)" % worst_drift)
		human.move_intent = Vector2.ZERO
	elif human != null:
		human.move_intent = Vector2(1.0, 0.0)
		await _frames(60)
		_check(absf(human.global_position.distance_to(arena.centre_spot) - tuning.throw_radius) < 1.0, "human attacker cannot leave the throw ring")
		human.move_intent = Vector2.ZERO
	main.queue_free()
	await _frames(2)


func _round_flow() -> void:
	for child: Node in root.get_children():
		if child is Arena:
			child.queue_free()
	await _frames(2)
	seed(ROUND_SEED)
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _frames(5)
	var manager: RoundManager = main.get_node("RoundManager") as RoundManager
	_seed_bots(manager)
	_check(manager.phase == RoundManager.COIN_FLIP, "match starts at the coin flip")
	await _frames(int(Tuning.load_default().coin_flip_time * 60.0) + 10)
	_check(manager.phase == RoundManager.TOPPLE, "coin flip moves to topple")
	_check(manager.throws_left == Tuning.load_default().team_size * Tuning.load_default().throws_per_attacker, "throws_left is team size times throws")
	var arena: Arena = main.get_node("Arena") as Arena
	_check(arena.get_characters(0).size() == Tuning.load_default().team_size, "team 0 has a full team")
	_check(arena.get_characters(1).size() == Tuning.load_default().team_size, "team 1 has a full team")
	var first_attacking: int = manager.attacking_team
	var ended: Array[bool] = [false]
	manager.round_ended.connect(func(_winner: int) -> void: ended[0] = true)
	# The game clock counts physics frames, so waiting on frames and signals never depends on machine speed.
	var frames: int = 0
	while not ended[0] and frames < ROUND_FRAME_LIMIT:
		_play_for_human(manager, arena)
		await _frames(PLAY_STEP_FRAMES)
		frames += PLAY_STEP_FRAMES
	var round_label: String = "round ends in %d frames" % frames
	if not ended[0]:
		round_label = "round ends (stuck in %s after %d frames, scores %s, throws left %d)" % [_phase_name(manager.phase), frames, manager.scores, manager.throws_left]
	_check(ended[0], round_label)
	_check(manager.scores[0] + manager.scores[1] == 1, "exactly one point is scored")
	await _frames(int(Tuning.load_default().round_end_delay * 60.0) + 20)
	_check(manager.attacking_team == 1 - first_attacking or manager.phase == RoundManager.MATCH_END, "roles swap after a round")
	main.queue_free()


## Seeds every bot, so the aim error and the dodge rolls repeat on every run.
func _seed_bots(manager: RoundManager) -> void:
	var index: int = 0
	for bot: Variant in manager._bots.values():
		(bot as BotController).seed_rng(ROUND_SEED + index)
		index += 1


func _phase_name(phase: int) -> String:
	match phase:
		RoundManager.COIN_FLIP:
			return "COIN_FLIP"
		RoundManager.TOPPLE:
			return "TOPPLE"
		RoundManager.SCATTER:
			return "SCATTER"
		RoundManager.ROUND_END:
			return "ROUND_END"
	return "MATCH_END"


## Plays the human seat the same way every run: an attacker throws at the stack and then rebuilds it,
## a defender passes the sandal. A human who idled would leave the round to bot dice.
func _play_for_human(manager: RoundManager, arena: Arena) -> void:
	var body: Character = manager.human.character
	if body == null or not body.alive:
		return
	body.move_intent = Vector2.ZERO
	if manager.phase == RoundManager.TOPPLE and body.role == Character.Role.ATTACKER and body.carried != null:
		body.throw_sandal((arena.centre_spot - body.global_position).normalized(), 1.0)
	elif manager.phase == RoundManager.SCATTER and body.role == Character.Role.ATTACKER:
		_rebuild_as_human(body, arena)
	elif manager.phase == RoundManager.SCATTER and body.role == Character.Role.DEFENDER and body.carried != null:
		for entry: Variant in arena.get_characters(body.team):
			var mate: Character = entry as Character
			if mate != body and mate.alive:
				body.pass_to(mate)
				return


## Walks every loose sandal into the zone, then builds. The human here answers the prompts at once,
## so the check covers the round flow and not the QTE timing.
func _rebuild_as_human(body: Character, arena: Arena) -> void:
	var stack: Stack = arena.stack
	if body.carried == null and stack.can_build():
		var to_centre: Vector2 = arena.centre_spot - body.global_position
		if to_centre.length() > 20.0 and not body.is_building():
			body.move_intent = to_centre.normalized()
			return
		if not body.is_building():
			body.start_building()
		else:
			body.complete_build_step()
		return
	var goal: Vector2 = arena.centre_spot
	if body.carried == null:
		var nearest: Sandal = null
		var best: float = INF
		for node: Node in arena.get_loose_sandals():
			var sandal: Sandal = node as Sandal
			if stack.is_in_zone(sandal.global_position):
				continue
			var distance: float = sandal.global_position.distance_to(body.global_position)
			if distance < best:
				best = distance
				nearest = sandal
		if nearest == null:
			return
		goal = nearest.global_position
	body.move_intent = (goal - body.global_position).normalized()
