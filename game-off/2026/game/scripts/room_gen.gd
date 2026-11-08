class_name RoomGen
extends RefCounted
## Room gates and analysis. Pure: uses only RoomState, HotSwapRules, and Motifs, never the scene.

## Gate set index of the final room. Floors 1 to 4 use their own number.
const FINAL_FLOOR: int = 5
## Monte Carlo runs for the measured win rate stored in the pool.
const MEASURE_RUNS: int = 400
## Monte Carlo runs for the cheap screen before the full measure.
const SCREEN_RUNS: int = 60
## Margin above the win rate gate that the screen still lets through.
const SCREEN_MARGIN: float = 0.15
## Whole-cell moves tried per room in [method generate].
const CLIMB_STEPS: int = 500
## Share of the win rate gate the search aims for, so the measured rate has noise room.
const RATE_AIM: float = 0.85
## Starting annealing temperature, in win-rate units.
const ANNEAL_START: float = 0.04

## Gates per floor, indexed by floor - 1. max_rate is the highest random win rate, max_best the most best
## solutions, trap_share the share of pool rooms that need a greedy trap, dead_share the highest share of non-fatal first shifts
## that leave a room no longer winnable within the budget (1.0 is no cap), slack the swaps above par, guns
## and covers the count ranges, kinds the allowed [enum RoomState.Kind] values, events the allowed event types.
## The trap shares of F2 and F3 are targets: the pool generator reports the share it reached (see the README).
const GATES: Array[Dictionary] = [
	{"max_rate": 0.60, "max_best": 99, "trap_share": 0.0, "dead_share": 0.30, "slack": 2, "guns": Vector2i(3, 3), "covers": Vector2i(0, 0), "kinds": [RoomState.Kind.PISTOL], "events": []},
	{"max_rate": 0.40, "max_best": 3, "trap_share": 0.34, "dead_share": 0.40, "slack": 1, "guns": Vector2i(3, 4), "covers": Vector2i(0, 0), "kinds": [RoomState.Kind.PISTOL, RoomState.Kind.SHIELD], "events": ["jam"]},
	{"max_rate": 0.25, "max_best": 2, "trap_share": 0.67, "dead_share": 0.55, "slack": 1, "guns": Vector2i(5, 5), "covers": Vector2i(0, 0), "kinds": [RoomState.Kind.PISTOL, RoomState.Kind.SHIELD, RoomState.Kind.KNIFE], "events": ["jam", "advance"]},
	{"max_rate": 0.15, "max_best": 2, "trap_share": 1.0, "dead_share": 1.0, "slack": 0, "guns": Vector2i(5, 6), "covers": Vector2i(0, 0), "kinds": [RoomState.Kind.PISTOL, RoomState.Kind.SHIELD, RoomState.Kind.KNIFE], "events": ["jam", "advance", "reinforce"]},
	{"max_rate": 0.10, "max_best": 1, "trap_share": 1.0, "dead_share": 1.0, "slack": 0, "guns": Vector2i(5, 6), "covers": Vector2i(0, 0), "kinds": [RoomState.Kind.PISTOL, RoomState.Kind.SHIELD, RoomState.Kind.KNIFE], "events": ["jam", "advance", "reinforce"]},
]


## Returns the swap budget for a room whose gate set is [param gate_floor].
static func slack_for(gate_floor: int) -> int:
	return int(GATES[gate_floor - 1]["slack"])


## Returns the seed for today's date, so every player gets the same daily run.
static func daily_seed() -> int:
	var date: Dictionary = Time.get_date_dict_from_system()
	return int(date["year"]) * 10000 + int(date["month"]) * 100 + int(date["day"])


## Returns the share of [param runs] random valid-tap games that clear [param room] within [param budget] taps.
static func random_win_rate(room: Dictionary, budget: int, runs: int) -> float:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 1337
	var base: RoomState = RoomState.from_room(room)
	var wins: int = 0
	for run: int in runs:
		var state: RoomState = base.clone()
		for step: int in budget:
			var live: Array[int] = []
			for i: int in state.guns.size():
				if state.alive[i]:
					live.append(i)
			if HotSwapRules.resolve(state, live[rng.randi_range(0, live.size() - 1)]).hero_dead:
				break
			if state.alive_count() == 0:
				wins += 1
				break
	return float(wins) / float(runs)


