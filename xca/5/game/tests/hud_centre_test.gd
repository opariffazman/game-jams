extends SceneTree
## No persistent HUD element covers the central pitch during SCATTER. Run under a virtual display:
## xvfb-run -a godot --path game --rendering-driver opengl3 --resolution 844x390 --script res://tests/hud_centre_test.gd -- <shot.png>

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


func _find_hud(node: Node) -> Hud:
	if node is Hud:
		return node
	for child: Node in node.get_children():
		var found: Hud = _find_hud(child)
		if found != null:
			return found
	return null


func _find_manager(node: Node) -> RoundManager:
	if node is RoundManager:
		return node
	for child: Node in node.get_children():
		var found: RoundManager = _find_manager(child)
		if found != null:
			return found
	return null


func _run() -> void:
	var settings: Node = root.get_node("Settings")
	settings.path = "user://hud_centre_test_settings.cfg"
	settings.set("skip_title", true)
	settings.set("coin_flip_seen", true)
	settings.call("mark_how_to_seen")
	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	var manager: RoundManager = _find_manager(scene)
	var hud: Hud = _find_hud(scene)
	var waited: int = 0
	while manager.phase != RoundManager.SCATTER and waited < 3000:
		await _frames(5)
		waited += 5
	_check(manager.phase == RoundManager.SCATTER, "the round reaches scatter")
	await _frames(3)
	var size: Vector2 = root.get_visible_rect().size
	var pitch: Rect2 = Rect2(size * Vector2(0.25, 0.3), size * Vector2(0.5, 0.4))
	var icon: TextureRect = hud._ring_icon
	var icon_rect: Rect2 = Rect2(icon.global_position, icon.size)
	_check(icon.modulate.a > 0.0, "the stack icon shows during scatter")
	_check(not icon_rect.intersects(pitch), "the stack icon stays out of the central pitch")
	_check(icon_rect.position.y < size.y * 0.2, "the stack icon sits in the top strip")
	if OS.get_cmdline_user_args().size() > 0:
		root.get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
	print("hud_centre_test: %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(_failures)
