class_name BotController
extends Controller
## Drives one [Character] as a bot for either role.
##
## Attackers throw the sandal the round manager hands them from the throw ring, then collect all three sandals,
## build the pyramid and dodge the pass sandal. Defenders ride the orbit ring in the topple phase, which the
## round manager sets up, then pass, hit with lead aim, and run through loose sandals near the
## stack. A bot only sets [member Character.move_intent] and calls the character's throw, pass,
## dash and pick-up methods.
##
## [b]Note:[/b] The round manager calls [method bind] and then [method Controller.attach]. The bot
## reads [member RoundManager.phase] every physics frame, so it needs no signal.

## Throw power sent to [method Character.throw_sandal], from 0 to 1.
const THROW_POWER: float = 1.0
## Distance at which a steering target counts as reached.
const ARRIVE_RADIUS: float = 8.0
## Distance from the pass holder where a defender looks for an open lane.
const LANE_RADIUS: float = 230.0
## Angle in radians between two neighbouring guard slots.
const GUARD_ARC_STEP: float = 0.9
## Distance under which an attacker avoids the pass holder.
const AVOID_RADIUS: float = 200.0
## Weight of the avoidance push against the main steering.
const AVOID_WEIGHT: float = 1.2
## Distance from a sandal path that counts as a hit threat.
const DANGER_RADIUS: float = 34.0
## Seconds ahead the dodge check looks along a sandal path.
const DODGE_LOOKAHEAD: float = 0.7
## Seconds a dodge direction overrides normal steering.
const DODGE_HOLD: float = 0.25
## Clear distance an attacker must keep from a pass lane for the lane to count as open.
const PASS_CLEAR_RADIUS: float = 45.0
## Seconds a holder waits for an open lane before it passes anyway.
const HOLD_LIMIT: float = 2.5
## Seconds between holder decisions.
const DECISION_INTERVAL: float = 0.25
## Seconds between lane replans.
const REPLAN_INTERVAL: float = 0.5
## Share of the throw range a defender trusts for a shot.
const RANGE_TRUST: float = 0.9
## Aim error in degrees at difficulty 0 and 1.
const AIM_ERROR_DEGREES: Vector2 = Vector2(18.0, 3.0)
## Reaction delay in seconds at difficulty 0 and 1.
const REACTION_DELAY: Vector2 = Vector2(0.8, 0.2)
## Dodge chance at difficulty 0 and 1.
const DODGE_CHANCE: Vector2 = Vector2(0.2, 0.8)
## Chance to take a clear shot instead of passing, at difficulty 0 and 1.
const SHOT_CHANCE: Vector2 = Vector2(0.3, 0.8)

## Distance of a foe that makes a hero bot use its power.
const POWER_TRIGGER_RADIUS: float = 150.0

## Arena the bot reads. Set by [method bind].
var arena: Arena
## Round manager the bot reads. Set by [method bind].
var round_manager: RoundManager
## Tuning resource the bot reads. Set by [method bind].
var tuning: Tuning
## Aim error in radians, derived from difficulty.
var aim_error: float = 0.0
## Reaction delay in seconds, derived from difficulty.
var reaction_delay: float = 0.5
## Chance to dodge a threatening sandal, derived from difficulty.
var dodge_chance: float = 0.5
## Chance to take a clear shot, derived from difficulty.
var shot_chance: float = 0.5

## Multiplier on [member Tuning.build_step_seconds] for this bot, derived from difficulty.
var build_skill_factor: float = 1.25

var _phase: int = -1
var _build_timer: float = 0.0
var _clock: float = 0.0
var _carry_time: float = 0.0
var _hold_timer: float = 0.0
var _next_decision: float = 0.0
var _dodge_timer: float = 0.0
var _dodge_direction: Vector2 = Vector2.ZERO
var _dodge_rolls: Dictionary = {}
var _lane_target: Vector2 = Vector2.ZERO
var _lane_timer: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = randi()
	if arena == null:
		arena = get_tree().get_first_node_in_group(Arena.GROUP) as Arena
	if round_manager == null:
		round_manager = get_tree().get_first_node_in_group(RoundManager.GROUP) as RoundManager
	if tuning == null:
		tuning = Tuning.load_default()
	_apply_difficulty()


