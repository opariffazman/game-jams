class_name HighScores
extends RefCounted
## The local top runs by distance. It is saved with a ConfigFile in user://, which the web build keeps in the browser.

const FILE: String = "user://highscores.cfg"
const SECTION: String = "scores"
const KEY: String = "rows"
const CAPACITY: int = 5
const SECONDS_PER_DAY: int = 86400
const MONTHS: Array[String] = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]


## Returns the saved rows, best first. A row is {hero: String, metres: int, day: int}, where day counts days since 1970.
static func load_rows(path: String = FILE) -> Array[Dictionary]:
	var file := ConfigFile.new()
	var rows: Array[Dictionary] = []
	if file.load(path) != OK:
		return rows
	for entry: Variant in file.get_value(SECTION, KEY, []):
		if entry is Dictionary:
			rows.append({"hero": String(entry.get("hero", "")), "metres": int(entry.get("metres", 0)), "day": int(entry.get("day", 0))})
	return rows


## Adds a run, keeps the best CAPACITY and saves them. Returns the zero-based rank of the new run, or -1 when it misses the board.
## A run that ties an older one ranks below it, so the first run to reach a distance keeps the place.
static func insert(hero: String, metres: int, path: String = FILE, now_unix: int = -1) -> int:
	var rows: Array[Dictionary] = load_rows(path)
	var unix: int = int(Time.get_unix_time_from_system()) if now_unix < 0 else now_unix
	var rank: int = rows.size()
	for index: int in rows.size():
		if metres > int(rows[index]["metres"]):
			rank = index
			break
	if rank >= CAPACITY:
		return -1
	rows.insert(rank, {"hero": hero, "metres": metres, "day": unix / SECONDS_PER_DAY})
	rows.resize(mini(rows.size(), CAPACITY))
	var file := ConfigFile.new()
	file.set_value(SECTION, KEY, rows)
	file.save(path)
	return rank


## "today" for the current day, otherwise a short date such as "Nov 1".
static func day_label(day: int, now_unix: int = -1) -> String:
	var unix: int = int(Time.get_unix_time_from_system()) if now_unix < 0 else now_unix
	if day == unix / SECONDS_PER_DAY:
		return "today"
	var date: Dictionary = Time.get_date_dict_from_unix_time(day * SECONDS_PER_DAY)
	return "%s %d" % [MONTHS[int(date["month"]) - 1], int(date["day"])]
