extends SceneTree
## Headless match simulator. Plays full matches on the real Arena and RoundManager, many seeds, and
## reports invariant violations with a one-line repro command.
##
## It reads only public state and signals, so it keeps working while the rules change. Run it through
## tests/run_sim.sh. Env: SIM_SCENARIOS=a,b  SIM_SEEDS=N|a-b  SIM_QUICK=1   SIM_TRACE=seed  SIM_RULES=1.
## The GameFeel autoload is removed on purpose: slow-motion and hit-stop only stretch time.
## Time scaling is not used: it changes the physics outcome, so only real-step runs are valid.

const ARENA_SCENE: String = "res://scenes/arena.tscn"
const RulesChecks: GDScript = preload("res://tests/sim/rules_checks.gd")

const STEP: float = 1.0 / 60.0
const SPIKE_CHANCE: float = 0.004
const SPIKE_RATES: Array[int] = [15, 10]
const GATHER_SETTLE_SECONDS: float = 1.0
const STALL_SECONDS: float = 20.0
const PROGRESS_PIXELS: float = 15.0
const ROUND_CAP_SECONDS: float = 120.0
const MATCH_CAP_SECONDS: float = 900.0
const STUCK_WINDOW_SECONDS: float = 5.0
const STUCK_PIXELS: float = 10.0
const OUT_OF_BOUNDS_SECONDS: float = 2.0
const OUT_OF_BOUNDS_MARGIN: float = 24.0
const COUNT_GRACE_FRAMES: int = 10
const DEFAULT_SEEDS: int = 30
const QUICK_SEEDS: int = 6
const LOPSIDED_SHARE: float = 0.85
const LOPSIDED_MIN_MATCHES: int = 20
const LOW_BUILD_RATE: float = 0.1
const SCRIPT_RELEASE_STEP: int = 12
const SCRIPT_RETRY_STEP: int = 130
const FUZZ_ACT_CHANCE: float = 0.05
const FUZZ_RETARGET_FRAMES: int = 45
const ENDLESS_FLIGHT_SECONDS: float = 6.0
const OUTSIDE_GRACE_FRAMES: int = 3

const SCENARIO_ORDER: Array[String] = ["bots", "idle_seat0", "idle_seat1", "script_seat0", "script_seat1", "fuzz_seat0", "fuzz_seat1", "hero_bots", "hero_fuzz_seat0", "hero_fuzz_seat1"]
const SCENARIOS: Dictionary = {
	"bots": {"human_team": -1, "mode": "none"},
	"idle_seat0": {"human_team": 0, "mode": "idle"},
	"idle_seat1": {"human_team": 1, "mode": "idle"},
	"script_seat0": {"human_team": 0, "mode": "script"},
	"script_seat1": {"human_team": 1, "mode": "script"},
	"fuzz_seat0": {"human_team": 0, "mode": "fuzz"},
	"fuzz_seat1": {"human_team": 1, "mode": "fuzz"},
	"hero_bots": {"human_team": -1, "mode": "none", "heroes": true, "spikes": true},
	"hero_fuzz_seat0": {"human_team": 0, "mode": "fuzz", "heroes": true, "spikes": true},
	"hero_fuzz_seat1": {"human_team": 1, "mode": "fuzz", "heroes": true, "spikes": true},
}
const PHASE_NAMES: Array[String] = ["COIN_FLIP", "TOPPLE", "SCATTER", "ROUND_END", "MATCH_END"]

var _stage: Node2D
var _arena: Arena
var _tuning: Tuning
var _manager: RoundManager
var _rules: RefCounted = RulesChecks.new()
var _rules_enabled: bool = false
var _trace_seed: int = -1
var _original_scheme: int = 0

var _scenario: String = ""
var _seed: int = 0
var _frame: int = 0
var _dt: float = 1.0 / 60.0
var _sim_time: float = 0.0
var _round_time: float = 0.0
var _since_progress: float = 0.0
var _match_over: bool = false
var _match_winner: int = -1
var _forced_round: bool = false
var _round_count: int = 0
var _signature: Array = []
var _sandal_mark: Dictionary = {}
var _out_of_bounds: Dictionary = {}
var _count_bad_frames: int = 0
var _stuck: Dictionary = {}
var _match_kinds: Dictionary = {}
var _next_trace: float = 0.0
var _script_step: int = -1
var _pass_hold_time: float = 0.0
var _pressed: Dictionary = {}
var _fuzz_target: Vector2 = Vector2.ZERO
var _fuzz_frames: int = 0
var _flight_time: Dictionary = {}
var _outside_frames: Dictionary = {}

