class_name DeadEnd
extends RefCounted
## Dead-end analysis: can a room still be won within the shifts left, and if not, why. Pure.
## It replays [method HotSwapRules.resolve], so it never copies a rule.

## Answer of a win search.
enum Verdict { WIN, DEAD, UNKNOWN }
## Why a dead end is a dead end. Ordered by the check that runs first.
enum Cause { SHIELDED, SHIFTS, FATAL, OTHER }

## Resolve calls the live detector may spend before it reports [constant Verdict.UNKNOWN].
const NODE_CAP: int = 20000
## Resolve calls the generator and the table may spend on one search.
const OFFLINE_CAP: int = 400000
## Shifts added on top of the shifts left when the classifier asks whether more shifts would win.
const EXTRA_SHIFTS: int = 3
## Banner reason line per [enum Cause].
const REASONS: Array[String] = [
	"Every gunman left is shielded or behind cover." if Rooms.COVER_ENABLED else "Every gunman left is shielded.",
	"Not enough shifts left to finish.",
	"Every shift left gets you shot or stabbed.",
	"No shift from here wins the room.",
]
## Short name per [enum Cause] for the table.
const CAUSE_NAMES: Array[String] = ["shielded", "shifts", "fatal", "other"]


## Search bookkeeping: resolve calls spent, the cap, whether the cap stopped the search, and states already proven lost.
class Search:
	extends RefCounted
	## Boons the hero owns.
	var boons: BoonSet
	## Resolve calls spent so far.
	var nodes: int = 0
	## Resolve calls allowed.
	var cap: int = 0
	## True once the cap stopped a branch, so a lost branch is unproven.
	var capped: bool = false
	## State key to the most shifts left with which that state is proven lost.
	var lost: Dictionary = {}


## Returns whether [param state] can be won within [param shifts_left] shifts, spending at most [param node_cap] resolve calls.
## Returns [constant Verdict.UNKNOWN] when the cap hit before a win or a full proof.
static func verdict(state: RoomState, shifts_left: int, boons: BoonSet = null, node_cap: int = NODE_CAP) -> Verdict:
	if state.alive_count() == 0:
		return Verdict.WIN
	if shifts_left <= 0:
		return Verdict.DEAD
	var search: Search = Search.new()
	search.boons = boons
	search.cap = node_cap
	if _wins(state, shifts_left, search):
		return Verdict.WIN
	return Verdict.UNKNOWN if search.capped else Verdict.DEAD


## Returns the cause of a dead end. [param state] must be a dead end for [param shifts_left].
static func classify(state: RoomState, shifts_left: int, boons: BoonSet = null, node_cap: int = NODE_CAP) -> Cause:
	var fatal: int = 0
	var open: int = 0
	var progress: bool = false
	for tap: int in state.guns.size():
		if not state.alive[tap]:
			continue
		var next: RoomState = state.clone()
		var res: HotSwapRules.Resolution = HotSwapRules.resolve(next, tap, boons)
		if res.hero_dead:
			fatal += 1
			continue
		open += 1
		progress = progress or res.kill_count() > 0
	if open == 0:
		return Cause.FATAL
	if not progress:
		return Cause.SHIELDED
	if verdict(state, shifts_left + EXTRA_SHIFTS, boons, node_cap) == Verdict.WIN:
		return Cause.SHIFTS
	return Cause.FATAL if fatal * 2 >= fatal + open else Cause.OTHER


## Returns a dictionary with [code]verdict[/code] and, for a dead end, [code]cause[/code] and [code]reason[/code].
static func analyze(state: RoomState, shifts_left: int, boons: BoonSet = null, node_cap: int = NODE_CAP) -> Dictionary:
	var answer: Verdict = verdict(state, shifts_left, boons, node_cap)
	var out: Dictionary = {"verdict": answer}
	if answer == Verdict.DEAD:
		var cause: Cause = classify(state, shifts_left, boons, node_cap)
		out["cause"] = cause
		out["reason"] = REASONS[cause]
	return out


## Returns the first shifts of [param state] that do not kill the hero, each as the state it leaves, skipping rooms already won.
static func first_shifts(state: RoomState, boons: BoonSet = null) -> Array[RoomState]:
	var out: Array[RoomState] = []
	for tap: int in state.guns.size():
		if not state.alive[tap]:
			continue
		var next: RoomState = state.clone()
		if not HotSwapRules.resolve(next, tap, boons).hero_dead:
			out.append(next)
	return out


## Returns the share of non-fatal first shifts of [param room] that leave a room no longer winnable within [param budget] shifts.
## A first shift that wins counts as open. An unproven search counts as open too, so the share never overstates.
static func dead_share(room: Dictionary, budget: int) -> float:
	var firsts: Array[RoomState] = first_shifts(RoomState.from_room(room))
	if firsts.is_empty():
		return 0.0
	var dead: int = 0
	for next: RoomState in firsts:
		if verdict(next, budget - 1, null, OFFLINE_CAP) == Verdict.DEAD:
			dead += 1
	return float(dead) / float(firsts.size())


static func _wins(state: RoomState, depth: int, search: Search) -> bool:
	for tap: int in state.guns.size():
		if not state.alive[tap]:
			continue
		if search.nodes >= search.cap:
			search.capped = true
			return false
		search.nodes += 1
		var next: RoomState = state.clone()
		if HotSwapRules.resolve(next, tap, search.boons).hero_dead:
			continue
		if next.alive_count() == 0:
			return true
		if depth == 1:
			continue
		var key: int = [next.hero, next.guns, next.alive, next.turn, next.coat_spent].hash()
		if int(search.lost.get(key, 0)) >= depth - 1:
			continue
		if _wins(next, depth - 1, search):
			return true
		if not search.capped:
			search.lost[key] = depth - 1
	return false
