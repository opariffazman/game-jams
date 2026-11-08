extends SceneTree
## The coin shows once ever. Run under a virtual display:
## xvfb-run -a godot --path game --rendering-driver opengl3 --resolution 844x390 --script res://tests/coin_flip_test.gd -- <shot.png>

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


func _coin_visible() -> bool:
	var coin: CoinFlip = _find(root)
	return coin != null and coin.visible


func _find(node: Node) -> CoinFlip:
	if node is CoinFlip:
		return node
	for child: Node in node.get_children():
		var found: CoinFlip = _find(child)
		if found != null:
			return found
	return null


func _run() -> void:
	var settings: Node = root.get_node("Settings")
	settings.path = "user://coin_flip_test_settings.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(settings.path))
	settings.set("skip_title", true)
	settings.set("coin_flip_seen", false)
	settings.call("mark_how_to_seen")
	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	await _frames(12)
	_check(_coin_visible(), "the coin shows on the first match")
	_check(bool(settings.get("coin_flip_seen")), "the first flip is remembered")
	if OS.get_cmdline_user_args().size() > 0:
		await _frames(6)
		root.get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
	await create_timer(5.0).timeout
	_check(not _coin_visible(), "the coin hides after the flip")
	var manager: RoundManager = get_first_node_in_group(&"round_manager") as RoundManager
	if manager == null:
		manager = _find_manager(root)
	manager.start_match()
	await _frames(20)
	_check(manager.phase == RoundManager.COIN_FLIP, "a new match enters the coin flip phase")
	_check(not _coin_visible(), "the coin does not show again")
	print("coin_flip_test: %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(_failures)


func _find_manager(node: Node) -> RoundManager:
	if node is RoundManager:
		return node
	for child: Node in node.get_children():
		var found: RoundManager = _find_manager(child)
		if found != null:
			return found
	return null
