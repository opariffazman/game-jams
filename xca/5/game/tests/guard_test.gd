extends SceneTree
## Headless test of the guard block: one absorbed hit, a stun, a cooldown, the builder never covered,
## and softer sandal impacts.
##
## Run: godot --headless --path game --script res://tests/guard_test.gd

const ARENA_SCENE: String = "res://scenes/arena.tscn"
const CHARACTER_SCENE: String = "res://scenes/character.tscn"

var _failures: int = 0
var _stage: Node2D
var _arena: Arena
var _tuning: Tuning
var _manager: RoundManager


func _initialize() -> void:
	await _run()
	print("guard_test: %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
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
	await _test_block_rules()
	await _test_builder_not_covered()
	await _test_soft_impacts()
	await _test_ricochet_matrix()


func _build_stage() -> void:
	await _build_stage_now()


func _build_stage_now() -> void:
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
	_manager = RoundManager.new()
	_manager.tuning = _tuning
	_manager.arena = _arena
	_manager.attacking_team = 0
	_stage.add_child(_manager)
	_manager.set_physics_process(false)
	await physics_frame
	await physics_frame
	_manager.phase = RoundManager.SCATTER


func _spawn(team: int, role: Character.Role, at: Vector2) -> Character:
	var character: Character = (load(CHARACTER_SCENE) as PackedScene).instantiate() as Character
	character.configure(team, role, _tuning)
	character.arena = _arena
	character.stack = _arena.stack
	character.position = at
	_arena.add_child(character)
	return character


func _hit(character: Character, sandal: Sandal) -> void:
	_manager.phase = RoundManager.SCATTER
	_manager._on_pass_hit(character, sandal)


func _guard_spot() -> Vector2:
	return _arena.centre_spot + Vector2(_tuning.build_zone_radius + _tuning.guard_ring_width * 0.5, 0.0)


func _pass_sandal_at(character: Character) -> Sandal:
	var sandal: Sandal = Sandal.new()
	sandal.tuning = _tuning
	sandal.is_pass_sandal = true
	sandal.position = character.position
	_arena.add_child(sandal)
	return sandal


func _test_block_rules() -> void:
	await _build_stage()
	await _frames(2)
	_arena.stack._topple()
	var guard: Character = _spawn(0, Character.Role.ATTACKER, _guard_spot())
	await _frames(2)
	var incoming: Sandal = _pass_sandal_at(guard)
	_hit(guard, incoming)
	_check(guard.alive, "a guard in the ring absorbs the first hit")
	_check(guard.guard_stun_left > 0.0 and is_equal_approx(guard.guard_stun_left, _tuning.guard_stun_seconds), "the block stuns for guard_stun_seconds")
	_check(not incoming.in_flight and incoming.linear_velocity == Vector2.ZERO, "the blocked sandal stops")
	_hit(guard, incoming)
	_check(not guard.alive, "a second hit during the cooldown kills")

	var second: Character = _spawn(0, Character.Role.ATTACKER, _guard_spot())
	await _frames(2)
	_hit(second, incoming)
	await _frames(int((_tuning.guard_stun_seconds + 0.1) * 60.0))
	_check(second.guard_stun_left <= 0.0, "the stun ends")
	_check(second.guard_cooldown_left > 0.0, "the cooldown outlasts the stun")
	_hit(second, incoming)
	_check(not second.alive, "a hit after the stun but inside the cooldown kills")

	var third: Character = _spawn(0, Character.Role.ATTACKER, _guard_spot())
	await _frames(2)
	_hit(third, incoming)
	await _frames(int((_tuning.guard_block_cooldown + 0.2) * 60.0))
	_check(third.can_block(), "the guard can block again after guard_block_cooldown")
	_hit(third, incoming)
	_check(third.alive, "the second block works after the cooldown")

	var outside: Character = _spawn(0, Character.Role.ATTACKER, _arena.centre_spot + Vector2(_tuning.build_zone_radius + _tuning.guard_ring_width + 60.0, 0.0))
	await _frames(2)
	_hit(outside, incoming)
	_check(not outside.alive, "an attacker outside the guard ring is not covered")


func _test_builder_not_covered() -> void:
	await _build_stage()
	await _frames(2)
	_arena.stack._topple()
	var free: Array[Sandal] = []
	for node: Node in get_nodes_in_group(Sandal.GROUP):
		if node.get_parent() == _arena.stack:
			free.append(node as Sandal)
	for index: int in free.size():
		free[index].halt()
		free[index].global_position = _arena.centre_spot + Vector2.from_angle(float(index) * 2.0) * 40.0
	var builder: Character = _spawn(0, Character.Role.ATTACKER, _arena.centre_spot)
	var carrier: Character = _spawn(0, Character.Role.ATTACKER, _guard_spot())
	await _frames(2)
	_check(builder.start_building(), "the builder starts")
	_check(not builder.can_block(), "the builder cannot block")
	var incoming: Sandal = _pass_sandal_at(builder)
	_hit(builder, incoming)
	_check(not builder.alive, "a hit on the builder kills")
	_check(_arena.stack.builder == null, "the hit cancels the build")
	var loose: Sandal = Sandal.new()
	loose.tuning = _tuning
	loose.position = carrier.position
	_arena.add_child(loose)
	await _frames(2)
	carrier.pick_up(loose)
	_check(not carrier.can_block(), "a carrier cannot block")
	_hit(carrier, incoming)
	_check(not carrier.alive, "a hit on a carrier kills")


func _test_soft_impacts() -> void:
	await _build_stage()
	await _frames(2)
	var resting: Sandal = Sandal.new()
	resting.tuning = _tuning
	resting.position = _arena.centre_spot + Vector2(0.0, 150.0)
	_arena.add_child(resting)
	var thrower: Sandal = Sandal.new()
	thrower.tuning = _tuning
	thrower.position = resting.position + Vector2(-120.0, 0.0)
	_arena.add_child(thrower)
	await _frames(3)
	var start: Vector2 = resting.global_position
	thrower.launch(Vector2.RIGHT, 1.0)
	var peak: float = 0.0
	for _i: int in 120:
		await physics_frame
		peak = maxf(peak, resting.linear_velocity.length())
	_check(peak <= _tuning.rest_hit_speed_cap + 1.0, "a resting sandal never exceeds rest_hit_speed_cap (peak %.0f)" % peak)
	var moved: float = resting.global_position.distance_to(start)
	_check(moved > 5.0 and moved < 140.0, "a resting sandal nudges a short distance (%.0f px)" % moved)

	await _build_stage()
	await _frames(2)
	var stack: Stack = _arena.stack
	stack._topple()
	var free: Array[Sandal] = []
	for node: Node in get_nodes_in_group(Sandal.GROUP):
		if node.get_parent() == stack:
			free.append(node as Sandal)
	for index: int in free.size():
		free[index].halt()
		free[index].global_position = _arena.centre_spot + Vector2.from_angle(float(index) * 2.0) * 40.0
	var body: Character = _spawn(0, Character.Role.ATTACKER, _arena.centre_spot)
	await _frames(2)
	body.start_building()
	body.complete_build_step()
	var slow: Sandal = Sandal.new()
	slow.tuning = _tuning
	slow.position = stack.to_global(stack.slot_positions[0]) + Vector2(_tuning.sandal_radius, 0.0)
	slow.collision_mask = 0
	_arena.add_child(slow)
	await _frames(2)
	slow.linear_velocity = Vector2.RIGHT * (_tuning.knock_min_speed * 0.5)
	slow.in_flight = true
	slow.collision_mask = 0
	await _frames(2)
	_check(stack.placed_count == 1, "a slow flying sandal does not knock a placed sandal loose")
	slow.linear_velocity = Vector2.RIGHT * (_tuning.knock_min_speed * 1.5)
	slow.global_position = stack.to_global(stack.slot_positions[0]) + Vector2(_tuning.sandal_radius, 0.0)
	await _frames(1)
	_check(stack.placed_count == 0, "a hard flying sandal knocks the placed sandal loose")


func _fire_at_guard(angle: float, offset: float, guard_position: Vector2) -> Dictionary:
	var guard: Character = _spawn(0, Character.Role.ATTACKER, guard_position)
	await _frames(2)
	var direction: Vector2 = Vector2.from_angle(angle)
	var sideways: Vector2 = direction.orthogonal()
	var sandal: Sandal = Sandal.new()
	sandal.tuning = _tuning
	sandal.is_pass_sandal = true
	sandal.position = guard_position - direction * 160.0 + sideways * offset
	sandal.hit_character.connect(func(hit_guard: Character) -> void: _hit(hit_guard, sandal))
	_arena.add_child(sandal)
	await _frames(1)
	sandal.launch(direction, 1.0)
	var passed_through: bool = false
	var worst_dot: float = -1.0
	var blocked: bool = false
	for _i: int in 40:
		await physics_frame
		if sandal.ricochets > 0 and not blocked:
			blocked = true
			var away: Vector2 = sandal.global_position - guard.global_position
			worst_dot = -1.0 if sandal.linear_velocity.length() < 1.0 else -sandal.linear_velocity.normalized().dot(away.normalized())
		var rel: Vector2 = sandal.global_position - guard.global_position
		var behind: bool = rel.dot(direction) > 0.0 and absf(rel.dot(direction.orthogonal())) < guard.get_body_radius()
		var inside: bool = rel.length() < guard.get_body_radius() + _tuning.sandal_radius - 2.0
		if blocked and (behind or inside):
			passed_through = true
	var result: Dictionary = {"blocked": blocked, "passed": passed_through, "dot": worst_dot, "alive": guard.alive}
	guard.queue_free()
	sandal.queue_free()
	await _frames(2)
	return result


func _test_ricochet_matrix() -> void:
	var failures_before: int = _failures
	var shots: int = 0
	var pass_throughs: int = 0
	var unblocked: int = 0
	var toward: int = 0
	var dead: int = 0
	for rate: int in [60, 30]:
		Engine.physics_ticks_per_second = rate
		for angle_index: int in 5:
			for offset: float in [0.0, 10.0, -16.0, 24.0]:
				await _build_stage()
				await _frames(2)
				var spot: Vector2 = _guard_spot()
				var angle: float = PI + float(angle_index - 2) * 0.35
				var result: Dictionary = await _fire_at_guard(angle, offset, spot)
				shots += 1
				if not result["blocked"]:
					unblocked += 1
				if result["passed"]:
					pass_throughs += 1
				if result["dot"] > 0.0:
					toward += 1
				if not result["alive"]:
					dead += 1
	Engine.physics_ticks_per_second = 60
	_check(shots >= 40, "the matrix fired %d max-speed shots" % shots)
	_check(pass_throughs == 0, "no sandal passes through a guard (%d of %d)" % [pass_throughs, shots])
	_check(toward == 0, "every reflected velocity points away from the blocker (%d wrong)" % toward)
	_check(dead == 0, "a guard never dies from its first block (%d dead)" % dead)
	print("  info  shots %d, unblocked (clean misses) %d" % [shots, unblocked])

	await _build_stage()
	await _frames(2)
	var plain: Character = _spawn(0, Character.Role.ATTACKER, _arena.centre_spot + Vector2(300.0, 0.0))
	await _frames(2)
	var lethal: Sandal = Sandal.new()
	lethal.tuning = _tuning
	lethal.is_pass_sandal = true
	lethal.position = plain.position + Vector2(-160.0, 0.0)
	lethal.hit_character.connect(func(hit_body: Character) -> void: _hit(hit_body, lethal))
	_arena.add_child(lethal)
	await _frames(1)
	lethal.launch(Vector2.RIGHT, 1.0)
	await _frames(30)
	_check(not plain.alive, "an attacker outside the guard ring still dies at max speed")
	_check(not lethal.in_flight, "the sandal stops where it kills")
