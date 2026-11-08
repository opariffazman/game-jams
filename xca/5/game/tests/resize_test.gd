extends SceneTree
## Headless test: the gear and restart ring stay at the top right corner for any window size.
##
## Run: godot --headless --path game --script res://tests/resize_test.gd

var _failures: int = 0


func _initialize() -> void:
	var viewport: Viewport = root
	for size: Vector2i in [Vector2i(1160, 640), Vector2i(844, 390), Vector2i(1920, 1080), Vector2i(400, 300), Vector2i(2400, 600)]:
		root.size = size
		root.content_scale_size = size
		var screen: Vector2 = viewport.get_visible_rect().size
		var column: Dictionary = RestartUiScale.top_right_column(viewport, 28.0, 22.0, 10.0, 60.0)
		var gear: Vector2 = column["gear"]
		var restart: Vector2 = column["restart"]
		_check(gear.x + 28.0 <= screen.x and gear.x - 28.0 >= screen.x * 0.5, "gear inside the right half at %s" % size)
		_check(gear.y - 28.0 >= 60.0, "gear below the HUD row at %s" % size)
		_check(gear.distance_to(restart) >= 28.0 + 22.0, "gear and restart ring do not overlap at %s" % size)
	print("resize_test: %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(_failures)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   ", label)
	else:
		print("  FAIL ", label)
		_failures += 1