var _stats: Dictionary = {}
var _scatter_clock: float = 0.0
var _gathered: bool = false
var _gather_streak: float = 0.0
var _examples: Array[Dictionary] = []
## Seconds without a flying sandal before a resting sandal that moves counts as shoved by a body.
const QUIET_SECONDS: float = 1.0
## Speed a resting sandal must leave rest with to count as shoved.
const SHOVE_SPEED: float = 20.0

var _total_violations: int = 0
var _zone_speeds: Dictionary = {}
var _last_flight_time: float = -100.0


func _initialize() -> void:
	_run_all()


func _run_all() -> void:
	var feel: Node = root.get_node_or_null("GameFeel")
	if feel != null:
		feel.free()
	_rules_enabled = OS.get_environment("SIM_RULES") == "1"
	var trace_text: String = OS.get_environment("SIM_TRACE")
	_trace_seed = int(trace_text) if trace_text != "" else -1
	await physics_frame
	_original_scheme = SettingsRef.scheme()
	SettingsRef.set_scheme(SettingsRef.SCHEME_AIM_STICK)
	var seeds: Array[int] = _seed_list()
	var started_ms: int = Time.get_ticks_msec()
	for scenario: String in _scenario_list():
		_stats[scenario] = _new_stats()
		for seed_value: int in seeds:
			await _run_match(scenario, seed_value)
		_check_scenario_level(scenario)
	SettingsRef.set_scheme(_original_scheme)
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	_print_report(float(Time.get_ticks_msec() - started_ms) / 1000.0)
	quit(1 if _total_violations > 0 else 0)


func _scenario_list() -> Array[String]:
	var wanted: String = OS.get_environment("SIM_SCENARIOS")
	var list: Array[String] = []
	if wanted == "":
		list.assign(SCENARIO_ORDER)
		return list
	for name: String in wanted.split(","):
		if SCENARIOS.has(name.strip_edges()):
			list.append(name.strip_edges())
	return list


func _seed_list() -> Array[int]:
	var text: String = OS.get_environment("SIM_SEEDS")
	var seeds: Array[int] = []
	if text.contains("-"):
		var parts: PackedStringArray = text.split("-")
		for value: int in range(int(parts[0]), int(parts[1]) + 1):
			seeds.append(value)
		return seeds
	var count: int = int(text) if text != "" else (QUICK_SEEDS if OS.get_environment("SIM_QUICK") == "1" else DEFAULT_SEEDS)
	if text != "" and count > 1000:
		seeds.append(count)
		return seeds
	if text != "" and count <= 0:
		return seeds
	for value: int in range(1, count + 1):
		seeds.append(value)
	return seeds


func _new_stats() -> Dictionary:
	return {
		"matches": 0, "ended": 0, "rounds": 0, "topple": 0, "build": 0, "wipe": 0, "forced": 0,
		"scatter": 0, "stalls": 0, "stuck": 0, "body_shoves": 0, "violations": 0, "wins": [0, 0],
		"gather_times": [], "round_counts": [], "human_stall_attack": 0, "human_stall_defence": 0,
	}


func _build_match(scenario: String) -> void:
	if _stage != null:
		root.remove_child(_stage)
		_stage.free()
	_stage = Node2D.new()
	root.add_child(_stage)
	_tuning = Tuning.load_default().duplicate() as Tuning
	_tuning.match_countdown = false
	_tuning.human_team = int((SCENARIOS[scenario] as Dictionary)["human_team"])
	_arena = (load(ARENA_SCENE) as PackedScene).instantiate() as Arena
	_arena.tuning = _tuning
	_stage.add_child(_arena)
	_manager = RoundManager.new()
	_manager.tuning = _tuning
	_manager.arena = _arena
	_manager.phase_changed.connect(_on_phase_changed)
	_manager.round_ended.connect(_on_round_ended)
	_manager.match_ended.connect(_on_match_ended)
	_stage.add_child(_manager)
	if bool((SCENARIOS[scenario] as Dictionary).get("heroes", false)):
		var roster: Array[HeroDef] = HeroRoster.all()
		_manager.heroes = [roster[_seed % roster.size()], roster[(_seed / roster.size()) % roster.size()]]
		_manager.start_match()


func _run_match(scenario: String, seed_value: int) -> void:
	_scenario = scenario
	_seed = seed_value
	seed(seed_value)
	_frame = 0
	_sim_time = 0.0
	_round_time = 0.0
	_since_progress = 0.0
	_match_over = false
	_match_winner = -1
	_forced_round = false
	_round_count = 0
	_signature = []
	_sandal_mark = {}
	_out_of_bounds = {}
	_count_bad_frames = 0
	_stuck = {}
	_match_kinds = {}
	_next_trace = 0.0
	_script_step = -1
	_pass_hold_time = 0.0
	_fuzz_frames = 0
	_flight_time = {}
	_build_match(scenario)
	var stats: Dictionary = _stats[scenario]
	stats["matches"] += 1
	while not _match_over and _sim_time < MATCH_CAP_SECONDS:
		await physics_frame
		_tick()
	_release_actions()
	if not _match_over:
		_violation("match_no_end", "no winner after %.0f s, scores %s" % [_sim_time, str(_manager.scores)], false)
	else:
		stats["ended"] += 1
		stats["wins"][_match_winner] += 1
		(stats["round_counts"] as Array).append(_round_count)


