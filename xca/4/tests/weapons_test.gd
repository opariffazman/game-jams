extends SceneTree
## Headless check of the look table, the shared weapon inventory, weapon cycling and the slide steering rule.
## Run: godot --headless --path godot -s ../tests/weapons_test.gd

var _failed: bool = false


func _init() -> void:
	_check_heroes()
	_check_weapons()
	_check_cycling()
	_check_loadouts()
	_check_slide_lane()
	print("weapons_test ", "FAILED" if _failed else "ok")
	quit(1 if _failed else 0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		printerr("FAIL: ", message)


func _check_heroes() -> void:
	_expect(HeroTable.HEROES.size() == 4, "four looks")
	var ids: Dictionary = {}
	for spec: Dictionary in HeroTable.HEROES:
		ids[spec["id"]] = true
		_expect(ResourceLoader.exists(String(spec["model"])), "model exists for %s" % spec["id"])
		_expect(int(spec["hearts"]) >= 5, "hearts for %s" % spec["id"])
		_expect(not spec.has("melee") and not spec.has("weapon"), "a look carries no weapon, %s" % spec["id"])
	_expect(ids.size() == 4, "ids are unique")
	_expect(int(HeroTable.get_spec(&"matt")["hearts"]) == 6, "matt has 6 hearts")
	_expect(HeroTable.get_spec(&"nobody")["id"] == &"lis", "unknown id falls back to lis")
	_expect(HeroTable.index_of(&"matt") == 3, "index of matt")


func _check_weapons() -> void:
	_expect(HeroTable.WEAPONS.size() == 9, "nine weapons")
	for weapon: Dictionary in HeroTable.WEAPONS:
		if bool(weapon["melee"]):
			_expect(weapon["swing_clip"] != &"" and float(weapon["swing_reach"]) > 0.0 and int(weapon["swing_damage"]) > 0, "melee numbers for %s" % weapon["id"])
		else:
			_expect(float(weapon["fire_interval"]) > 0.0 and int(weapon["pellets"]) >= 1 and int(weapon["damage"]) >= 1 and float(weapon["range"]) > 0.0, "gun numbers for %s" % weapon["id"])
	var by_id: Dictionary = {}
	for weapon: Dictionary in HeroTable.WEAPONS:
		by_id[weapon["id"]] = weapon
	_expect(is_equal_approx(float(by_id[&"shotgun"]["fire_interval"]), 0.7) and int(by_id[&"shotgun"]["pellets"]) > 1, "shotgun is slow with several pellets")
	_expect(is_equal_approx(float(by_id[&"smg"]["fire_interval"]), 0.12), "smg is fast")
	_expect(bool(by_id[&"bat"]["melee"]), "bat is melee")
	for weapon: Dictionary in HeroTable.WEAPONS:
		_expect(ResourceLoader.exists("res://assets/ui/%s.png" % weapon["id"]), "icon exists for %s" % weapon["id"])
		_expect(HeroTable.weapon_by_id(weapon["id"]) == weapon, "lookup by id for %s" % weapon["id"])


func _check_cycling() -> void:
	var count: int = HeroTable.WEAPONS.size()
	_expect(HeroTable.step_weapon(0, 1) == 1, "next from the first")
	_expect(HeroTable.step_weapon(count - 1, 1) == 0, "next wraps to the first")
	_expect(HeroTable.step_weapon(0, -1) == count - 1, "previous wraps to the last")
	_expect(HeroTable.step_weapon(2, 1, 3) == 0, "next wraps inside a carried set of three")


func _check_loadouts() -> void:
	var pairs: Dictionary = {}
	for spec: Dictionary in HeroTable.HEROES:
		var ids: Array[StringName] = HeroTable.loadout(spec["id"])
		_expect(ids.size() == 2, "two weapons for %s" % spec["id"])
		_expect(not bool(HeroTable.weapon_by_id(ids[0])["melee"]), "ranged first for %s" % spec["id"])
		_expect(bool(HeroTable.weapon_by_id(ids[1])["melee"]), "melee second for %s" % spec["id"])
		pairs[ids] = true
	_expect(pairs.size() == HeroTable.HEROES.size(), "every hero has its own pair")
	var shooter := Shooter.new()
	shooter.set_loadout(HeroTable.loadout(&"matt"))
	_expect(shooter.carried == [&"shotgun", &"axe"], "matt carries a shotgun and an axe")
	_expect(shooter.get_weapon()["id"] == &"shotgun", "the ranged weapon starts in hand")
	_expect(shooter.peek_weapon(1)["id"] == &"axe", "the next weapon is the melee one")
	_expect(shooter.add_weapon(&"smg"), "a new weapon joins")
	_expect(shooter.carried.size() == 3 and shooter.get_weapon()["id"] == &"smg", "the new weapon is in hand")
	_expect(shooter.ammo_left(HeroTable.weapon_by_id(&"smg")) == 70, "the new gun comes full")
	_expect(shooter.add_weapon(&"rifle"), "a fourth weapon joins")
	_expect(shooter.carried == [&"shotgun", &"axe", &"rifle"], "the cap replaces the previous pickup, never the loadout")
	_expect(not shooter.add_weapon(&"rifle"), "a carried weapon only refills")
	shooter.free()


func _check_slide_lane() -> void:
	_expect(BodyInput.slide_to_lane(-1.0, 1, 3) == 1, "no hand keeps the lane")
	_expect(BodyInput.slide_to_lane(0.1, 1, 3) == 0, "left third picks lane 0")
	_expect(BodyInput.slide_to_lane(0.9, 1, 3) == 2, "right third picks lane 2")
	_expect(BodyInput.slide_to_lane(0.5, 0, 3) == 1, "middle third picks lane 1")
	var border: float = 1.0 / 3.0
	_expect(BodyInput.slide_to_lane(border + BodyInput.SLIDE_HYSTERESIS * 0.5, 0, 3) == 0, "just past the border holds the lane")
	_expect(BodyInput.slide_to_lane(border + BodyInput.SLIDE_HYSTERESIS * 2.0, 0, 3) == 1, "well past the border changes the lane")
	_expect(BodyInput.slide_to_lane(1.0, 0, 5) == 4, "five lanes reach the last lane")
