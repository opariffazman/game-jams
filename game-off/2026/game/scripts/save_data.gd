class_name SaveData
extends RefCounted
## The persistent save in a JSON file: tips balance, best floor, owned upgrades, and the equipped coat.

## Default save file.
const DEFAULT_PATH: String = "user://save.json"

## Save file in use. Tests point it at a scratch file.
static var path: String = DEFAULT_PATH


## Returns a new save with no tips and no upgrades.
static func fresh() -> Dictionary:
	var owned: Array[int] = []
	return {"tips": 0, "best_floor": 0, "owned": owned, "coat": -1}


## Returns the save. A missing or corrupt file gives a fresh save. Unknown upgrade ids are dropped.
static func load_save() -> Dictionary:
	if not FileAccess.file_exists(path):
		return fresh()
	var parser: JSON = JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK or not parser.data is Dictionary:
		return fresh()
	var data: Dictionary = parser.data
	# The key stays "tips" though the player reads it as MONEY, so saves written before the rename keep working.
	if not (data.get("tips") is float and data.get("best_floor") is float):
		return fresh()
	var save: Dictionary = fresh()
	save["tips"] = maxi(int(data["tips"]), 0)
	save["best_floor"] = maxi(int(data["best_floor"]), 0)
	var raw_owned: Variant = data.get("owned")
	if raw_owned is Array:
		var listed: Array = raw_owned
		for item: Variant in listed:
			if item is float and int(item) >= 0 and int(item) < Upgrades.COUNT and int(item) not in save["owned"]:
				save["owned"].append(int(item))
	var coat: Variant = data.get("coat")
	if coat is float and Upgrades.is_style(int(coat)) and int(coat) in save["owned"]:
		save["coat"] = int(coat)
	return save


## Writes [param data] to the save file.
static func write(data: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data))
		file.close()


## Adds the tips of an ended run, raises the best floor, writes the file, and returns the new save.
static func record_run(floor_reached: int, run_tips: int) -> Dictionary:
	var data: Dictionary = load_save()
	data["tips"] = int(data["tips"]) + run_tips
	data["best_floor"] = maxi(int(data["best_floor"]), floor_reached)
	write(data)
	return data