func _physics_process(delta: float) -> void:
	if not is_instance_valid(character) or arena == null or round_manager == null:
		return
	if not character.alive:
		character.move_intent = Vector2.ZERO
		return
	if round_manager.phase != _phase:
		_enter_phase(round_manager.phase)
	_clock += delta
	_dodge_timer = maxf(_dodge_timer - delta, 0.0)
	_maybe_use_power()
	match _phase:
		RoundManager.TOPPLE:
			if _is_attacker():
				_topple_attacker(delta)
			else:
				_topple_defender()
		RoundManager.SCATTER:
			if _is_attacker():
				_scatter_attacker()
			else:
				_scatter_defender(delta)
		_:
			character.move_intent = Vector2.ZERO


## Sets the world references and reads difficulty from [param new_tuning].
func bind(new_arena: Arena, new_round_manager: RoundManager, new_tuning: Tuning) -> void:
	arena = new_arena
	round_manager = new_round_manager
	tuning = new_tuning
	_apply_difficulty()


## Seeds the random generator so a test run is repeatable.
func seed_rng(seed_value: int) -> void:
	_rng.seed = seed_value


func _on_attached(_target: Character) -> void:
	_carry_time = 0.0
	_hold_timer = 0.0
	_next_decision = 0.0
	_dodge_timer = 0.0
	_lane_timer = 0.0
	_dodge_rolls.clear()


func _apply_difficulty() -> void:
	var difficulty: float = clampf(tuning.bot_difficulty, 0.0, 1.0)
	aim_error = deg_to_rad(lerpf(AIM_ERROR_DEGREES.x, AIM_ERROR_DEGREES.y, difficulty))
	reaction_delay = lerpf(REACTION_DELAY.x, REACTION_DELAY.y, difficulty)
	dodge_chance = lerpf(DODGE_CHANCE.x, DODGE_CHANCE.y, difficulty)
	shot_chance = lerpf(SHOT_CHANCE.x, SHOT_CHANCE.y, difficulty)
	build_skill_factor = lerpf(tuning.bot_build_slowdown, 1.0, difficulty)


# A hero bot uses its power when the moment pays: a carrier or a defender with a foe close, or a builder under threat.
func _maybe_use_power() -> void:
	if character.hero == null or not character.can_use_power():
		return
	if _phase != RoundManager.SCATTER and _phase != RoundManager.TOPPLE:
		return
	var foe_team: int = 1 - character.team
	var near_foe: bool = false
	for entry: Variant in arena.get_characters(foe_team):
		var foe: Character = entry as Character
		if foe.alive and foe.global_position.distance_to(character.global_position) < POWER_TRIGGER_RADIUS:
			near_foe = true
			break
	if near_foe or (_is_attacker() and character.carried != null and _phase == RoundManager.SCATTER):
		character.try_power()


func _enter_phase(phase: int) -> void:
	_phase = phase
	_build_timer = 0.0
	_carry_time = 0.0
	_hold_timer = 0.0
	_next_decision = 0.0
	_lane_timer = 0.0
	_dodge_rolls.clear()


func _is_attacker() -> bool:
	return character.role == Character.Role.ATTACKER


func _other_team() -> int:
	return 1 - character.team


func _steer_to(target: Vector2, arrive_radius: float) -> Vector2:
	var offset: Vector2 = target - character.global_position
	if offset.length() <= arrive_radius:
		return Vector2.ZERO
	return offset.normalized()


func _alive_members(team: int) -> Array[Character]:
	var members: Array[Character] = []
	for entry: Variant in arena.get_characters(team):
		var member: Character = entry as Character
		if member != null and member.alive:
			members.append(member)
	return members


func _is_pass_holder(member: Character) -> bool:
	return member.carried != null and member.carried.is_pass_sandal


func _topple_attacker(delta: float) -> void:
	character.move_intent = Vector2.ZERO
	if character.carried == null:
		_carry_time = 0.0
		return
	var to_stack: Vector2 = arena.centre_spot - character.global_position
	_carry_time += delta
	if _carry_time < reaction_delay:
		return
	var direction: Vector2 = to_stack.normalized().rotated(_rng.randfn(0.0, aim_error * 0.5))
	character.throw_sandal(direction, THROW_POWER)
	_carry_time = 0.0


