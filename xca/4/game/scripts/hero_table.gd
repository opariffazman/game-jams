class_name HeroTable
extends RefCounted
## The playable looks and the shared weapon inventory. Scripts read these tables and never branch on a name.
##
## A hero is a look plus a starting loadout of one ranged and one melee weapon. The player cycles the carried weapons during the run and can pick up more.
##
## Hero fields:
##   id, name, role, trait  - texts and key, shown on the hero card.
##   model                  - glTF path.
##   hearts                 - lives of the hero.
##   accent                 - highlight colour, decoration only.
##   loadout                - weapon ids the hero starts with: the ranged weapon first, then the melee weapon.
##
## Weapon fields:
##   id, label              - key, and the name shown on the weapon HUD.
##   node                   - weapon node left visible on the hero model.
##   idle_clip, run_clip    - base clips. A gun is held in the gun pose, the bat is not.
##   melee                  - true means no gun: the hero swings at zombies that get close.
##   fire_interval          - seconds between shots.
##   pellets, spread        - zombies a shot can reach, and the metres around the target a blast covers.
##   damage                 - lives a hit takes.
##   range                  - metres ahead a shot reaches.
##   swing_clip, swing_damage, swing_reach - melee only. Reach is metres ahead of the hero.
##   ammo                   - rounds a full weapon holds. -1 means unlimited.
##   shot_sound             - sound played for a shot or swing.
##   swing_interval         - melee only. Seconds between two swings.
##   drop                   - true means the weapon can appear as a pickup in the level.
##   accent                 - HUD colour.

const DEFAULT_ID: StringName = &"lis"

const HEROES: Array[Dictionary] = [
	{
		"id": &"lis", "name": "Lis", "role": "Scout", "trait": "Light and quick.",
		"model": "res://assets/Characters_Lis.gltf", "hearts": 5, "accent": Color(0.3, 0.85, 0.8), "loadout": [&"pistol", &"knife"],
	},
	{
		"id": &"sam", "name": "Sam", "role": "Tinkerer", "trait": "Always ready.",
		"model": "res://assets/Characters_Sam.gltf", "hearts": 5, "accent": Color(1.0, 0.65, 0.2), "loadout": [&"smg", &"spear"],
	},
	{
		"id": &"shaun", "name": "Shaun", "role": "Rocker", "trait": "Loud and proud.",
		"model": "res://assets/Characters_Shaun.gltf", "hearts": 5, "accent": Color(0.45, 0.65, 1.0), "loadout": [&"rifle", &"guitar"],
	},
	{
		"id": &"matt", "name": "Matt", "role": "Bruiser", "trait": "Tough, one more heart.",
		"model": "res://assets/Characters_Matt.gltf", "hearts": 6, "accent": Color(1.0, 0.45, 0.5), "loadout": [&"shotgun", &"axe"],
	},
]

const GUN_IDLE: StringName = &"Idle_Gun"
const GUN_RUN: StringName = &"Run_Gun"

