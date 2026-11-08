class_name RunState
extends RefCounted
## One run up the tower: seed, position, hearts, tips, and the 12 rooms drawn from the pool. Pure data and logic, no scene.

## Rewards on the door screen.
enum Door { HEART, TIPS, ELITE, BOON }

## Rooms in a run.
const ROOM_COUNT: int = 12
## Rooms on each floor.
const ROOMS_PER_FLOOR: int = 3
## Hearts at the start of a run, before upgrades.
const START_HEARTS: int = 3
## Hearts the hero can hold above the starting count.
const HEART_CAP_ABOVE_START: int = 2
## Phases of the boss fight in the last room.
const BOSS_PHASES: int = 3
## Tips for each cleared room. The boss fight counts as one room.
const ROOM_TIPS: int = 3
## Tips for clearing the last room of a floor.
const FLOOR_TIPS: int = 15
## Tips for beating the boss.
const BOSS_TIPS: int = 50
## Tips from the tips door.
const TIPS_DOOR_REWARD: int = 10
## Tips for clearing an elite room.
const ELITE_REWARD: int = 25

## Seed that built the tower and picks the doors.
var seed: int = 0
## Room index, 0 to 11.
var room_index: int = 0
## Hearts left. Zero ends the run.
var hearts: int = START_HEARTS
## Most hearts the hero can hold in this run.
var max_hearts: int = START_HEARTS + HEART_CAP_ABOVE_START
## Bought [enum Upgrades.Id] values that apply to this run.
var upgrades: Array[int] = []
## Boss phase being fought, 1 to 3, in the last room.
var boss_phase: int = 1
## The three boss puzzles in phase order. The first one is also the last tower room.
var boss_rooms: Array[Dictionary] = []
## Tips earned in this run.
var tips: int = 0
## Owned [enum BoonSet.Boon] ids, in pick order.
var boons: Array[int] = []
## Best chain of this run, for the end recap.
var chain: ChainTracker = ChainTracker.new()
## Undos each room or boss phase starts with. A Locker upgrade or a boon can raise it.
var undos_per_room: int = 1
## Rooms of the tower, one per index.
var rooms: Array[Dictionary] = []
## Rooms cleared so far.
var rooms_cleared: int = 0
## True once the run ended, by death or by clearing the last room.
var over: bool = false
## True when the run ended by clearing the last room.
var won: bool = false


## Builds a run for [param run_seed] and draws its 12 rooms from the pool. [param owned] holds the bought upgrades.
func _init(run_seed: int, owned: Array = []) -> void:
	seed = run_seed
	upgrades.assign(owned)
	hearts = Upgrades.start_hearts(upgrades)
	max_hearts = hearts + HEART_CAP_ABOVE_START
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = run_seed
	var used: Array[String] = []
	var traps_on_floor: int = 0
	for i: int in ROOM_COUNT:
		var gate: int = gate_floor_of(i)
		var min_traps: int = floori(float(RoomGen.GATES[gate - 1]["trap_share"]) * ROOMS_PER_FLOOR)
		if i % ROOMS_PER_FLOOR == 0:
			traps_on_floor = 0
		var slots_left: int = ROOMS_PER_FLOOR - i % ROOMS_PER_FLOOR
		var avoid: Array[String] = []
		if i > 0:
			avoid.append(str(rooms[i - 1]["motif"]))
		var room: Dictionary = Pool.draw(rng, gate, used, avoid, min_traps - traps_on_floor >= slots_left)
		if room.is_empty():
			room = Pool.draw(rng, gate, used, [], false)
		if i == ROOM_COUNT - 1:
			boss_rooms = _draw_boss(rng, used, avoid)
			room = boss_rooms[0]
		traps_on_floor += 1 if bool(room.get("trap", false)) else 0
		used.append(str(room["id"]))
		rooms.append(room)


## Returns a fresh random seed that differs from [param previous].
static func new_seed(previous: int = 0) -> int:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	var fresh: int = rng.randi_range(1, SeedCode.MAX_SEED - 1)
	return fresh if fresh != previous else fresh + 1


## Returns the floor, 1 to 4, of room [param index].
static func floor_of(index: int) -> int:
	return floori(float(index) / ROOMS_PER_FLOOR) + 1


## Returns the gate set of room [param index]. The last room uses the final gate set.
static func gate_floor_of(index: int) -> int:
	return RoomGen.FINAL_FLOOR if index == ROOM_COUNT - 1 else floor_of(index)


## Returns the current floor.
func floor_now() -> int:
	return floor_of(room_index)


## Returns the room number on the current floor, 1 to 3.
func room_in_floor() -> int:
	return room_index % ROOMS_PER_FLOOR + 1


## Returns the current room. In the boss fight it is the puzzle of the current phase.
func current_room() -> Dictionary:
	return boss_rooms[boss_phase - 1] if is_last_room() else rooms[room_index]


## Returns true on the last room.
func is_last_room() -> bool:
	return room_index == ROOM_COUNT - 1


