class_name Pool
extends RefCounted
## The room pool read from data/pool.json, and the per-run draw from it. Runs never generate rooms live.

## Pool file, written by [method PoolGen.write_all].
const PATH: String = "res://data/pool.json"

static var _cache: Array[Dictionary] = []


## Returns every pooled room. Reads the file once.
static func rooms() -> Array[Dictionary]:
	if _cache.is_empty():
		_cache = load_file(PATH)
	return _cache


## Reads a pool file and returns its rooms, or an empty array on any read error.
static func load_file(path: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not FileAccess.file_exists(path):
		return out
	var parser: JSON = JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK or not parser.data is Array:
		return out
	var items: Array = parser.data
	for item: Variant in items:
		var entry: Dictionary = item
		out.append(Rooms.from_json(entry))
	return out


## Returns the pooled rooms of gate set [param level].
static func of_floor(level: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for room: Dictionary in rooms():
		if int(room["floor"]) == level:
			out.append(room)
	return out


## Draws a room of gate set [param level] with [param rng]. Skips ids in [param used] and motifs in [param avoid].
## Prefers a greedy-trap room when [param need_trap]. A mirrored copy is possible. Returns an empty dictionary if the gate set has no room.
static func draw(rng: RandomNumberGenerator, level: int, used: Array[String], avoid: Array[String], need_trap: bool) -> Dictionary:
	var fresh: Array[Dictionary] = []
	for room: Dictionary in of_floor(level):
		if str(room["id"]) not in used and str(room["motif"]) not in avoid:
			fresh.append(room)
	var trapped: Array[Dictionary] = fresh.filter(func(room: Dictionary) -> bool: return bool(room["trap"]))
	var choices: Array[Dictionary] = trapped if need_trap and not trapped.is_empty() else fresh
	if choices.is_empty():
		return {}
	var pick: Dictionary = choices[rng.randi_range(0, choices.size() - 1)]
	return Rooms.mirror(pick) if rng.randf() < 0.5 else pick


## Returns the room of gate set [param level] with the highest [param scorer] value, skipping ids in [param used].
## Ties go to a random room. A mirrored copy is possible. Returns an empty dictionary if the gate set has no room.
static func pick_best(rng: RandomNumberGenerator, level: int, used: Array[String], scorer: Callable) -> Dictionary:
	var best: Array[Dictionary] = []
	var best_score: float = -INF
	for room: Dictionary in of_floor(level):
		if str(room["id"]) in used:
			continue
		var score: float = scorer.call(room)
		if score > best_score + 0.001:
			best_score = score
			best = [room]
		elif absf(score - best_score) <= 0.001:
			best.append(room)
	if best.is_empty():
		return {}
	var pick: Dictionary = best[rng.randi_range(0, best.size() - 1)]
	return Rooms.mirror(pick) if rng.randf() < 0.5 else pick