func _topple_defender() -> void:
	character.move_intent = Vector2.ZERO


func _scatter_attacker() -> void:
	var stack: Stack = arena.stack
	var steer: Vector2 = Vector2.ZERO
	if character.carried != null:
		# The zone drop is automatic, so walking into the zone delivers the sandal.
		steer = _steer_to(arena.centre_spot, 0.0)
	elif stack != null and stack.can_build() and (stack.builder == null or stack.builder == character):
		steer = _build_step(stack)
	elif stack != null and stack.can_build():
		_stop_build()
		steer = _guard_step()
	else:
		_stop_build()
		var sandal: Sandal = _nearest_pickable()
		if sandal != null:
			steer = _steer_to(sandal.global_position, 0.0)
			if character.global_position.distance_to(sandal.global_position) <= tuning.pickup_radius:
				character.pick_up(sandal)
		else:
			steer = _guard_step()
	# A carrier near the zone must arrive. A defender in the way would cancel the steering into a wobble.
	var near_zone: bool = character.carried != null and character.global_position.distance_to(arena.centre_spot) < tuning.build_zone_radius * 2.0
	if not character.is_building() and not near_zone:
		steer += _holder_avoidance() * AVOID_WEIGHT
	_try_dodge()
	if _dodge_timer > 0.0:
		steer = _dodge_direction
	character.move_intent = steer.limit_length(1.0)


## Walks to a slot in the guard ring on the side of the pass holder, where a thrown sandal arrives first.
## Each free attacker takes its own slot, spread along the arc, so two guards never stack on one spot.
func _guard_step() -> Vector2:
	var holder: Character = null
	for foe: Character in _alive_members(_other_team()):
		if _is_pass_holder(foe):
			holder = foe
			break
	var facing: Vector2 = Vector2.RIGHT
	if holder != null:
		facing = (holder.global_position - arena.centre_spot).normalized()
	var guards: Array[Character] = []
	for member: Character in _alive_members(character.team):
		if member.carried == null and not member.is_building():
			guards.append(member)
	var index: int = maxi(guards.find(character), 0)
	var spread: float = (float(index) - float(guards.size() - 1) * 0.5) * GUARD_ARC_STEP
	var radius: float = tuning.build_zone_radius + tuning.guard_ring_width * 0.5
	var slot: Vector2 = arena.centre_spot + facing.rotated(spread) * radius
	return _steer_to(slot, 6.0)


## Walks to the middle of the build zone, then builds with a simulated time per step. The bot
## stands still while it builds and the avoidance push is off, so the two never cancel into a wobble.
func _build_step(stack: Stack) -> Vector2:
	var arrive: float = tuning.build_zone_radius * 0.4
	var to_centre: float = character.global_position.distance_to(arena.centre_spot)
	if to_centre > arrive and not character.is_building():
		_build_timer = 0.0
		return _steer_to(arena.centre_spot, arrive)
	if not character.is_building():
		if not character.start_building():
			return Vector2.ZERO
		_build_timer = 0.0
	_build_timer += get_physics_process_delta_time()
	if _build_timer >= tuning.build_step_seconds * build_skill_factor:
		_build_timer = 0.0
		character.complete_build_step()
	return Vector2.ZERO


func _stop_build() -> void:
	if character.is_building():
		character.stop_building()
	_build_timer = 0.0


func _nearest_pickable() -> Sandal:
	var best: Sandal = null
	var best_distance: float = INF
	for entry: Variant in arena.get_loose_sandals():
		var sandal: Sandal = entry as Sandal
		if sandal == null or sandal.is_pass_sandal:
			continue
		if arena.stack != null and arena.stack.is_down and arena.stack.is_in_zone(sandal.global_position):
			continue
		var distance: float = character.global_position.distance_to(sandal.global_position)
		if distance < best_distance:
			best_distance = distance
			best = sandal
	return best


func _holder_avoidance() -> Vector2:
	var push: Vector2 = Vector2.ZERO
	for defender: Character in _alive_members(_other_team()):
		if not _is_pass_holder(defender):
			continue
		var away: Vector2 = character.global_position - defender.global_position
		var distance: float = away.length()
		if distance < AVOID_RADIUS and distance > 0.001:
			push += away.normalized() * (1.0 - distance / AVOID_RADIUS)
	return push


