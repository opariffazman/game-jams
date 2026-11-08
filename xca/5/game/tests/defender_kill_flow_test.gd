extends SceneTree
## Regression test: a human defender kills attackers with the real scheme code (aim stick fire and
## locked hit), including the last attacker. After every kill a pass sandal must lie free for a
## defender, and the next round must hand the new defenders a pass sandal in scatter.

var _failures: int = 0
var _manager: RoundManager
var _arena: Arena


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


func _holder() -> Character:
	for team: int in 2:
		for entry: Variant in _arena.get_characters(team):
			var member: Character = entry as Character
			if member != null and member.alive and member.carried != null and member.carried.is_pass_sandal:
				return member
	return null


func _initialize() -> void:
	Engine.time_scale = 6.0
	Engine.max_physics_steps_per_frame = 16
	_run()


func _run() -> void:
	await physics_frame
	var tuning: Tuning = Tuning.load_default().duplicate() as Tuning
	tuning.match_countdown = false
	tuning.human_team = 0
	_arena = (load("res://scenes/arena.tscn") as PackedScene).instantiate() as Arena
	_arena.tuning = tuning
	root.add_child(_arena)
	_manager = RoundManager.new()
	_manager.tuning = tuning
	_manager.arena = _arena
	root.add_child(_manager)
	SettingsRef.set_scheme(SettingsRef.SCHEME_LOCK_FIRE)
	var wipes: int = 0
	var swaps: int = 0
	var last_attacking: int = -1
	var waited: int = 0
	while wipes < 2 and waited < 40000:
		await physics_frame
		waited += 1
		if _manager.phase == RoundManager.MATCH_END:
			_manager.start_match()
			continue
		if _manager.phase != RoundManager.SCATTER:
			continue
		if last_attacking != -1 and last_attacking != _manager.attacking_team:
			swaps += 1
			_check(_holder() != null or _pass_sandal() != null, "the new round has a pass sandal after the role swap")
		last_attacking = _manager.attacking_team
		var human: Character = _manager.human.character
		if human == null or not is_instance_valid(human) or not human.alive or human.role != Character.Role.DEFENDER:
			# Let the round run out, bots attack and defend.
			await _frames(1)
			continue
		var scheme: ThrowScheme = _manager.human.scheme
		for bot: Variant in _manager._bots.values():
			(bot as BotController).detach()
		# Kill every attacker one at a time with the real locked hit, the last one included.
		while is_instance_valid(human) and _manager.phase == RoundManager.SCATTER and not _manager._alive_team(_manager.attacking_team).is_empty():
			if human.carried == null:
				var loose: Sandal = _pass_sandal()
				_check(loose != null, "a pass sandal exists while attackers live")
				if loose == null:
					break
				var mate: Character = _holder()
				if mate != null and mate != human:
					mate.pass_to(human)
				else:
					human.global_position = loose.global_position + Vector2(40.0, 0.0)
				await _frames(40)
				_check(human.carried != null, "the human defender gets the pass sandal (mate held %s, at %s)" % [str(mate != null), str(loose.global_position)])
				if human.carried == null:
					break
			var victim: Character = _manager._alive_team(_manager.attacking_team)[0]
			victim.velocity = Vector2.ZERO
			victim.global_position = human.global_position + Vector2(200.0, 0.0)
			await physics_frame
			var alive_before: int = _manager._alive_team(_manager.attacking_team).size()
			scheme.character = human
			scheme.locked = victim
			scheme.kind = ThrowScheme.TargetKind.FOE
			_check(scheme.fire(), "the locked hit leaves the hand")
			await _frames(120)
			if victim.alive:
				# A miss: the sandal must still be reachable.
				_check(_pass_sandal() != null, "the pass sandal survives a miss")
				continue
			_check(_pass_sandal() != null or _manager.phase != RoundManager.SCATTER, "a pass sandal survives the kill (alive before %d)" % alive_before)
		if _manager.phase == RoundManager.ROUND_END or _manager._alive_team(_manager.attacking_team).is_empty():
			wipes += 1
		await _frames(int(_manager.tuning.round_end_delay * 60.0) + 120)
	Engine.time_scale = 1.0
	_check(wipes >= 1, "at least one wipe happened (%d)" % wipes)
	_check(swaps >= 1, "at least one role swap happened (%d)" % swaps)
	print("defender_kill_flow_test: %s (%d failures, %d wipes, %d swaps)" % ["PASS" if _failures == 0 else "FAIL", _failures, wipes, swaps])
	quit(_failures)
