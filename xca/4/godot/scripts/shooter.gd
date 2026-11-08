class_name Shooter
extends Node
## Fires the current weapon on its own at the nearest zombie ahead in the hero's lane and the lanes next to it.
##
## The player only steers and cycles weapons, so the weapon is a shared inventory and a missed flick costs little.
## A gun hits at once, because the target is chosen by lane and distance and no ray is cast. The bat swings at close range.

## Emitted for every shot or swing, with the number of zombies it hit.
signal shot_fired(hits: int)
## Emitted when the current weapon changes.
signal weapon_changed(weapon: Dictionary)
## Emitted when a weapon joins or leaves the carried set.
signal carried_changed
## Emitted when any ammo count changes.
signal ammo_changed

## Sideways distance in metres that still counts as the hero's lane or a neighbour. Slightly over one lane step.
const LANE_REACH_X: float = 3.0
## Zombies closer than this in metres are out of a gun's reach and left to the bat.
const MIN_GUN_DISTANCE: float = 0.0
## Weapons the hero carries at once. Two come from the hero, so one slot is left for a pickup.
const MAX_CARRIED: int = 3

## Pool that is searched for targets.
@export var pool: ZombiePool
## Hero that holds the weapons.
@export var hero: RailsHero
## Director that knows the hero's sideways position.
@export var director: RailsDirector

## Whether weapons fire. The game turns this on after the start screen.
var active: bool = false
## Ids of the carried weapons, oldest first. The hero's loadout comes first and a pickup replaces the previous pickup, never the loadout.
var carried: Array[StringName] = []
## Index of the current weapon in the carried weapons.
var weapon_index: int = 0
## Total shots since start, for the readout.
var shots_fired: int = 0
## Total hits since start, for the readout.
var shots_hit: int = 0

## Dirt on the weapons. Dirt slows the fire rate.
var grime: WeaponGrime = WeaponGrime.new()

var _cooldown: float = 0.0
var _ammo: Dictionary = {}
var _loadout_size: int = 0


func _ready() -> void:
	set_loadout(HeroTable.loadout(HeroTable.DEFAULT_ID))


func _process(delta: float) -> void:
	grime.tick(delta)
	_cooldown = maxf(_cooldown - delta, 0.0)
	if not active or _cooldown > 0.0:
		return
	var weapon: Dictionary = get_weapon()
	if ammo_left(weapon) == 0:
		# An empty weapon falls back to the first weapon that never runs dry.
		set_weapon_index(_unlimited_index())
		return
	if bool(weapon["melee"]):
		_swing(weapon)
	else:
		_shoot(weapon)


## Replaces the carried weapons with a hero's starting loadout and fills their ammo.
func set_loadout(ids: Array[StringName]) -> void:
	carried = ids.duplicate()
	_loadout_size = carried.size()
	refill_ammo()
	carried_changed.emit()
	set_weapon_index(0)


## Adds a picked-up weapon. A weapon already carried only gets its ammo back. At the cap the previous pickup is replaced. Returns whether the carried set changed.
func add_weapon(id: StringName) -> bool:
	if carried.has(id):
		_fill(HeroTable.weapon_by_id(id))
		ammo_changed.emit()
		return false
	if carried.size() >= MAX_CARRIED:
		var gone: StringName = carried[MAX_CARRIED - 1]
		carried.remove_at(MAX_CARRIED - 1)
		_ammo.erase(gone)
	carried.append(id)
	_fill(HeroTable.weapon_by_id(id))
	carried_changed.emit()
	ammo_changed.emit()
	set_weapon_index(carried.size() - 1)
	return true


## Returns the current weapon spec.
func get_weapon() -> Dictionary:
	return HeroTable.weapon_by_id(carried[weapon_index])


## Returns the carried weapon specs in cycle order.
func get_carried() -> Array[Dictionary]:
	var specs: Array[Dictionary] = []
	for id: StringName in carried:
		specs.append(HeroTable.weapon_by_id(id))
	return specs


## Returns the rounds left of a weapon, or -1 when it is unlimited.
func ammo_left(weapon: Dictionary) -> int:
	if int(weapon["ammo"]) < 0:
		return -1
	return int(_ammo.get(weapon["id"], 0))


