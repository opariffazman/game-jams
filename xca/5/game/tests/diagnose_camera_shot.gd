extends SceneTree
## Screenshots the settings panel with the camera sliders at min, default and max. Run under a virtual display:
## xvfb-run -a godot --path game --rendering-driver opengl3 --resolution 844x390 --script res://tests/diagnose_camera_shot.gd

const OUT: String = "res://tests/e2e/out/view"


func _initialize() -> void:
	_run()


func _frames(count: int) -> void:
	for _i: int in count:
		await process_frame


func _run() -> void:
	var settings: Node = root.get_node("Settings")
	settings.path = "user://diagnose_settings.cfg"
	settings.set_view(SettingsRef.VIEW_DEPTH)
	SkinRef.reload()
	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	await _frames(30)
	var layer: SettingsLayer = null
	for node: Node in root.find_children("*", "CanvasLayer", true, false):
		if node is SettingsLayer:
			layer = node
	layer.set_open(true)
	var cases: Dictionary = {
		"min": [ViewProjection.MIN_PITCH_DEGREES, ViewProjection.MIN_FIT],
		"default": [ViewProjection.DEFAULT_PITCH_DEGREES, ViewProjection.DEFAULT_FIT],
		"max": [ViewProjection.MAX_PITCH_DEGREES, ViewProjection.MAX_FIT],
	}
	for name: String in cases:
		settings.set_camera(cases[name][0], cases[name][1], false)
		await _frames(12)
		var tag: String = "%dx%d" % [root.get_visible_rect().size.x, root.get_visible_rect().size.y]
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("%s/camera-%s-%s.png" % [OUT, name, tag]))
		print("saved ", name, " ", tag, " pitch ", rect_text(layer.slider_rect(&"camera_pitch")), " zoom ", rect_text(layer.slider_rect(&"camera_zoom")), " reset ", layer.tile_hit(&"camera_reset"))
	settings.reset_camera()
	DirAccess.remove_absolute("user://diagnose_settings.cfg")
	quit(0)


func rect_text(rect: Rect2) -> String:
	return "%s" % [rect]