func _flying_pass_sandals() -> Array[Sandal]:
	var found: Array[Sandal] = []
	for node: Node in get_tree().get_nodes_in_group(Sandal.GROUP):
		var sandal: Sandal = node as Sandal
		if sandal != null and sandal.is_pass_sandal and sandal.in_flight:
			found.append(sandal)
	return found


func _try_dodge() -> void:
	if not character.can_dash():
		return
	for sandal: Sandal in _flying_pass_sandals():
		var velocity: Vector2 = sandal.linear_velocity
		if velocity.length_squared() < 1.0:
			continue
		var relative: Vector2 = character.global_position - sandal.global_position
		var time_to_closest: float = relative.dot(velocity) / velocity.length_squared()
		if time_to_closest < 0.0 or time_to_closest > DODGE_LOOKAHEAD:
			continue
		var miss: Vector2 = relative - velocity * time_to_closest
		if miss.length() > DANGER_RADIUS:
			continue
		var sandal_id: int = sandal.get_instance_id()
		if not _dodge_rolls.has(sandal_id):
			_dodge_rolls[sandal_id] = _rng.randf() < dodge_chance
		if not _dodge_rolls[sandal_id]:
			continue
		var side: Vector2 = velocity.orthogonal().normalized()
		if side.dot(miss) < 0.0:
			side = -side
		_dodge_direction = side
		_dodge_timer = DODGE_HOLD
		character.move_intent = side
		character.dash()
		return


func _scatter_defender(delta: float) -> void:
	if _is_pass_holder(character):
		_holder_step(delta)
		return
	_hold_timer = 0.0
	_support_step(delta)


func _throw_range() -> float:
	return (tuning.throw_speed_max - tuning.flight_min_speed) / maxf(tuning.sandal_damping, 0.1) * RANGE_TRUST


func _holder_step(delta: float) -> void:
	character.move_intent = Vector2.ZERO
	_hold_timer += delta
	if _hold_timer < reaction_delay or _clock < _next_decision:
		return
	_next_decision = _clock + DECISION_INTERVAL
	var shot: Vector2 = _find_shot()
	if shot != Vector2.ZERO and _rng.randf() < shot_chance:
		character.throw_sandal(shot, THROW_POWER)
		_hold_timer = 0.0
		return
	var mate: Character = _best_pass_target(_hold_timer > reaction_delay + HOLD_LIMIT)
	if mate != null:
		character.pass_to(mate)
		_hold_timer = 0.0


func _find_shot() -> Vector2:
	var teammates: Array[Character] = _alive_members(character.team)
	var best_direction: Vector2 = Vector2.ZERO
	var best_distance: float = INF
	for attacker: Character in _alive_members(_other_team()):
		var distance: float = character.global_position.distance_to(attacker.global_position)
		if distance > _throw_range():
			continue
		# A builder is the priority target. A guard absorbs the shot, so only an open attacker is worth it.
		var covered: bool = attacker.can_block()
		var is_builder: bool = attacker.is_building()
		var rank: float = distance - (1000.0 if is_builder else 0.0) + (2000.0 if covered else 0.0)
		if rank >= best_distance:
			continue
		var direction: Vector2 = character.lead_direction(attacker, THROW_POWER)
		var end: Vector2 = character.global_position + direction * distance
		var blocked: bool = false
		for mate: Character in teammates:
			if mate == character:
				continue
			var closest: Vector2 = Geometry2D.get_closest_point_to_segment(mate.global_position, character.global_position, end)
			if closest.distance_to(mate.global_position) < PASS_CLEAR_RADIUS:
				blocked = true
				break
		if blocked:
			continue
		best_distance = rank
		best_direction = direction
	var stack: Stack = arena.stack
	if stack != null and best_direction == Vector2.ZERO:
		# No attacker is open. A half-built teepee, then a gathered sandal, is the next target.
		var aim_points: Array[Vector2] = []
		if stack.placed_count > 0:
			aim_points.append(stack.global_position)
		else:
			for sandal: Sandal in stack.zone_sandals():
				aim_points.append(sandal.global_position)
		var nearest: float = INF
		for point: Vector2 in aim_points:
			var distance: float = character.global_position.distance_to(point)
			if distance <= _throw_range() and distance < nearest and _lane_is_clear(point, teammates):
				nearest = distance
				best_direction = (point - character.global_position).normalized()
	if best_direction == Vector2.ZERO:
		return Vector2.ZERO
	return best_direction.rotated(_rng.randfn(0.0, aim_error * 0.5))