func _tick() -> void:
	_frame += 1
	_dt = 1.0 / float(Engine.physics_ticks_per_second)
	_sim_time += _dt
	_round_time += _dt
	_apply_scenario_stress()
	if _manager.phase == RoundManager.MATCH_END:
		return
	_drive_human()
	_check_finite()
	_check_guard_pass_through()
	_check_zone_displacement()
	_check_bounds()
	_check_counts()
	_check_custody()
	_check_stuck()
	_check_gather_time()
	_check_progress()
	if _trace_on():
		_trace()


## Hero scenarios force every ready power and drop single physics steps to 15 or 10 Hz, as a slow web frame does.
func _apply_scenario_stress() -> void:
	var config: Dictionary = SCENARIOS[_scenario]
	Engine.physics_ticks_per_second = 60
	if bool(config.get("spikes", false)) and randf() < SPIKE_CHANCE:
		Engine.physics_ticks_per_second = SPIKE_RATES[randi() % SPIKE_RATES.size()]
	if not bool(config.get("heroes", false)):
		return
	for team: int in 2:
		for entry: Variant in _arena.get_characters(team):
			var member: Character = entry as Character
			if member != null and member.can_use_power():
				member.try_power()


func _trace_on() -> bool:
	return _trace_seed == _seed


func _human_role() -> int:
	var body: Character = _human_body()
	return int(body.role) if body != null else -1


func _human_body() -> Character:
	if _manager.human == null:
		return null
	var body: Character = _manager.human.character
	return body if body != null and is_instance_valid(body) else null


func _alive_count(team: int) -> int:
	var count: int = 0
	for entry: Variant in _arena.get_characters(team):
		var member: Character = entry as Character
		if member != null and member.alive:
			count += 1
	return count


func _live_sandals() -> Array[Sandal]:
	var found: Array[Sandal] = []
	for node: Node in get_nodes_in_group(Sandal.GROUP):
		var sandal: Sandal = node as Sandal
		if sandal != null and not sandal.is_queued_for_deletion():
			found.append(sandal)
	return found


func _violation(kind: String, detail: String, once_per_match: bool = true) -> void:
	if once_per_match and _match_kinds.has(kind):
		return
	_match_kinds[kind] = true
	_total_violations += 1
	(_stats[_scenario] as Dictionary)["violations"] += 1
	var repro: String = "SIM_SCENARIOS=%s SIM_SEEDS=%d-%d SIM_TRACE=%d bash tests/run_sim.sh" % [_scenario, _seed, _seed, _seed]
	var seen: int = 0
	for example: Dictionary in _examples:
		if example["scenario"] == _scenario and example["kind"] == kind:
			seen += 1
	if seen < 3:
		_examples.append({"scenario": _scenario, "kind": kind, "seed": _seed, "frame": _frame, "detail": detail, "repro": repro})


func _on_phase_changed(phase: int) -> void:
	if phase == RoundManager.SCATTER:
		(_stats[_scenario] as Dictionary)["scatter"] += 1
		_scatter_clock = 0.0
		_gather_streak = 0.0
		_gathered = false
	_stuck.clear()


func _on_match_ended(winner_team: int) -> void:
	_match_over = true
	_match_winner = winner_team


func _on_round_ended(winner_team: int) -> void:
	var stats: Dictionary = _stats[_scenario]
	stats["rounds"] += 1
	_round_count += 1
	var kind: String = "forced"
	if not _forced_round:
		if not _arena.stack.is_down:
			kind = "topple"
		elif winner_team == _manager.attacking_team:
			kind = "build"
		else:
			kind = "wipe"
	stats[kind] += 1
	if _rules_enabled:
		for message: String in _rules.on_round_ended(_manager, _arena, _tuning, winner_team, kind):
			_violation("rule:" + message.get_slice(":", 0), message, false)
	_forced_round = false
	_round_time = 0.0
	_since_progress = 0.0


## Records the seconds from the topple until all three sandals have stayed in the build zone for
## GATHER_SETTLE_SECONDS. Toppled sandals start in the zone, so the settle time shows the ones a hit flung out.
func _check_gather_time() -> void:
	if _manager.phase != RoundManager.SCATTER or _gathered:
		return
	_scatter_clock += _dt
	if _arena.stack.zone_sandals().size() + _arena.stack.placed_count >= _tuning.stack_size:
		_gather_streak += _dt
	else:
		_gather_streak = 0.0
	if _gather_streak >= GATHER_SETTLE_SECONDS:
		_gathered = true
		((_stats[_scenario] as Dictionary)["gather_times"] as Array).append(_scatter_clock)