const WEAPONS: Array[Dictionary] = [
	{
		"id": &"pistol", "label": "Pistol", "node": &"Pistol", "idle_clip": GUN_IDLE, "run_clip": GUN_RUN,
		"melee": false, "fire_interval": 0.4, "pellets": 1, "spread": 0.0, "damage": 2, "range": 24.0, "ammo": -1,
		"swing_clip": &"", "swing_damage": 0, "swing_reach": 0.0, "swing_interval": 0.0,
		"shot_sound": &"shot_pistol", "drop": false, "accent": Color(0.3, 0.85, 0.8),
	},
	{
		"id": &"shotgun", "label": "Shotgun", "node": &"Shotgun", "idle_clip": GUN_IDLE, "run_clip": GUN_RUN,
		"melee": false, "fire_interval": 0.7, "pellets": 5, "spread": 2.0, "damage": 2, "range": 14.0, "ammo": 14,
		"swing_clip": &"", "swing_damage": 0, "swing_reach": 0.0, "swing_interval": 0.0,
		"shot_sound": &"shot_shotgun", "drop": true, "accent": Color(1.0, 0.65, 0.2),
	},
	{
		"id": &"smg", "label": "SMG", "node": &"SMG", "idle_clip": GUN_IDLE, "run_clip": GUN_RUN,
		"melee": false, "fire_interval": 0.12, "pellets": 1, "spread": 0.0, "damage": 1, "range": 16.0, "ammo": 70,
		"swing_clip": &"", "swing_damage": 0, "swing_reach": 0.0, "swing_interval": 0.0,
		"shot_sound": &"shot_smg", "drop": true, "accent": Color(0.45, 0.65, 1.0),
	},
	{
		"id": &"rifle", "label": "Rifle", "node": &"Rifle", "idle_clip": GUN_IDLE, "run_clip": GUN_RUN,
		"melee": false, "fire_interval": 0.55, "pellets": 1, "spread": 0.0, "damage": 3, "range": 30.0, "ammo": 30,
		"swing_clip": &"", "swing_damage": 0, "swing_reach": 0.0, "swing_interval": 0.0,
		"shot_sound": &"shot_pistol", "drop": true, "accent": Color(0.6, 0.9, 0.4),
	},
	{
		"id": &"bat", "label": "Bat", "node": &"WoodenBat_Barbed", "idle_clip": &"Idle", "run_clip": &"Run",
		"melee": true, "fire_interval": 0.0, "pellets": 0, "spread": 0.0, "damage": 0, "range": 0.0, "ammo": -1,
		"swing_clip": &"Run_Slash", "swing_damage": 4, "swing_reach": 3.5, "swing_interval": 0.55,
		"shot_sound": &"bat_swing", "drop": true, "accent": Color(1.0, 0.45, 0.5),
	},
	{
		"id": &"knife", "label": "Knife", "node": &"Knife", "idle_clip": &"Idle", "run_clip": &"Run",
		"melee": true, "fire_interval": 0.0, "pellets": 0, "spread": 0.0, "damage": 0, "range": 0.0, "ammo": -1,
		"swing_clip": &"Run_Stab", "swing_damage": 2, "swing_reach": 2.8, "swing_interval": 0.3,
		"shot_sound": &"bat_swing", "drop": true, "accent": Color(0.8, 0.9, 1.0),
	},
	{
		"id": &"axe", "label": "Axe", "node": &"Axe", "idle_clip": &"Idle", "run_clip": &"Run",
		"melee": true, "fire_interval": 0.0, "pellets": 0, "spread": 0.0, "damage": 0, "range": 0.0, "ammo": -1,
		"swing_clip": &"Run_Slash", "swing_damage": 5, "swing_reach": 3.2, "swing_interval": 0.85,
		"shot_sound": &"bat_swing", "drop": true, "accent": Color(1.0, 0.5, 0.25),
	},
	{
		"id": &"spear", "label": "Spear", "node": &"Spear", "idle_clip": &"Idle", "run_clip": &"Run",
		"melee": true, "fire_interval": 0.0, "pellets": 0, "spread": 0.0, "damage": 0, "range": 0.0, "ammo": -1,
		"swing_clip": &"Run_Stab", "swing_damage": 3, "swing_reach": 5.0, "swing_interval": 0.6,
		"shot_sound": &"bat_swing", "drop": true, "accent": Color(0.9, 0.8, 0.4),
	},
	{
		"id": &"guitar", "label": "Guitar", "node": &"Guitar", "idle_clip": &"Idle", "run_clip": &"Run",
		"melee": true, "fire_interval": 0.0, "pellets": 0, "spread": 0.0, "damage": 0, "range": 0.0, "ammo": -1,
		"swing_clip": &"Run_Slash", "swing_damage": 3, "swing_reach": 3.6, "swing_interval": 0.5,
		"shot_sound": &"bat_swing", "drop": true, "accent": Color(0.9, 0.4, 0.9),
	},
]

static var _by_id: Dictionary[StringName, Dictionary] = {}


## Returns the weapon with an id, or the pistol for an unknown id.
static func weapon_by_id(id: StringName) -> Dictionary:
	if _by_id.is_empty():
		for weapon: Dictionary in WEAPONS:
			_by_id[weapon["id"]] = weapon
	return _by_id.get(id, WEAPONS[0])


## Returns the starting weapon ids of a hero, ranged first.
static func loadout(hero_id: StringName) -> Array[StringName]:
	var ids: Array[StringName] = []
	for id: StringName in get_spec(hero_id)["loadout"]:
		ids.append(id)
	return ids


## Returns the spec of a hero, or the default hero for an unknown id.
static func get_spec(id: StringName) -> Dictionary:
	for spec: Dictionary in HEROES:
		if spec["id"] == id:
			return spec
	return HEROES[0]


## Returns the index of a hero in the table, or 0 for an unknown id.
static func index_of(id: StringName) -> int:
	for index: int in HEROES.size():
		if HEROES[index]["id"] == id:
			return index
	return 0


## Returns the index one step from an index, wrapping around an inventory of `count` weapons.
static func step_weapon(index: int, direction: int, count: int = WEAPONS.size()) -> int:
	return posmod(index + direction, count)
