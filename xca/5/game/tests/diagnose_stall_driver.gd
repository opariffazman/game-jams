extends Node
## Per-frame driver for diagnose_stall.gd. Scripts the human seat and watches the pass sandal.

var owner_probe: Object

var _age: float = 0.0
var _last_phase: int = -1
var _logged: bool = false
var _stall_start: float = -1.0
var _holder_clock: float = 0.0
var _nan_logged: bool = false
var _nan_count: int = 0
var _prev_pos: Vector2 = Vector2.ZERO
var _prev_vel: Vector2 = Vector2.ZERO
var _prev_flight: bool = false
var _prev_freeze: bool = false
var _last_event: String = "none"
var _watched: Dictionary = {}


func _physics_process(delta: float) -> void:
	var probe: Object = owner_probe
	if probe == null:
		return
	var manager: RoundManager = probe.manager
	var arena: Arena = probe.arena
	probe.frame += 1
	if probe.frame % 600 == 0:
		print("heartbeat frame=%d phase=%d scatters=%d stalls=%d" % [probe.frame, manager.phase, probe.scatters, probe.stalls])
	if manager.phase == RoundManager.MATCH_END:
		manager.start_match()
		return
	if manager.phase != _last_phase:
		if manager.phase == RoundManager.SCATTER:
			probe.scatters += 1
			print("scatter %d started, stalls so far %d, frame %d" % [probe.scatters, probe.stalls, probe.frame])
			_age = 0.0
			_logged = false
			_stall_start = -1.0
		if _last_phase == RoundManager.SCATTER and manager.phase == RoundManager.ROUND_END:
			var winner_is_attacker: bool = manager.attacking_team == _winner(manager)
			probe.rounds_by_end["rebuilt" if winner_is_attacker else "all_mati"] += 1
		_last_phase = manager.phase
	_drive_human(manager, arena, probe.mode)
	if manager.phase != RoundManager.SCATTER:
		return
	_age += delta
	var pass_sandal: Sandal = _find_pass_sandal()
	if pass_sandal != null and probe.scatters == int(OS.get_environment("DIAGNOSE_TRACE_SCATTER") if OS.get_environment("DIAGNOSE_TRACE_SCATTER") != "" else "-1") and not _nan_logged:
		var near: Array[String] = []
		for team_i: int in 2:
			for entry_n: Variant in arena.get_characters(team_i):
				var ch: Character = entry_n as Character
				if ch != null:
					var dist: float = ch.global_position.distance_to(pass_sandal.global_position)
					if dist < 90.0:
						near.append("t%d%s%s d=%.1f" % [team_i, "A" if ch.role == Character.Role.ATTACKER else "D", "" if ch.alive else "x", dist])
		var touching: Array[String] = []
		for body: Node2D in pass_sandal.get_colliding_bodies():
			touching.append("%s %s layer=%d" % [body.get_class(), body.name, body.get("collision_layer") if body.get("collision_layer") != null else -1])
		print("TOUCH ", touching, " shape_disabled_attackers=", _disabled_attackers(arena))
		print("TRACE f=%d pos=(%.1f,%.1f) vel=(%.1f,%.1f) contacts=%d flight=%s damp=%.2f ang=%.2f near=%s" % [probe.frame, pass_sandal.global_position.x, pass_sandal.global_position.y, pass_sandal.linear_velocity.x, pass_sandal.linear_velocity.y, pass_sandal.get_contact_count(), str(pass_sandal.in_flight), pass_sandal.linear_damp, pass_sandal.angular_velocity, str(near)])
	if pass_sandal != null:
		if is_nan(pass_sandal.global_position.x) and not _nan_logged:
			_nan_logged = false
			_nan_count += 1
			print("NANTRACE first NaN at scatter=%d age=%.2f previous: pos=(%.1f,%.1f) vel=(%.1f,%.1f) in_flight=%s freeze=%s | last event: %s" % [probe.scatters, _age, _prev_pos.x, _prev_pos.y, _prev_vel.x, _prev_vel.y, str(_prev_flight), str(_prev_freeze), _last_event])
		else:
			_prev_pos = pass_sandal.global_position
			_prev_vel = pass_sandal.linear_velocity
			_prev_flight = pass_sandal.in_flight
			_prev_freeze = pass_sandal.freeze
		_watch(pass_sandal, manager, arena)
	var holder: Character = _holder(arena, manager)
	var flying: bool = pass_sandal != null and pass_sandal.in_flight
	var lost: bool = holder == null and not flying
	if lost:
		if _stall_start < 0.0:
			_stall_start = _age
	else:
		_stall_start = -1.0
	if lost and _age - _stall_start >= 20.0 and not _logged:
		_logged = true
		probe.stalls += 1
		probe.stall_reports.append(_describe(probe, manager, arena, pass_sandal))
		print(probe.stall_reports[-1])
	if _age > probe.MAX_SCATTER_SECONDS:
		probe.rounds_by_end["timeout"] += 1
		if not _logged:
			_logged = true
			probe.stalls += 1
			probe.stall_reports.append("TIMEOUT-NOT-LOST " + _describe(probe, manager, arena, pass_sandal))
			print(probe.stall_reports[-1])
		manager.end_round(1 - manager.attacking_team)
	if probe.scatters >= probe.target_scatters and manager.phase == RoundManager.ROUND_END:
		probe.finish()


