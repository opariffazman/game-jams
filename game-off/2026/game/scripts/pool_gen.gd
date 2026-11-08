class_name PoolGen
extends RefCounted
## Builds data/pool.json offline: rooms that pass the gates of each floor, tagged and tabulated.

## Pooled rooms per floor, F1 to F4 then the final room. F3 is smaller because its win rate gate is slow to meet. The final room has more for the boss phases.
const ROOMS_PER_FLOOR: Array[int] = [40, 40, 30, 40, 28]
## Seconds of generation time for floors 1 to 4 and the final room, before a floor settles for fewer rooms.
const FLOOR_SECONDS: Array[float] = [6.0, 35.0, 100.0, 45.0, 60.0]
## Share of a floor's time spent first on greedy-trap rooms.
const TRAP_TIME_SHARE: float = 0.5
## Event lists forced on the first final-room attempts: jam plus advance for boss phase 3, a turn 1 reinforcement for phase 2, then plain rooms for phase 1.
const FINAL_QUOTAS: Array[Array] = [["jam", "advance"], ["jam", "advance"], ["jam", "advance"], ["jam", "advance"], ["jam", "advance"], ["jam", "advance"], ["reinforce"], ["reinforce"], ["reinforce"], ["reinforce"], ["reinforce"], [], [], [], []]
## Largest share of a floor one motif can fill, until half the time is spent.
const MOTIF_CAP: float = 0.4


## Generates every floor, writes [constant Pool.PATH], prints the per-floor table, and returns the room count.
static func write_all() -> int:
	var started: int = Time.get_ticks_msec()
	var out: Array = []
	var all: Array[Dictionary] = []
	for level: int in range(1, RoomGen.FINAL_FLOOR + 1):
		var rooms: Array[Dictionary] = _fill_floor(level, ROOMS_PER_FLOOR[level - 1])
		all.append_array(rooms)
	for room: Dictionary in all:
		out.append(Rooms.to_json(room))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(Pool.PATH).get_base_dir())
	var file: FileAccess = FileAccess.open(Pool.PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(out))
	file.close()
	print_table(all)
	print_kind_table(all)
	print("generated %d rooms in %d ms" % [all.size(), Time.get_ticks_msec() - started])
	return all.size()


## Prints one row per floor: room count, mean random win rate, mean best-solution count, greedy-trap share, mean dead-end share, the gates, motif counts.
static func print_table(rooms: Array[Dictionary]) -> void:
	print("floor  rooms  win_rate  best  trap  dead   gate(rate/best/trap/dead)   motifs")
	for level: int in range(1, RoomGen.FINAL_FLOOR + 1):
		var count: int = 0
		var rate: float = 0.0
		var best: float = 0.0
		var traps: int = 0
		var dead: float = 0.0
		var motifs: Dictionary = {}
		for room: Dictionary in rooms:
			if int(room["floor"]) != level:
				continue
			count += 1
			rate += float(room["rate"])
			best += float(room["best"])
			traps += 1 if bool(room["trap"]) else 0
			dead += float(room["dead"])
			motifs[room["motif"]] = int(motifs.get(room["motif"], 0)) + 1
		if count == 0:
			print("%5d  none" % level)
			continue
		var gate: Dictionary = RoomGen.GATES[level - 1]
		print("%5s  %5d  %8.3f  %4.2f  %4.2f  %4.2f   <=%.2f/<=%d/>=%.2f/<=%.2f   %s" % [
			"final" if level == RoomGen.FINAL_FLOOR else "F%d" % level, count, rate / count, best / count,
			float(traps) / count, dead / count, gate["max_rate"], gate["max_best"], gate["trap_share"], gate["dead_share"], JSON.stringify(motifs)])


## Prints one row per floor with the share of rooms that hold each gunman type and each event type.
static func print_kind_table(rooms: Array[Dictionary]) -> void:
	print("floor  pistol  shield  knife   jam  advance  reinforce  events(0/1/2)")
	for level: int in range(1, RoomGen.FINAL_FLOOR + 1):
		var count: int = 0
		var seen: Dictionary = {}
		var per_count: Array[int] = [0, 0, 0]
		for room: Dictionary in rooms:
			if int(room["floor"]) != level:
				continue
			count += 1
			var kinds: Array = room.get("kinds", [])
			for kind: int in 3:
				if kind in kinds:
					seen[kind] = int(seen.get(kind, 0)) + 1
			var events: Array = room.get("events", [])
			per_count[mini(events.size(), 2)] += 1
			var types: Array[String] = []
			for event: Dictionary in events:
				if event["type"] not in types:
					types.append(event["type"])
			for type: String in types:
				seen[type] = int(seen.get(type, 0)) + 1
		if count == 0:
			continue
		print("%5s  %6.2f  %6.2f  %5.2f  %4.2f  %7.2f  %9.2f  %d/%d/%d" % [
			"final" if level == RoomGen.FINAL_FLOOR else "F%d" % level,
			float(seen.get(RoomState.Kind.PISTOL, 0)) / count, float(seen.get(RoomState.Kind.SHIELD, 0)) / count,
			float(seen.get(RoomState.Kind.KNIFE, 0)) / count, float(seen.get("jam", 0)) / count,
			float(seen.get("advance", 0)) / count, float(seen.get("reinforce", 0)) / count,
			per_count[0], per_count[1], per_count[2]])


static func _fill_floor(level: int, target: int) -> Array[Dictionary]:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7000 + level
	var trap_target: int = ceili(target * float(RoomGen.GATES[level - 1]["trap_share"]))
	var rooms: Array[Dictionary] = []
	var motifs: Dictionary = {}
	var traps: int = 0
	var attempts: int = 0
	var names: Array[String] = Motifs.names_for(level)
	var started: int = Time.get_ticks_msec()
	var budget_ms: int = int(FLOOR_SECONDS[level - 1] * 1000.0)
	var quota: int = 0
	while rooms.size() < target and Time.get_ticks_msec() - started < budget_ms:
		attempts += 1
		var elapsed: int = Time.get_ticks_msec() - started
		var motif: String = names[rng.randi_range(0, names.size() - 1)]
		if elapsed < budget_ms / 2 and int(motifs.get(motif, 0)) >= ceili(target * MOTIF_CAP):
			continue
		# Trap rooms are rare for the middle floors, so they get the first part of the time.
		var want_trap: bool = traps < trap_target and elapsed < budget_ms * TRAP_TIME_SHARE
		var forced: Variant = null
		if level == RoomGen.FINAL_FLOOR and quota < FINAL_QUOTAS.size():
			forced = FINAL_QUOTAS[quota]
			if motif == "reinforced_crossfire":
				continue
		var room: Dictionary = RoomGen.generate(rng, level, motif, want_trap, forced)
		if room.is_empty():
			continue
		quota += 1 if forced != null else 0
		traps += 1 if bool(room["trap"]) else 0
		motifs[motif] = int(motifs.get(motif, 0)) + 1
		room["id"] = "f%d-%03d" % [level, rooms.size()]
		rooms.append(room)
	if rooms.size() < target:
		printerr("floor %d: only %d of %d rooms after %d attempts" % [level, rooms.size(), target, attempts])
	else:
		print("floor %d: %d rooms from %d attempts in %d ms" % [level, rooms.size(), attempts, Time.get_ticks_msec() - started])
	return rooms