func _median(values: Array) -> float:
	if values.is_empty():
		return -1.0
	var sorted: Array = values.duplicate()
	sorted.sort()
	return float(sorted[sorted.size() / 2])


func _check_finite() -> void:
	for sandal: Sandal in _live_sandals():
		if not (sandal.global_position.is_finite() and sandal.linear_velocity.is_finite()):
			_violation("nan_sandal", "sandal %s position %s velocity %s" % [sandal.name, str(sandal.global_position), str(sandal.linear_velocity)])
	for team: int in 2:
		for entry: Variant in _arena.get_characters(team):
			var member: Character = entry as Character
			if member != null and not (member.global_position.is_finite() and member.velocity.is_finite()):
				_violation("nan_character", "team %d %s position %s" % [team, member.name, str(member.global_position)])


## A resting sandal never starts to move on its own. One that jumps from rest, with no flying
## sandal for QUIET_SECONDS and none touching it, was shoved by a body.
func _check_zone_displacement() -> void:
	for sandal: Sandal in _live_sandals():
		if sandal.in_flight:
			_last_flight_time = _sim_time
	var quiet: bool = _sim_time - _last_flight_time > QUIET_SECONDS
	var seen: Dictionary = {}
	for sandal: Sandal in _live_sandals():
		if sandal.is_pass_sandal or sandal.freeze or sandal.in_flight:
			continue
		var id: int = sandal.get_instance_id()
		var speed: float = sandal.linear_velocity.length()
		seen[id] = speed
		if not quiet or _manager.phase != RoundManager.SCATTER or not _zone_speeds.has(id):
			continue
		if float(_zone_speeds[id]) < 1.0 and speed > SHOVE_SPEED and not _touches_other_sandal(sandal) and sandal.get_parent() == _arena:
			(_stats[_scenario] as Dictionary)["body_shoves"] += 1
			_violation("defender_body_shove", "sandal at %s left rest at %.0f px/s with no throw in flight" % [str(sandal.global_position), speed])
	_zone_speeds = seen


func _touches_other_sandal(sandal: Sandal) -> bool:
	for other: Sandal in _live_sandals():
		if other != sandal and other.global_position.distance_to(sandal.global_position) < _tuning.sandal_radius * 2.0 + 8.0:
			return true
	return false


func _check_guard_pass_through() -> void:
	for sandal: Sandal in _live_sandals():
		if not sandal.is_pass_sandal or not sandal.in_flight:
			continue
		for entry: Variant in _arena.get_characters(_manager.attacking_team):
			var guard: Character = entry as Character
			if guard == null or not guard.alive or guard.guard_stun_left <= 0.0:
				continue
			if sandal.global_position.distance_to(guard.global_position) < guard.get_body_radius() - 2.0:
				_violation("guard_pass_through", "pass sandal at %s inside blocking guard %s" % [str(sandal.global_position), guard.name])


func _check_bounds() -> void:
	var half: Vector2 = _tuning.arena_half_extents + Vector2.ONE * OUT_OF_BOUNDS_MARGIN
	var live: Dictionary = {}
	for sandal: Sandal in _live_sandals():
		var offset: Vector2 = sandal.global_position - _arena.centre_spot
		var id: int = sandal.get_instance_id()
		if absf(offset.x) > half.x or absf(offset.y) > half.y:
			live[id] = float(_out_of_bounds.get(id, 0.0)) + _dt
			if float(live[id]) > OUT_OF_BOUNDS_SECONDS:
				_violation("sandal_out_of_bounds", "sandal at %s for over %.0f s" % [str(sandal.global_position), OUT_OF_BOUNDS_SECONDS])
	_out_of_bounds = live


func _check_counts() -> void:
	var expected: int = _tuning.stack_size
	var bad: String = ""
	var loose_normal: int = 0
	var pass_count: int = 0
	for sandal: Sandal in _live_sandals():
		if sandal.is_pass_sandal:
			pass_count += 1
		elif sandal.is_placed:
			continue
		elif sandal.get_parent() == _arena.stack or _manager.phase == RoundManager.SCATTER:
			loose_normal += 1
	if pass_count > 1:
		bad = "%d pass sandals" % pass_count
	elif _manager.phase == RoundManager.TOPPLE and not _arena.stack.is_down and _arena.stack.standing_sandals.size() != expected:
		bad = "%d standing stack sandals, expected %d" % [_arena.stack.standing_sandals.size(), expected]
	elif _manager.phase == RoundManager.SCATTER and _arena.stack.is_down and loose_normal + _arena.stack.placed_count != expected:
		bad = "%d sandals in play plus %d placed, expected %d in total" % [loose_normal, _arena.stack.placed_count, expected]
	_count_bad_frames = _count_bad_frames + 1 if bad != "" else 0
	if _count_bad_frames == COUNT_GRACE_FRAMES:
		_violation("sandal_count", bad + " in " + PHASE_NAMES[_manager.phase] + ". " + _describe())


