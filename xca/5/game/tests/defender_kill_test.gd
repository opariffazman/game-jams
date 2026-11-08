extends SceneTree
## Regression test: a defender throws the pass sandal and kills an attacker. The sandal must stay
## in play, so a defender can pick it up again and the round still has a pass sandal.

var _failures: int = 0


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		print("FAIL ", label)


func _frames(count: int) -> void:
	for _i: int in count:
		await physics_frame


func _pass_sandal() -> Sandal:
	for node: Node in get_nodes_in_group(Sandal.GROUP):
		var sandal: Sandal = node as Sandal
		if sandal != null and sandal.is_pass_sandal and not sandal.is_queued_for_deletion():
			return sandal
	return null


func _holder(arena: Arena) -> Character:
	for entry: Variant in arena.get_characters(1):
		var member: Character = entry as Character
		if member != null and member.alive and member.carried != null:
			return member
	for team: int in 2:
		for entry: Variant in arena.get_characters(team):
			var member: Character = entry as Character
			if member != null and member.alive and member.carried != null and member.carried.is_pass_sandal:
				return member
	return null


func _initialize() -> void:
	_run()


func _run() -> void:
	await physics_frame
	var tuning: Tuning = Tuning.load_default().duplicate() as Tuning
	tuning.match_countdown = false
	tuning.human_team = 0
	var arena: Arena = (load("res://scenes/arena.tscn") as PackedScene).instantiate() as Arena
	arena.tuning = tuning
	root.add_child(arena)
	var manager: RoundManager = RoundManager.new()
	manager.tuning = tuning
	manager.arena = arena
	root.add_child(manager)
	var kills: int = 0
	var rounds: int = 0
	var waited: int = 0
	while kills < 4 and waited < 60000:
		await physics_frame
		waited += 1
		if manager.phase == RoundManager.MATCH_END:
			manager.start_match()
			continue
		if manager.phase != RoundManager.SCATTER:
			continue
		var holder: Character = _holder(arena)
		var pass_sandal: Sandal = _pass_sandal()
		if holder == null or pass_sandal == null or holder.role != Character.Role.DEFENDER:
			continue
		var victim: Character = null
		for entry: Variant in arena.get_characters(manager.attacking_team):
			var mate: Character = entry as Character
			if mate != null and mate.alive and (victim == null or mate.global_position.distance_to(holder.global_position) < victim.global_position.distance_to(holder.global_position)):
				victim = mate
		if victim == null:
			continue
		# Silence bots so only the scripted throw acts, then freeze the victim in the line of fire.
		for bot: Variant in manager._bots.values():
			(bot as BotController).detach()
		if kills % 2 == 1 and victim.carried == null:
			for node: Node in get_nodes_in_group(Sandal.GROUP):
				var loose: Sandal = node as Sandal
				if loose != null and not loose.is_pass_sandal and not loose.freeze and not loose.is_placed and victim.carried == null:
					victim.pick_up(loose)
		victim.global_position = holder.global_position + Vector2(220.0, 0.0)
		victim.velocity = Vector2.ZERO
		await physics_frame
		var carried_before: Sandal = victim.carried
		holder.throw_manual(Vector2.RIGHT, 1.0)
		var before_alive: int = manager._alive_team(manager.attacking_team).size()
		await _frames(150)
		var killed: bool = not victim.alive
		if not killed:
			continue
		kills += 1
		if carried_before != null and is_instance_valid(carried_before) and not carried_before.is_pass_sandal:
			var clear_of_tombstone: float = tuning.character_radius + tuning.sandal_radius
			_check(carried_before.global_position.distance_to(victim.global_position) >= clear_of_tombstone, "the dead attacker's sandal lies clear of the tombstone (%.0f px)" % carried_before.global_position.distance_to(victim.global_position))
		var remaining: Sandal = _pass_sandal()
		_check(remaining != null, "pass sandal exists after the kill")
		if remaining != null:
			_check(remaining.global_position.is_finite(), "pass sandal position is finite")
			var who: String = "nobody"
			for team: int in 2:
				for entry: Variant in arena.get_characters(team):
					var m: Character = entry as Character
					if m != null and m.carried == remaining:
						who = "%s alive %s role %d" % [m.name, str(m.alive), m.role]
			_check(not remaining.freeze or who != "nobody", "pass sandal lies free or is held after the kill")
			_check(not remaining.in_flight, "pass sandal rests after the kill")
			_check(remaining.get_parent() == arena, "pass sandal stays in the arena")
			_check(remaining.visible and (remaining.visual == null or remaining.visual.visible), "pass sandal is visible")
			var inside: Rect2 = Rect2(tuning.arena_centre - tuning.arena_half_extents, tuning.arena_half_extents * 2.0)
			_check(inside.has_point(remaining.global_position), "pass sandal lies inside the walls, at %s" % str(remaining.global_position))
			for node: Node in get_nodes_in_group(Sandal.GROUP):
				var other: Sandal = node as Sandal
				if other != null and not other.is_queued_for_deletion() and not other.is_placed and other.get_parent() == arena:
					_check(inside.has_point(other.global_position) and other.global_position.is_finite(), "every loose sandal lies inside the walls")
					_check(other.visible, "every loose sandal is visible")
			# A defender walks to the sandal and must be able to take it.
			var taker: Character = null
			for entry: Variant in arena.get_characters(1 - manager.attacking_team):
				var mate: Character = entry as Character
				if mate != null and mate.alive:
					taker = mate
					break
			if taker != null and manager.phase == RoundManager.SCATTER:
				var ok: bool = false
				for _i: int in 240:
					taker.global_position = remaining.global_position
					await physics_frame
					if _holder(arena) != null:
						ok = true
						break
				_check(ok, "a defender picks the pass sandal up after the kill (alive attackers %d)" % before_alive)
		if manager.phase == RoundManager.SCATTER:
			manager.end_round(1 - manager.attacking_team)
		await _frames(30)
	_check(kills >= 1, "at least one kill happened")
	print("defender_kill_test: %s (%d failures, %d kills)" % ["PASS" if _failures == 0 else "FAIL", _failures, kills])
	quit(_failures)
