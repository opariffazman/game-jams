class_name DeadEndReport
extends RefCounted
## Prints the dead-end table of the pool: per floor, the non-fatal first shifts that leave an unwinnable room, grouped by cause.

## Prints one row per floor: first shifts, dead ends, the share, one column per cause, and dead ends with one gunman left.
static func print_table() -> void:
	print("floor  shifts  dead  share  shielded  shifts  fatal  other  lone")
	var started: int = Time.get_ticks_msec()
	for level: int in range(1, RoomGen.FINAL_FLOOR + 1):
		var total: int = 0
		var dead: int = 0
		var lone: int = 0
		var causes: Array[int] = [0, 0, 0, 0]
		for room: Dictionary in Pool.of_floor(level):
			var budget: int = int(room["par"]) + RoomGen.slack_for(level)
			for next: RoomState in DeadEnd.first_shifts(RoomState.from_room(room)):
				total += 1
				if DeadEnd.verdict(next, budget - 1, null, DeadEnd.OFFLINE_CAP) != DeadEnd.Verdict.DEAD:
					continue
				dead += 1
				lone += 1 if next.alive_count() == 1 else 0
				causes[DeadEnd.classify(next, budget - 1, null, DeadEnd.OFFLINE_CAP)] += 1
		print("%5s  %6d  %4d  %5.2f  %8d  %6d  %5d  %5d  %4d" % [
			"final" if level == RoomGen.FINAL_FLOOR else "F%d" % level, total, dead, float(dead) / maxi(total, 1),
			causes[0], causes[1], causes[2], causes[3], lone])
	_print_timing()
	print("table took %d ms" % (Time.get_ticks_msec() - started))


## Prints the slowest live detector call over every first-shift state of the pool, with the live node cap, and how many calls hit the cap.
static func _print_timing() -> void:
	var worst_ms: float = 0.0
	var worst_room: String = ""
	var unknown: int = 0
	var calls: int = 0
	for room: Dictionary in Pool.rooms():
		var budget: int = int(room["par"]) + RoomGen.slack_for(int(room["floor"]))
		for next: RoomState in DeadEnd.first_shifts(RoomState.from_room(room)):
			var started: int = Time.get_ticks_usec()
			var info: Dictionary = DeadEnd.analyze(next, budget - 1)
			var took: float = float(Time.get_ticks_usec() - started) / 1000.0
			calls += 1
			unknown += 1 if info["verdict"] == DeadEnd.Verdict.UNKNOWN else 0
			if took > worst_ms:
				worst_ms = took
				worst_room = str(room["id"])
	print("detector: %d calls, worst %.1f ms in %s, %d hit the cap of %d nodes" % [calls, worst_ms, worst_room, unknown, DeadEnd.NODE_CAP])
