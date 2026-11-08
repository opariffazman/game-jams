extends SceneTree
## Headless test of the title screen: skip rules, pause until Play, how-to cards, sizes.
##
## Run: godot --headless --path game --script res://tests/title_test.gd

var _failures: int = 0


func _initialize() -> void:
	await _run()
	print("title_test: %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(_failures)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   ", label)
	else:
		print("  FAIL ", label)
		_failures += 1


func _run() -> void:
	_check(TitleScreen.should_skip(), "headless run skips the title")
	TitleScreen.done = false
	var settings: Node = root.get_node("Settings")
	settings.path = "user://title_test_settings.cfg"
	settings.how_to_seen = true
	TitleScreen.show_when_headless = true
	var title: TitleScreen
	title = TitleScreen.new()
	title.process_mode = Node.PROCESS_MODE_ALWAYS
	root.add_child(title)
	await process_frame
	_check(title.is_open(), "open shows the title")
	_check(paused, "tree is paused while the title shows")
	for size: Vector2i in [Vector2i(320, 180), Vector2i(844, 390), Vector2i(1160, 640), Vector2i(2560, 1440), Vector2i(390, 844)]:
		root.size = size
		await process_frame
		await process_frame
		var area: Rect2 = root.get_visible_rect()
		var inside: bool = area.encloses(Rect2(title.play_button.global_position, title.play_button.size)) and area.encloses(Rect2(title.help_button.global_position, title.help_button.size))
		_check(inside, "buttons fit at %dx%d (%s %s %s)" % [size.x, size.y, title.play_button.global_position, title.play_button.size, title.help_button.size])
		_check(title.play_button.size.x >= 44.0 and title.help_button.size.x >= 20.0, "buttons have size at %dx%d" % [size.x, size.y])
	title.show_how_to()
	_check(title.how_to.visible and settings.how_to_seen, "how-to opens and is remembered")
	for index: int in 4:
		title.how_to.card = index
		await process_frame
	title.how_to.card = 0
	title.how_to.show_card(1, true)
	_check(title.how_to.card == 1, "next card")
	title.how_to.close()
	_check(not title.how_to.visible, "close hides how-to")
	title.play()
	_check(not paused and TitleScreen.done, "play unpauses and marks done")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://title_test_settings.cfg"))