func _lane_is_clear(end: Vector2, teammates: Array[Character]) -> bool:
	for mate: Character in teammates:
		if mate == character:
			continue
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(mate.global_position, character.global_position, end)
		if closest.distance_to(mate.global_position) < PASS_CLEAR_RADIUS:
			return false
	return true


func _openness(from: Vector2, to: Vector2, attackers: Array[Character]) -> float:
	var openness: float = INF
	for attacker: Character in attackers:
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(attacker.global_position, from, to)
		openness = minf(openness, closest.distance_to(attacker.global_position))
	return openness


func _best_pass_target(accept_blocked: bool) -> Character:
	var attackers: Array[Character] = _alive_members(_other_team())
	var best: Character = null
	var best_score: float = -INF
	for mate: Character in _alive_members(character.team):
		if mate == character:
			continue
		var lane: float = _openness(character.global_position, mate.global_position, attackers)
		if lane > best_score:
			best_score = lane
			best = mate
	if best == null:
		return null
	if best_score < PASS_CLEAR_RADIUS and not accept_blocked:
		return null
	return best


func _find_holder() -> Character:
	for mate: Character in _alive_members(character.team):
		if _is_pass_holder(mate):
			return mate
	return null


func _support_step(delta: float) -> void:
	var holder: Character = _find_holder()
	if holder == null:
		var loose: Sandal = _loose_pass_sandal()
		if loose != null and _is_closest_defender_to(loose.global_position):
			if character.global_position.distance_to(loose.global_position) <= tuning.pickup_radius:
				character.pick_up(loose)
			character.move_intent = _steer_to(loose.global_position, 0.0)
			return
	if holder == null:
		character.move_intent = _steer_to(arena.centre_spot, tuning.orbit_radius)
		return
	_lane_timer -= delta
	if _lane_timer <= 0.0:
		_lane_timer = REPLAN_INTERVAL
		_lane_target = _pick_lane(holder)
	character.move_intent = _steer_to(_lane_target, ARRIVE_RADIUS)


func _loose_pass_sandal() -> Sandal:
	for entry: Variant in arena.get_loose_sandals():
		var sandal: Sandal = entry as Sandal
		if sandal != null and sandal.is_pass_sandal:
			return sandal
	return null


func _is_closest_defender_to(point: Vector2) -> bool:
	var own_distance: float = character.global_position.distance_to(point)
	for mate: Character in _alive_members(character.team):
		if mate != character and mate.global_position.distance_to(point) < own_distance:
			return false
	return true


func _pick_lane(holder: Character) -> Vector2:
	var attackers: Array[Character] = _alive_members(_other_team())
	var mates: Array[Character] = _alive_members(character.team)
	# A target on the wall line is out of reach for a body with a radius, so the bot would push into the wall forever.
	var inset: Vector2 = Vector2.ONE * (tuning.character_radius + ARRIVE_RADIUS * 2.0)
	var bounds: Rect2 = Rect2(arena.centre_spot - tuning.arena_half_extents + inset, tuning.arena_half_extents * 2.0 - inset * 2.0)
	var best_target: Vector2 = character.global_position
	var best_score: float = -INF
	for index: int in 8:
		var candidate: Vector2 = holder.global_position + Vector2.from_angle(TAU * float(index) / 8.0) * LANE_RADIUS
		candidate = candidate.clamp(bounds.position, bounds.end)
		var score: float = minf(_openness(holder.global_position, candidate, attackers), 300.0)
		score -= 0.35 * character.global_position.distance_to(candidate)
		for mate: Character in mates:
			if mate != character and mate != holder and mate.global_position.distance_to(candidate) < 100.0:
				score -= 80.0
		if score > best_score:
			best_score = score
			best_target = candidate
	return best_target