## Returns how many distinct tap sequences of the minimum length clear [param room].
static func best_solution_count(room: Dictionary) -> int:
	var state: RoomState = RoomState.from_room(room)
	var par: int = HotSwapRules.solve(state).size()
	return 0 if par == 0 else int(_profile(state, par)["count"])


## Returns true when the tap that kills the most right now is on no optimal path.
static func greedy_trap(room: Dictionary) -> bool:
	var state: RoomState = RoomState.from_room(room)
	var par: int = HotSwapRules.solve(state).size()
	return par > 0 and _is_trap(state, _profile(state, par)["firsts"])


## Runs every gate for [param level]. Returns the metrics dictionary, or an empty one when a gate fails.
static func evaluate(room: Dictionary, level: int, runs: int) -> Dictionary:
	var gate: Dictionary = GATES[level - 1]
	var state: RoomState = RoomState.from_room(room)
	if _hero_starts_dead(room):
		return {}
	var par: int = HotSwapRules.solve(state).size()
	if par == 0 or _late_event_count(room, par) > 0:
		return {}
	var budget: int = par + int(gate["slack"])
	var max_rate: float = gate["max_rate"]
	if random_win_rate(room, budget, SCREEN_RUNS) > max_rate + SCREEN_MARGIN:
		return {}
	var profile: Dictionary = _profile(state, par)
	if int(profile["count"]) > int(gate["max_best"]):
		return {}
	var trap: bool = _is_trap(state, profile["firsts"])
	if not trap and float(gate["trap_share"]) >= 1.0:
		return {}
	var dead: float = DeadEnd.dead_share(room, budget)
	if dead > float(gate["dead_share"]) + 0.0001:
		return {}
	var rate: float = random_win_rate(room, budget, runs)
	if rate > max_rate:
		return {}
	return {"par": par, "rate": snappedf(rate, 0.001), "best": int(profile["count"]), "trap": trap, "dead": snappedf(dead, 0.001)}


## Builds one room for [param level] from [param motif], then moves pieces by whole cells while the gates get closer.
## Returns an empty dictionary when the room still fails a gate after [constant CLIMB_STEPS]. A room passes the trap gate when [param want_trap] is true.
## A non-null [param force] is the exact list of event types the room gets.
static func generate(rng: RandomNumberGenerator, level: int, motif: String, want_trap: bool, force: Variant = null) -> Dictionary:
	var gate: Dictionary = GATES[level - 1].duplicate()
	if force != null:
		gate["force"] = force
	var gun_range: Vector2i = gate["guns"]
	var cover_range: Vector2i = gate["covers"]
	var room: Dictionary = Motifs.build(rng, motif, rng.randi_range(gun_range.x, gun_range.y), rng.randi_range(cover_range.x, cover_range.y), gate)
	var need_trap: bool = want_trap or float(gate["trap_share"]) >= 1.0
	var score: float = _gap(room, level, need_trap)
	for step: int in CLIMB_STEPS:
		if score == 0.0:
			var info: Dictionary = evaluate(room, level, MEASURE_RUNS)
			if not info.is_empty() and (info["trap"] or not want_trap) and _mirror_keeps_par(room, int(info["par"])):
				room.merge(info)
				room["floor"] = level
				return room
		var next: Dictionary = Motifs.mutate(rng, room)
		if not Motifs.is_layout_valid(next):
			continue
		var next_score: float = _gap(next, level, need_trap)
		var temperature: float = ANNEAL_START * (1.0 - float(step) / CLIMB_STEPS) + 0.001
		if next_score <= score or rng.randf() < exp((score - next_score) / temperature):
			room = next
			score = next_score
	return {}


static func _profile(state: RoomState, par: int) -> Dictionary:
	var firsts: Array[int] = []
	var total: int = 0
	for tap: int in state.guns.size():
		var count: int = _count_from(state, tap, par)
		if count > 0:
			firsts.append(tap)
			total += count
	return {"count": total, "firsts": firsts}


