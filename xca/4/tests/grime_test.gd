extends SceneTree
## Headless check of the weapon dirt rules and the scrub stroke counter.
## Run: godot --headless --path godot -s ../tests/grime_test.gd

var _failed: bool = false


func _init() -> void:
	_check_buildup()
	_check_scrub()
	_check_bonus()
	_check_counter()
	print("grime_test ", "FAILED" if _failed else "ok")
	quit(1 if _failed else 0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		printerr("FAIL: ", message)


func _check_buildup() -> void:
	var grime := WeaponGrime.new()
	_expect(grime.level(&"pistol") == 0.0, "a new weapon is clean")
	_expect(grime.interval_scale(&"pistol") == 1.0, "a clean weapon fires at full rate")
	for i: int in 1000:
		grime.add_shot(&"pistol")
	_expect(grime.level(&"pistol") == 1.0, "dirt stops at 1")
	_expect(grime.level(&"bat") == 0.0, "dirt stays on its own weapon")
	var slowdown: float = 1.0 - 1.0 / grime.interval_scale(&"pistol")
	_expect(absf(slowdown - 0.4) < 0.01, "full dirt cuts the fire rate by 40 percent, got %f" % slowdown)


func _check_scrub() -> void:
	var grime := WeaponGrime.new()
	_expect(not grime.scrub(&"smg", 5), "scrubbing a clean weapon changes nothing")
	for i: int in 100:
		grime.add_shot(&"smg")
	var before: float = grime.level(&"smg")
	grime.scrub(&"smg", 2)
	_expect(grime.level(&"smg") < before, "scrubbing removes dirt")
	_expect(grime.scrub(&"smg", 100), "enough strokes make the weapon spotless")
	_expect(grime.level(&"smg") == 0.0, "spotless is 0")


func _check_bonus() -> void:
	var grime := WeaponGrime.new()
	for i: int in 100:
		grime.add_shot(&"pistol")
	grime.scrub(&"pistol", 100)
	_expect(grime.bonus_remaining > 0.0, "a full clean of a dirty weapon starts the bonus")
	_expect(grime.interval_scale(&"pistol") < 1.0, "the bonus beats a new weapon")
	_expect(grime.interval_scale(&"shotgun") == 1.0, "the bonus holds only for its weapon")
	grime.tick(WeaponGrime.BONUS_SECONDS + 1.0)
	_expect(grime.interval_scale(&"pistol") == 1.0, "the bonus ends")
	var light := WeaponGrime.new()
	light.add_shot(&"bat")
	light.scrub(&"bat", 5)
	_expect(light.bonus_remaining == 0.0, "a lightly used weapon earns no bonus")
	grime.add_shot(&"pistol")
	grime.reset()
	_expect(grime.level(&"pistol") == 0.0 and grime.bonus_remaining == 0.0, "reset cleans everything")


func _check_counter() -> void:
	var counter := InspectView.ScrubCounter.new(20.0)
	var strokes: int = 0
	for i: int in 3:
		for step: int in 10:
			strokes += counter.feed(5.0)
		for step: int in 10:
			strokes += counter.feed(-5.0)
	_expect(strokes == 5, "three full cycles make five reversals, got %d" % strokes)
	var jitter := InspectView.ScrubCounter.new(20.0)
	var noise: int = 0
	for step: int in 200:
		noise += jitter.feed(3.0 if step % 2 == 0 else -3.0)
	_expect(noise == 0, "small jitter counts no stroke, got %d" % noise)
	var one_way := InspectView.ScrubCounter.new(20.0)
	var drift: int = 0
	for step: int in 100:
		drift += one_way.feed(5.0)
	_expect(drift == 0, "a one-way drag counts no stroke, got %d" % drift)
