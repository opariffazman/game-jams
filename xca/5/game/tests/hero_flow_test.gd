extends SceneTree
## Real flow: main scene with the title shown, tap Play, the hero select must open, then Confirm starts the match.
## Run under a virtual display:
## xvfb-run -a godot --path game --rendering-driver opengl3 --resolution 844x390 --script res://tests/hero_flow_test.gd -- <shot.png>

var _failures: int = 0


func _initialize() -> void:
	_run()


func _frames(count: int) -> void:
	for _i: int in count:
		await process_frame


func _check(condition: bool, label: String) -> void:
	print("  ", "ok   " if condition else "FAIL ", label)
	if not condition:
		_failures += 1


func _run() -> void:
	TitleScreen.show_when_headless = true
	TitleScreen.done = false
	var settings: Node = root.get_node("Settings")
	settings.path = "user://hero_flow_settings.cfg"
	settings.set("skip_title", false)
	settings.call("mark_how_to_seen")
	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	await _frames(10)
	var title: TitleScreen = get_first_node_in_group(TitleScreen.GROUP) as TitleScreen
	_check(title != null and title.is_open(), "title opens")
	title.play()
	await _frames(5)
	var select: HeroSelect = get_first_node_in_group(HeroSelect.GROUP) as HeroSelect
	_check(select != null and select.is_open(), "hero select opens after Play")
	_check(paused, "match is paused on the select screen")
	if OS.get_cmdline_user_args().size() > 0:
		await _frames(5)
		root.get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
	if select != null:
		select.confirm(select.heroes[select.selected].id)
	await _frames(5)
	_check(not paused, "match runs after confirm")
	print("hero_flow_test: %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(_failures)