func _has_free_sandal() -> bool:
	for entry: Variant in _arena.get_loose_sandals():
		var sandal: Sandal = entry as Sandal
		if sandal == null or sandal.is_pass_sandal:
			continue
		# A delivered sandal needs no carrier, so an attacker that waits for the last delivery has no work.
		if _arena.stack.is_down and _arena.stack.is_in_zone(sandal.global_position):
			continue
		return true
	return false


func _has_work(member: Character) -> bool:
	if _manager.phase != RoundManager.SCATTER or member.frozen:
		return false
	if member.role == Character.Role.ATTACKER:
		if not _arena.stack.is_down:
			return false
		if member.is_building():
			return false
		if member.carried != null:
			return not _arena.stack.is_in_zone(member.global_position)
		if _arena.stack.can_build():
			return not _arena.stack.is_in_zone(member.global_position)
		return _has_free_sandal()
	if member.carried != null and member.carried.is_pass_sandal:
		return false
	return member.move_intent.length() > 0.1


func _check_stuck() -> void:
	var human: Character = _human_body()
	for team: int in 2:
		for entry: Variant in _arena.get_characters(team):
			var member: Character = entry as Character
			if member == null or not member.alive or member == human:
				continue
			var id: int = member.get_instance_id()
			if not _stuck.has(id):
				_stuck[id] = {"pos": member.global_position, "time": 0.0, "work": true}
			var record: Dictionary = _stuck[id]
			record["time"] = float(record["time"]) + _dt
			record["work"] = bool(record["work"]) and _has_work(member)
			if float(record["time"]) < STUCK_WINDOW_SECONDS:
				continue
			var moved: float = (record["pos"] as Vector2).distance_to(member.global_position)
			if bool(record["work"]) and moved < STUCK_PIXELS:
				(_stats[_scenario] as Dictionary)["stuck"] += 1
				_violation("stuck_bot", "team %d %s role %d moved %.1f px in %.0f s, carrying %s, phase %s" % [team, member.name, member.role, moved, STUCK_WINDOW_SECONDS, str(member.carried != null), PHASE_NAMES[_manager.phase]], false)
			record["pos"] = member.global_position
			record["time"] = 0.0
			record["work"] = true


func _progress_signature() -> Array:
	return [_manager.phase, _manager.scores.duplicate(), _alive_count(0), _alive_count(1), _arena.stack.placed_count, _manager.throws_left, _arena.stack.is_down]


func _check_progress() -> void:
	var moved: bool = false
	var snapshot: Dictionary = {}
	var live: Array[Sandal] = _live_sandals()
	for sandal: Sandal in live:
		var id: int = sandal.get_instance_id()
		snapshot[id] = sandal.global_position
		if not _sandal_mark.has(id) or (_sandal_mark[id] as Vector2).distance_to(sandal.global_position) > PROGRESS_PIXELS:
			moved = true
	if snapshot.size() != _sandal_mark.size():
		moved = true
	var signature: Array = _progress_signature()
	if signature != _signature:
		moved = true
		_signature = signature
	if moved:
		_sandal_mark = snapshot
		_since_progress = 0.0
	else:
		_since_progress += _dt
	if _manager.phase == RoundManager.ROUND_END or _manager.phase == RoundManager.COIN_FLIP:
		return
	if _since_progress >= STALL_SECONDS:
		(_stats[_scenario] as Dictionary)["stalls"] += 1
		_record_human_stall()
		_violation("stall", "no progress for %.0f s. %s" % [STALL_SECONDS, _describe()], false)
		_force_round_end()
	elif _round_time >= ROUND_CAP_SECONDS:
		_violation("round_cap", "round ran %.0f s. %s" % [ROUND_CAP_SECONDS, _describe()], false)
		_force_round_end()


func _record_human_stall() -> void:
	var stats: Dictionary = _stats[_scenario]
	var role: int = _human_role()
	if role == int(Character.Role.ATTACKER):
		stats["human_stall_attack"] += 1
	elif role == int(Character.Role.DEFENDER):
		stats["human_stall_defence"] += 1


func _force_round_end() -> void:
	_forced_round = true
	_manager.end_round(1 - _manager.attacking_team)
	_forced_round = _manager.phase == RoundManager.ROUND_END and _forced_round


