class_name HeroRoster
extends RefCounted
## Loads the hero resources and picks heroes for a match.

const DIR: String = "res://data/heroes/"
const IDS: Array[StringName] = [&"kilat", &"tukang", &"perisai", &"lontar", &"tangkap"]

static var _cache: Dictionary = {}


## Returns the hero with [param id], or null when the file is missing.
static func get_hero(id: StringName) -> HeroDef:
	if _cache.has(id):
		return _cache[id]
	var path: String = DIR + String(id) + ".tres"
	var hero: HeroDef = load(path) as HeroDef if ResourceLoader.exists(path) else null
	_cache[id] = hero
	return hero


## Every hero that loads, in roster order.
static func all() -> Array[HeroDef]:
	var heroes: Array[HeroDef] = []
	for id: StringName in IDS:
		var hero: HeroDef = get_hero(id)
		if hero != null:
			heroes.append(hero)
	return heroes


## A hero picked by [param rng]. Mirror matches can occur.
static func random_hero(rng: RandomNumberGenerator) -> HeroDef:
	var heroes: Array[HeroDef] = all()
	if heroes.is_empty():
		return null
	return heroes[rng.randi() % heroes.size()]
