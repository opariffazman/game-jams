extends SceneTree
## Screenshots a 3D match frame. Run under a virtual display:
## xvfb-run -a godot --path game --rendering-driver opengl3 --resolution 844x390 --script res://tests/diagnose_look_shot.gd -- <out.png>


func _initialize() -> void:
	_run()


func _frames(count: int) -> void:
	for _i: int in count:
		await process_frame


func _run() -> void:
	var settings: Node = root.get_node("Settings")
	settings.path = "user://diagnose_settings.cfg"
	settings.set_view(SettingsRef.VIEW_DEPTH)
	settings.set("skip_title", true)
	settings.call("mark_how_to_seen")
	SkinRef.reload()
	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	await _frames(240)
	var out: String = OS.get_cmdline_user_args()[0]
	root.get_viewport().get_texture().get_image().save_png(out)
	quit()