func _describe() -> String:
	var human: Character = _human_body()
	var human_text: String = "none"
	if human != null:
		human_text = "%s%s" % ["attacker" if human.role == Character.Role.ATTACKER else "defender", " holding sandal" if human.carried != null else ""]
	var sandals: Array[String] = []
	for sandal: Sandal in _live_sandals():
		sandals.append("(%.0f,%.0f v%.0f%s%s%s d%.1f)" % [sandal.global_position.x, sandal.global_position.y, sandal.linear_velocity.length(),
			" flying" if sandal.in_flight else "", " frozen" if sandal.freeze else "", " pass" if sandal.is_pass_sandal else "", sandal.linear_damp])
	return "phase %s, attacking team %d, human %s, throws_left %d, stack down %s placed %d, alive %d vs %d, scores %s, sandals %s" % [
		PHASE_NAMES[_manager.phase], _manager.attacking_team, human_text, _manager.throws_left,
		str(_arena.stack.is_down), _arena.stack.placed_count, _alive_count(0), _alive_count(1), str(_manager.scores), " ".join(sandals)]


func _trace() -> void:
	if _sim_time < _next_trace:
		return
	_next_trace = _sim_time + 1.0
	print("[trace seed %d] t=%03.0f %s" % [_seed, _sim_time, _describe()])
	var human: Character = _human_body()
	for team: int in 2:
		for entry: Variant in _arena.get_characters(team):
			var member: Character = entry as Character
			if member == null:
				continue
			var nearest: String = "-"
			var nearest_distance: float = INF
			for loose: Variant in _arena.get_loose_sandals():
				var sandal: Sandal = loose as Sandal
				if sandal != null and not sandal.is_pass_sandal:
					var distance: float = member.global_position.distance_to(sandal.global_position)
					if distance < nearest_distance:
						nearest_distance = distance
						nearest = "%.0fpx" % distance
			print("    team %d %-10s %s%s alive=%s pos=(%.0f,%.0f) intent=(%.2f,%.2f) carry=%s nearest_loose=%s centre=%.0fpx" % [
				team, member.name, "ATK" if member.role == Character.Role.ATTACKER else "DEF", " HUMAN" if member == human else "",
				str(member.alive), member.global_position.x, member.global_position.y, member.move_intent.x, member.move_intent.y,
				("pass" if member.carried.is_pass_sandal else "sandal") if member.carried != null else "no",
				nearest, member.global_position.distance_to(_arena.centre_spot)])


func _drive_human() -> void:
	var mode: String = String((SCENARIOS[_scenario] as Dictionary)["mode"])
	if mode != "script" and mode != "fuzz":
		return
	var body: Character = _human_body()
	if body == null or not body.alive:
		_release_actions()
		_script_step = -1
		return
	if mode == "fuzz":
		_fuzz(body)
	elif body.role == Character.Role.ATTACKER:
		_script_attacker(body)
	else:
		_script_defender(body)


## A human who throws, passes, hits, drops and walks at random, through the same character calls the input schemes use.
func _fuzz(body: Character) -> void:
	if _manager.phase == RoundManager.COIN_FLIP or _manager.phase == RoundManager.ROUND_END:
		_release_actions()
		return
	_fuzz_frames -= 1
	if _fuzz_frames <= 0:
		_fuzz_frames = FUZZ_RETARGET_FRAMES
		_fuzz_target = _arena.random_point(30.0)
		var pick: float = randf()
		if pick < 0.4:
			var loose: Array = _arena.get_loose_sandals()
			if not loose.is_empty():
				_fuzz_target = (loose[randi() % loose.size()] as Node2D).global_position
		elif pick < 0.6:
			_fuzz_target = _arena.centre_spot
	_walk(body, _fuzz_target, 6.0)
	if randf() < 0.01:
		body.dash()
	if body.carried == null or randf() > FUZZ_ACT_CHANCE:
		return
	var direction: Vector2 = Vector2.from_angle(randf() * TAU)
	var power: float = [0.0, 0.05, 0.2, 0.5, 1.0, randf()][randi() % 6]
	var mates: Array[Character] = []
	var foes: Array[Character] = []
	for team: int in 2:
		for entry: Variant in _arena.get_characters(team):
			var other: Character = entry as Character
			if other != null and other != body and other.alive:
				(mates if team == body.team else foes).append(other)
	match randi() % 6:
		0:
			body.throw_manual(direction, power)
		1:
			body.throw_sandal(direction, power)
		2:
			if not mates.is_empty():
				body.pass_to(mates[randi() % mates.size()])
		3:
			if not foes.is_empty():
				body.hit(foes[randi() % foes.size()])
		4:
			if _manager.phase == RoundManager.SCATTER:
				body.drop_carried(body.global_position)
		5:
			body.throw_manual(_arena.centre_spot - body.global_position, power)