## Returns the swap budget of the current room: par plus the slack of its gate set, plus Spare Clip and Spare Slack.
func budget() -> int:
	var room: Dictionary = current_room()
	return int(room["par"]) + RoomGen.slack_for(int(room["floor"])) + (1 if BoonSet.Boon.SPARE_CLIP in boons else 0) + Upgrades.slack_bonus(upgrades, floor_now())


## Returns the owned boons as the set the simulation reads.
func boon_set() -> BoonSet:
	return BoonSet.from_owned(boons)


## Returns the boons the hero does not own yet, in id order. The boon screen draws its cards from them.
func unowned_boons() -> Array[int]:
	var out: Array[int] = []
	for boon: int in BoonSet.COUNT:
		if boon not in boons:
			out.append(boon)
	return out


## Adds [param boon] without moving. The Opening Choice uses it before the first room.
func add_boon(boon: int) -> void:
	if boon not in boons:
		boons.append(boon)


## Adds [param boon] and moves to the next room.
func take_boon(boon: int) -> void:
	add_boon(boon)
	room_index += 1


## Takes one heart. Returns true when none are left.
func lose_heart() -> bool:
	hearts = maxi(hearts - 1, 0)
	return hearts == 0


## Records a cleared room and pays its tips. Returns false after a boss phase that is not the last: the next phase starts.
func on_cleared() -> bool:
	if is_last_room() and boss_phase < BOSS_PHASES:
		boss_phase += 1
		return false
	rooms_cleared += 1
	tips += ROOM_TIPS
	if bool(current_room().get("elite", false)):
		tips += ELITE_REWARD
	if room_in_floor() == ROOMS_PER_FLOOR:
		tips += FLOOR_TIPS
	if is_last_room():
		tips += BOSS_TIPS
	return true


## Marks the run as ended.
func finish(did_win: bool) -> void:
	over = true
	won = did_win


## Returns the two different rewards of the door screen after the current room. They depend on the seed and the room.
func door_offers() -> Array[int]:
	var pool: Array[int] = [Door.HEART, Door.TIPS]
	if boons.size() < BoonSet.COUNT:
		pool.append(Door.BOON)
	if room_index + 1 < ROOM_COUNT - 1:
		pool.append(Door.ELITE)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed * 31 + room_index
	for i: int in range(pool.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var swap: int = pool[i]
		pool[i] = pool[j]
		pool[j] = swap
	return [pool[0], pool[1]]


## Applies [param door] and moves to the next room. The boon door moves on only after [method take_boon].
func apply_door(door: int) -> void:
	match door:
		Door.BOON:
			return
		Door.HEART:
			hearts = mini(hearts + 1, max_hearts)
		Door.TIPS:
			tips += TIPS_DOOR_REWARD
		Door.ELITE:
			_make_next_elite()
	room_index += 1


func _make_next_elite() -> void:
	var next: int = room_index + 1
	var gate: int = mini(gate_floor_of(next) + 1, RoomGen.FINAL_FLOOR)
	var used: Array[String] = []
	for room: Dictionary in rooms:
		used.append(str(room["id"]))
	var avoid: Array[String] = [str(rooms[room_index]["motif"])]
	if next + 1 < ROOM_COUNT:
		avoid.append(str(rooms[next + 1]["motif"]))
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed * 17 + next
	var room: Dictionary = Pool.draw(rng, gate, used, avoid, false)
	if room.is_empty():
		return
	room["elite"] = true
	rooms[next] = room


## Draws the three boss puzzles from the final gate set, none repeated: a plain room, one with a turn 1 reinforcement,
## one with a jam and an advance. A phase takes the closest room when the pool lacks an exact match.
func _draw_boss(rng: RandomNumberGenerator, used: Array[String], avoid: Array[String]) -> Array[Dictionary]:
	var scorers: Array[Callable] = [
		func(room: Dictionary) -> float: return -float(room["events"].size()) - (5.0 if str(room["motif"]) in avoid else 0.0),
		func(room: Dictionary) -> float: return _event_score(room, ["reinforce"], 1),
		func(room: Dictionary) -> float: return _event_score(room, ["jam", "advance"], 0)]
	var out: Array[Dictionary] = []
	for scorer: Callable in scorers:
		var room: Dictionary = Pool.pick_best(rng, RoomGen.FINAL_FLOOR, used, scorer)
		used.append(str(room["id"]))
		out.append(room)
	return out


## Scores [param room] for the boss: 10 per different wanted event type present, plus 5 when [param turn] is set and the first wanted event fires then.
func _event_score(room: Dictionary, wanted: Array[String], turn: int) -> float:
	var score: float = 0.0
	var seen: Array[String] = []
	for event: Dictionary in room["events"]:
		if event["type"] in wanted and event["type"] not in seen:
			seen.append(event["type"])
			score += 10.0 + (5.0 if turn > 0 and int(event["turn"]) == turn else 0.0)
	return score