static func _count_from(state: RoomState, tap: int, depth: int) -> int:
	if not state.alive[tap]:
		return 0
	var next: RoomState = state.clone()
	if HotSwapRules.resolve(next, tap).hero_dead:
		return 0
	if next.alive_count() == 0:
		return 1 if depth == 1 else 0
	if depth == 1:
		return 0
	var total: int = 0
	for follow: int in next.guns.size():
		total += _count_from(next, follow, depth - 1)
	return total


## Greedy means the survivable tap with the most kills. Ties go to the gunman nearest the hero.
static func _is_trap(state: RoomState, firsts: Array[int]) -> bool:
	return int(_trap_deficit(state, firsts)) == 0


## Returns 0 when the greedy tap is a trap, else how many kills the optimal taps trail the greedy tap by, plus one. A search gradient.
static func _trap_deficit(state: RoomState, firsts: Array[int]) -> int:
	var best_kills: int = -1
	var greedy: int = -1
	var optimal_kills: int = 0
	for tap: int in state.guns.size():
		if not state.alive[tap]:
			continue
		var next: RoomState = state.clone()
		var res: HotSwapRules.Resolution = HotSwapRules.resolve(next, tap)
		if res.hero_dead:
			continue
		var kills: int = res.kill_count()
		if tap in firsts:
			optimal_kills = maxi(optimal_kills, kills)
		var closer: bool = greedy >= 0 and state.guns[tap].distance_to(state.hero) < state.guns[greedy].distance_to(state.hero)
		if kills > best_kills or (kills == best_kills and closer):
			best_kills = kills
			greedy = tap
	if greedy < 0:
		return 9
	return 0 if greedy not in firsts else maxi(1, optimal_kills - best_kills + 1)


## Returns how many events fire after turn [param par], so a best solution never meets them.
static func _late_event_count(room: Dictionary, par: int) -> int:
	var count: int = 0
	for event: Dictionary in room.get("events", []):
		count += 1 if int(event["turn"]) > par else 0
	return count


## Returns true when the mirrored room has the same par. A reinforcement tie can break the symmetry.
static func _mirror_keeps_par(room: Dictionary, par: int) -> bool:
	return HotSwapRules.solve(RoomState.from_room(Rooms.mirror(room))).size() == par


static func _hero_starts_dead(room: Dictionary) -> bool:
	var hero: Vector2 = room["hero"]
	for cover: Rect2 in room["covers"]:
		if cover.has_point(hero):
			return true
	for gun_pos: Vector2 in room["guns"]:
		if gun_pos.distance_to(hero) <= HotSwapRules.HERO_RADIUS + HotSwapRules.BODY_RADIUS:
			return true
	return false


static func _gap(room: Dictionary, level: int, need_trap: bool) -> float:
	var state: RoomState = RoomState.from_room(room)
	var gate: Dictionary = GATES[level - 1]
	var par: int = HotSwapRules.solve(state).size()
	if par == 0:
		return 99.0
	var max_rate: float = gate["max_rate"]
	var rate: float = _exact_rate(state, par + int(gate["slack"]))
	var profile: Dictionary = _profile(state, par)
	var gap: float = maxf(0.0, rate - max_rate * RATE_AIM) + 0.3 * _late_event_count(room, par)
	gap += 0.1 * maxi(0, int(profile["count"]) - int(gate["max_best"]))
	if need_trap:
		gap += 0.05 * _trap_deficit(state, profile["firsts"])
	var dead_cap: float = gate["dead_share"]
	if dead_cap < 1.0:
		gap += 0.5 * maxf(0.0, DeadEnd.dead_share(room, par + int(gate["slack"])) - dead_cap)
	return gap


## Exact chance that uniformly random valid taps clear [param state] within [param budget] taps. A noise-free stand-in for [method random_win_rate] while searching.
static func _exact_rate(state: RoomState, budget: int) -> float:
	var live: Array[int] = []
	for i: int in state.guns.size():
		if state.alive[i]:
			live.append(i)
	var total: float = 0.0
	for tap: int in live:
		var next: RoomState = state.clone()
		if HotSwapRules.resolve(next, tap).hero_dead:
			continue
		if next.alive_count() == 0:
			total += 1.0
		elif budget > 1:
			total += _exact_rate(next, budget - 1)
	return total / live.size()