## Every sandal is either held by exactly one living character, standing in the pyramid, or loose inside the walls.
func _check_custody() -> void:
	var holders: Dictionary = {}
	for team: int in 2:
		for entry: Variant in _arena.get_characters(team):
			var member: Character = entry as Character
			if member == null or member.carried == null or not is_instance_valid(member.carried):
				continue
			if not member.alive:
				_violation("dead_holder", "%s is dead and still holds a sandal" % member.name)
			var id: int = member.carried.get_instance_id()
			if holders.has(id):
				_violation("double_custody", "two characters hold one sandal at %s" % str(member.carried.global_position))
			holders[id] = member
	var half: Vector2 = _tuning.arena_half_extents
	var pass_count: int = 0
	var flying: Dictionary = {}
	for sandal: Sandal in _live_sandals():
		var id: int = sandal.get_instance_id()
		if sandal.is_pass_sandal:
			pass_count += 1
		var offset: Vector2 = sandal.global_position - _arena.centre_spot
		var outside_frames: int = int(_outside_frames.get(id, 0)) + 1 if absf(offset.x) > half.x or absf(offset.y) > half.y else 0
		_outside_frames[id] = outside_frames
		if outside_frames > OUTSIDE_GRACE_FRAMES:
			_violation("sandal_outside_walls", "sandal at %s, pass %s, held %s, flight %s, frozen %s, placed %s, parent %s, velocity %s, phase %s" % [str(sandal.global_position), str(sandal.is_pass_sandal), str(holders.has(id)), str(sandal.in_flight), str(sandal.freeze), str(sandal.is_placed), sandal.get_parent().name, str(sandal.linear_velocity), PHASE_NAMES[_manager.phase]])
		if sandal.freeze and not sandal.is_placed and not holders.has(id):
			_violation("sandal_limbo", "frozen sandal at %s that nobody holds, pass %s" % [str(sandal.global_position), str(sandal.is_pass_sandal)])
		if holders.has(id) and not sandal.freeze:
			_violation("held_but_free", "held sandal at %s is not frozen" % str(sandal.global_position))
		if not sandal.in_flight and not sandal.freeze and sandal.linear_damp <= 0.0:
			_violation("undamped_rest", "sandal at %s rests with no damping, speed %.0f" % [str(sandal.global_position), sandal.linear_velocity.length()])
		if sandal.in_flight:
			flying[id] = float(_flight_time.get(id, 0.0)) + _dt
			if float(flying[id]) > ENDLESS_FLIGHT_SECONDS:
				_violation("endless_flight", "sandal at %s flew %.0f s, speed %.0f" % [str(sandal.global_position), ENDLESS_FLIGHT_SECONDS, sandal.linear_velocity.length()])
	_flight_time = flying
	if _manager.phase == RoundManager.SCATTER and pass_count == 0 and _alive_count(1 - _manager.attacking_team) > 0:
		_violation("pass_sandal_missing", "no pass sandal in the scatter phase")


func _script_attacker(body: Character) -> void:
	if _manager.phase == RoundManager.TOPPLE:
		_release_actions()
		_script_throw(body)
		return
	_script_step = -1
	if _manager.phase != RoundManager.SCATTER:
		_release_actions()
		return
	var target: Vector2 = _arena.centre_spot
	var stop_radius: float = _tuning.place_radius * 0.4
	if body.carried == null:
		var best: float = INF
		for entry: Variant in _arena.get_loose_sandals():
			var sandal: Sandal = entry as Sandal
			if sandal == null or sandal.is_pass_sandal:
				continue
			var distance: float = body.global_position.distance_to(sandal.global_position)
			if distance < best:
				best = distance
				target = sandal.global_position
				stop_radius = 0.0
	_walk(body, target, stop_radius)


func _script_defender(body: Character) -> void:
	_release_actions()
	if _manager.phase != RoundManager.SCATTER or body.carried == null or not body.carried.is_pass_sandal:
		_pass_hold_time = 0.0
		return
	_pass_hold_time += _dt
	if _pass_hold_time < 1.0:
		return
	_pass_hold_time = 0.0
	for entry: Variant in _arena.get_characters(body.team):
		var mate: Character = entry as Character
		if mate != null and mate != body and mate.alive:
			body.pass_to(mate)
			return


func _script_throw(body: Character) -> void:
	var scheme: Variant = _manager.human.scheme
	var stick: Variant = scheme.get("stick") if scheme != null else null
	if stick == null or body.carried == null:
		_script_step = -1
		return
	if _script_step < 0:
		_script_step = 0
	var centre: Vector2 = stick.hit_centre()
	var radius: float = stick.hit_radius()
	var bearing: Vector2 = (_arena.centre_spot - body.global_position).normalized()
	if _script_step == 0:
		_touch(centre, true)
	elif _script_step <= 8:
		_drag(centre + bearing * radius * float(_script_step) / 8.0)
	elif _script_step == SCRIPT_RELEASE_STEP:
		_touch(centre + bearing * radius, false)
	_script_step += 1
	if _script_step >= SCRIPT_RETRY_STEP:
		_script_step = -1