func _winner(manager: RoundManager) -> int:
	return manager._round_winner


func _find_pass_sandal() -> Sandal:
	for node: Node in get_tree().get_nodes_in_group(Sandal.GROUP):
		var sandal: Sandal = node as Sandal
		if sandal != null and sandal.is_pass_sandal and not sandal.is_queued_for_deletion():
			return sandal
	return null


func _holder(arena: Arena, manager: RoundManager) -> Character:
	for team: int in 2:
		for entry: Variant in arena.get_characters(team):
			var character: Character = entry as Character
			if character != null and character.alive and character.carried != null and character.carried.is_pass_sandal:
				return character
	return null


func _drive_human(manager: RoundManager, arena: Arena, mode: String) -> void:
	# The human seat is either an idle or a rebuilding attacker. When the coin flip makes the human a defender, the
	# human never throws, so the pass sandal sits with a bot until the bots take over: detach the human to hand the seat to its bot.
	var human: HumanController = manager.human
	if human == null or human.character == null or not is_instance_valid(human.character):
		return
	var body: Character = human.character
	if not body.alive:
		return
	if manager.phase == RoundManager.SCATTER and body.role == Character.Role.DEFENDER and body.carried != null and body.carried.is_pass_sandal:
		# A defender seat that holds the pass sandal passes it on after one second, like a player would.
		_holder_clock += get_physics_process_delta_time()
		if _holder_clock > 1.0:
			_holder_clock = 0.0
			for entry: Variant in arena.get_characters(body.team):
				var mate: Character = entry as Character
				if mate != body and mate.alive:
					body.pass_to(mate)
					break
		return
	_holder_clock = 0.0
	if manager.phase == RoundManager.TOPPLE and body.role == Character.Role.ATTACKER and body.carried != null:
		# Both modes throw at the stack, as a player does. Only the scatter behaviour differs: idle stands still, rebuild carries sandals.
		body.throw_sandal((arena.centre_spot - body.global_position).normalized(), 1.0)
		return
	if manager.phase == RoundManager.SCATTER and body.role == Character.Role.ATTACKER and mode == "rebuild":
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
			steer = (arena.centre_spot - body.global_position)
			steer = steer.normalized() if steer.length() > 30.0 else Vector2.ZERO
		body.move_intent = steer