## Returns the lowest share of ammo left across the limited weapons, from 0 to 1.
func ammo_share() -> float:
	var lowest: float = 1.0
	for weapon: Dictionary in get_carried():
		if int(weapon["ammo"]) > 0:
			lowest = minf(lowest, float(ammo_left(weapon)) / float(weapon["ammo"]))
	return lowest


## Fills every limited weapon.
func refill_ammo() -> void:
	for weapon: Dictionary in get_carried():
		_fill(weapon)
	ammo_changed.emit()


## Returns the weapon one step from the current one, without switching to it.
func peek_weapon(direction: int) -> Dictionary:
	return HeroTable.weapon_by_id(carried[HeroTable.step_weapon(weapon_index, direction, carried.size())])


## Switches to the next (1) or previous (-1) weapon.
func cycle_weapon(direction: int) -> void:
	set_weapon_index(HeroTable.step_weapon(weapon_index, direction, carried.size()))


## Switches to a weapon by inventory index.
func set_weapon_index(index: int) -> void:
	weapon_index = posmod(index, carried.size())
	_cooldown = 0.0
	if hero != null:
		hero.set_weapon(get_weapon())
	weapon_changed.emit(get_weapon())


func _fill(weapon: Dictionary) -> void:
	if int(weapon["ammo"]) > 0:
		_ammo[weapon["id"]] = int(weapon["ammo"])


func _unlimited_index() -> int:
	for index: int in carried.size():
		if int(HeroTable.weapon_by_id(carried[index])["ammo"]) < 0:
			return index
	return 0


func _hero_x() -> float:
	return director.get_hero_x() if director != null else 0.0


## Returns the nearest zombie in reach, or null. Nearest means the smallest distance ahead.
func _nearest_target(reach: float) -> Zombie:
	var hero_x: float = _hero_x()
	var best: Zombie = null
	var best_distance: float = INF
	for zombie: Zombie in pool.get_zombies():
		if not zombie.is_targetable():
			continue
		var ahead: float = zombie.distance_ahead()
		if ahead < MIN_GUN_DISTANCE or ahead > reach:
			continue
		if absf(zombie.global_position.x - hero_x) > LANE_REACH_X:
			continue
		if ahead < best_distance:
			best_distance = ahead
			best = zombie
	return best


func _shoot(weapon: Dictionary) -> void:
	var target: Zombie = _nearest_target(float(weapon["range"]))
	if target == null:
		return
	var hits: int = 0
	var damage: int = int(weapon["damage"])
	var pellets: int = int(weapon["pellets"])
	var spread: float = float(weapon["spread"])
	if pellets <= 1:
		target.take_damage(damage)
		hits = 1
	else:
		var center: Vector3 = target.global_position
		var covered: Array[Zombie] = pool.find_in_radius(center, spread)
		for zombie: Zombie in covered:
			if hits >= pellets:
				break
			zombie.take_damage(damage)
			hits += 1
	if int(weapon["ammo"]) > 0:
		_ammo[weapon["id"]] = ammo_left(weapon) - 1
		ammo_changed.emit()
	_cooldown = float(weapon["fire_interval"]) * grime.interval_scale(StringName(weapon["id"]))
	_record(hits)


func _swing(weapon: Dictionary) -> void:
	var reach: float = float(weapon["swing_reach"])
	var target: Zombie = _nearest_target(reach)
	if target == null:
		return
	hero.play_swing()
	var hits: int = 0
	for zombie: Zombie in pool.get_zombies():
		if not zombie.is_targetable() or zombie.distance_ahead() > reach:
			continue
		if absf(zombie.global_position.x - _hero_x()) > LANE_REACH_X:
			continue
		zombie.take_damage(int(weapon["swing_damage"]))
		hits += 1
	_cooldown = float(weapon["swing_interval"]) * grime.interval_scale(StringName(weapon["id"]))
	_record(hits)


func _record(hits: int) -> void:
	grime.add_shot(StringName(get_weapon()["id"]))
	shots_fired += 1
	if hits > 0:
		shots_hit += 1
	shot_fired.emit(hits)