func _touch(position: Vector2, pressed: bool) -> void:
	var event: InputEventScreenTouch = InputEventScreenTouch.new()
	event.index = 7
	event.position = position
	event.pressed = pressed
	root.push_input(event, true)


func _drag(position: Vector2) -> void:
	var event: InputEventScreenDrag = InputEventScreenDrag.new()
	event.index = 7
	event.position = position
	root.push_input(event, true)


func _walk(body: Character, target: Vector2, stop_radius: float) -> void:
	var offset: Vector2 = target - body.global_position
	var direction: Vector2 = Vector2.ZERO if offset.length() <= stop_radius else offset.normalized()
	_set_action(&"move_left", maxf(-direction.x, 0.0))
	_set_action(&"move_right", maxf(direction.x, 0.0))
	_set_action(&"move_up", maxf(-direction.y, 0.0))
	_set_action(&"move_down", maxf(direction.y, 0.0))


func _set_action(action: StringName, strength: float) -> void:
	if strength > 0.0:
		Input.action_press(action, strength)
		_pressed[action] = true
	elif _pressed.has(action):
		Input.action_release(action)
		_pressed.erase(action)


func _release_actions() -> void:
	for action: Variant in _pressed.keys():
		Input.action_release(action as StringName)
	_pressed.clear()


func _check_scenario_level(scenario: String) -> void:
	_scenario = scenario
	_seed = 0
	_frame = 0
	_match_kinds = {}
	var stats: Dictionary = _stats[scenario]
	var ended: int = int(stats["ended"])
	if scenario == "bots":
		if ended >= LOPSIDED_MIN_MATCHES:
			var share: float = float(maxi(stats["wins"][0], stats["wins"][1])) / float(ended)
			if share > LOPSIDED_SHARE:
				_violation("lopsided_winner", "one team won %.0f%% of %d bot-only matches, wins %s" % [share * 100.0, ended, str(stats["wins"])])
		var scatter: int = int(stats["scatter"])
		if scatter >= 10 and float(stats["build"]) / float(scatter) < LOW_BUILD_RATE:
			_violation("low_build_rate", "attackers built the stack in %d of %d scatter phases" % [stats["build"], scatter])


func _percent(part: int, whole: int) -> String:
	return "%3.0f%%" % (100.0 * float(part) / float(whole)) if whole > 0 else "  - "


func _print_report(seconds: float) -> void:
	print("")
	print("sim: %.0f s wall, seeds per scenario %d" % [seconds, _seed_list().size()])
	print("%-13s %5s %5s %6s %6s %5s %5s %6s %6s %6s %5s %5s %7s %7s %-13s %8s %8s %10s" % ["scenario", "match", "ended", "rounds", "topple", "build", "wipe", "forced", "scat", "build%", "stall", "stuck", "t0 win", "t1 win", "rounds/match", "gather s", "atk win%", "zone kicks"])
	for scenario: String in _scenario_list():
		var stats: Dictionary = _stats[scenario]
		var counts: Array = stats["round_counts"]
		var low: int = 0
		var high: int = 0
		var total: int = 0
		for value: Variant in counts:
			total += int(value)
		if not counts.is_empty():
			low = int(counts.min())
			high = int(counts.max())
		var average: float = float(total) / float(maxi(counts.size(), 1))
		print("%-13s %5d %5d %6d %6d %5d %5d %6d %6d %6s %5d %5d %7s %7s %d / %.1f / %d  %7.1f %8s %10d" % [
			scenario, stats["matches"], stats["ended"], stats["rounds"], stats["topple"], stats["build"], stats["wipe"], stats["forced"],
			stats["scatter"], _percent(int(stats["build"]), int(stats["scatter"])), stats["stalls"], stats["stuck"],
			_percent(int(stats["wins"][0]), int(stats["ended"])), _percent(int(stats["wins"][1]), int(stats["ended"])), low, average, high, _median(stats["gather_times"]), _percent(int(stats["build"]), int(stats["rounds"])), stats["body_shoves"]])
		if int(stats["human_stall_attack"]) + int(stats["human_stall_defence"]) > 0:
			print("    stalls with the human attacking %d, defending %d" % [stats["human_stall_attack"], stats["human_stall_defence"]])
	print("")
	if _examples.is_empty():
		print("sim: no violations")
		return
	print("sim: %d violations, first examples per class" % _total_violations)
	for example: Dictionary in _examples:
		print("  [%s] %s seed %d frame %d: %s" % [example["kind"], example["scenario"], example["seed"], example["frame"], example["detail"]])
		print("      repro: %s" % example["repro"])