func _describe(probe: Object, manager: RoundManager, arena: Arena, pass_sandal: Sandal) -> String:
	if pass_sandal == null:
		return "STALL round=%d pass sandal does not exist" % probe.scatters
	var carried_by: String = "nobody"
	for team: int in 2:
		for entry: Variant in arena.get_characters(team):
			var character: Character = entry as Character
			if character != null and character.carried == pass_sandal:
				carried_by = "team %d %s alive=%s" % [character.team, "attacker" if character.role == Character.Role.ATTACKER else "defender", str(character.alive)]
	var offset: Vector2 = pass_sandal.global_position - arena.centre_spot
	var half: Vector2 = probe.tuning.arena_half_extents
	var near_wall: bool = absf(offset.x) > half.x - 40.0 or absf(offset.y) > half.y - 40.0
	var defenders: Array[String] = []
	for entry: Variant in arena.get_characters(1 - manager.attacking_team):
		var defender: Character = entry as Character
		if defender != null:
			defenders.append("alive=%s d=%.0f" % [str(defender.alive), defender.global_position.distance_to(pass_sandal.global_position)])
	var closest_live: float = INF
	for entry: Variant in arena.get_characters(1 - manager.attacking_team):
		var d: Character = entry as Character
		if d != null and d.alive:
			closest_live = minf(closest_live, d.global_position.distance_to(pass_sandal.global_position))
	var pickup_ok: bool = false
	for entry: Variant in arena.get_characters(1 - manager.attacking_team):
		var d2: Character = entry as Character
		if d2 != null and d2.alive:
			pickup_ok = d2.pickup_enabled
	var bot_state: String = "no bot"
	for team_index: int in 2:
		for entry_c: Variant in arena.get_characters(team_index):
			var holder_c: Character = entry_c as Character
			if holder_c != null and holder_c.carried == pass_sandal:
				var bot: BotController = manager._bots.get(holder_c) as BotController
				if bot != null:
					bot_state = "bot attached=%s processing=%s hold_timer=%.1f next_decision=%.1f clock=%.1f reaction=%.2f phase_seen=%d move_intent=%s" % [str(bot.character == holder_c), str(bot.is_physics_processing()), bot._hold_timer, bot._next_decision, bot._clock, bot.reaction_delay, bot._phase, str(holder_c.move_intent)]
				var is_human_body: bool = manager.human != null and manager.human.character == holder_c
				bot_state += " is_human_body=%s in_human_group=%s" % [str(is_human_body), str(holder_c.is_in_group(&"human_controlled"))]
	var attackers_text: Array[String] = []
	for entry_a: Variant in arena.get_characters(manager.attacking_team):
		var attacker: Character = entry_a as Character
		if attacker != null:
			attackers_text.append("%s%s@(%.0f,%.0f) carry=%s human=%s" % ["A", "" if attacker.alive else "x", attacker.global_position.x, attacker.global_position.y, str(attacker.carried != null), str(manager.human != null and manager.human.character == attacker)])
	var loose_text: Array[String] = []
	for entry_l: Variant in arena.get_loose_sandals():
		var loose: Sandal = entry_l as Sandal
		loose_text.append("(%.0f,%.0f)%s" % [loose.global_position.x, loose.global_position.y, "P" if loose.is_pass_sandal else ""])
	bot_state += " | attackers=%s | stack down=%s placed=%d | loose=%s" % [str(attackers_text), str(arena.stack.is_down), arena.stack.placed_count, str(loose_text)]
	return "STALL scatter=%d at=%.1fs pass_sandal pos=(%.0f,%.0f) off_centre=%.0f carried_by=%s frozen=%s in_flight=%s speed=%.1f near_wall=%s outside_arena=%s in_stack=%s loose_listed=%s closest_live_defender=%.0f defenders=%s pickup_enabled=%s" % [
		probe.scatters, _age, pass_sandal.global_position.x, pass_sandal.global_position.y, offset.length(), carried_by,
		str(pass_sandal.freeze), str(pass_sandal.in_flight), pass_sandal.linear_velocity.length(), str(near_wall),
		str(absf(offset.x) > half.x or absf(offset.y) > half.y), str(arena.stack.is_standing(pass_sandal)),
		str(arena.get_loose_sandals().has(pass_sandal)), closest_live, str(defenders), str(pickup_ok)] + " | " + bot_state


func _watch(_pass_sandal: Sandal, manager: RoundManager, arena: Arena) -> void:
	for team: int in 2:
		for entry: Variant in arena.get_characters(team):
			var character: Character = entry as Character
			if character == null or _watched.has(character.get_instance_id()):
				continue
			_watched[character.get_instance_id()] = true
			character.threw.connect(func(sandal: Sandal) -> void: _last_event = "threw by team%d %s alive=%s sandal_is_pass=%s pos_before=(%.0f,%.0f)" % [character.team, "ATT" if character.role == Character.Role.ATTACKER else "DEF", str(character.alive), str(sandal.is_pass_sandal), sandal.global_position.x, sandal.global_position.y])
			character.passed.connect(func(receiver: Character) -> void: _last_event = "passed by team%d to team%d receiver_alive=%s dist=%.1f" % [character.team, receiver.team, str(receiver.alive), character.global_position.distance_to(receiver.global_position)])
			character.died.connect(func() -> void: _last_event = "died team%d %s with pass sandal carried=%s" % [character.team, "ATT" if character.role == Character.Role.ATTACKER else "DEF", str(character.carried != null)])


func _disabled_attackers(arena: Arena) -> Array[String]:
	var found: Array[String] = []
	for team: int in 2:
		for entry: Variant in arena.get_characters(team):
			var ch: Character = entry as Character
			if ch != null and not ch.alive:
				var shape: CollisionShape2D = ch.get_node_or_null("CollisionShape2D") as CollisionShape2D
				found.append("t%d %s disabled=%s layer=%d mask=%d" % [team, "A" if ch.role == Character.Role.ATTACKER else "D", str(shape.disabled) if shape != null else "?", ch.collision_layer, ch.collision_mask])
	return found
