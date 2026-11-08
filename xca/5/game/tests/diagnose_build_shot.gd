extends SceneTree
## Screenshot driver for the build moment. Needs a window, so run it under a virtual display:
## xvfb-run -a godot --path game --resolution 844x390 --script res://tests/diagnose_build_shot.gd
## DIAGNOSE_VIEW=flat or depth, DIAGNOSE_OUT=directory. It forces a human attacker, topples the pyramid,
## shows the build button, starts the build, and places all three sandals.

const MAIN_SCENE: String = "res://scenes/main.tscn"

var _out: String = "res://tests/e2e/out/view"


func _initialize() -> void:
	_run()


func _frames(count: int) -> void:
	for _i: int in count:
		await process_frame


func _shot(name: String) -> void:
	await _frames(6)
	var image: Image = root.get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path("%s/%s.png" % [_out, name]))
	print("saved ", name)


func _run() -> void:
	var settings: Node = root.get_node("Settings")
	var depth: bool = OS.get_environment("DIAGNOSE_VIEW") != "flat"
	if OS.get_environment("DIAGNOSE_OUT") != "":
		_out = OS.get_environment("DIAGNOSE_OUT")
	settings.path = "user://diagnose_settings.cfg"
	settings.set_view(SettingsRef.VIEW_DEPTH if depth else SettingsRef.VIEW_FLAT)
	SkinRef.reload()
	var scene: Node = (load(MAIN_SCENE) as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	await _frames(30)
	var manager: RoundManager = scene.find_child("RoundManager", true, false) as RoundManager
	manager.tuning.match_countdown = false
	manager.attacking_team = manager.tuning.human_team
	manager._spawn_round()
	await _frames(10)
	manager._start_scatter()
	var stack: Stack = manager.arena.stack
	stack._topple()
	await _frames(5)
	var human: Character = manager.human.character
	human.global_position = stack.global_position + Vector2(-60.0, 40.0)
	var angle: float = 0.0
	for sandal: Sandal in stack._free_sandals():
		sandal.global_position = stack.global_position + Vector2.from_angle(angle) * 40.0
		sandal.linear_velocity = Vector2.ZERO
		angle += TAU / 3.0
	for entry: Variant in manager.arena.get_characters(1):
		(entry as Character).global_position = stack.global_position + Vector2(300.0, 200.0)
	await _frames(20)
	print("can_build ", stack.can_build(), " in_zone ", stack.is_in_zone(human.global_position))
	var name_prefix: String = "build-3d" if depth else "build-2d"
	await _shot(name_prefix + "-1-button")
	var overlay: BuildOverlay = null
	for node: Node in root.find_children("BuildOverlay", "Control", true, false):
		overlay = node as BuildOverlay
	overlay._begin()
	await _frames(30)
	print("building ", stack.builder != null, " blend ", ViewProjection.build_blend)
	await _shot(name_prefix + "-2-qte")
	while stack.builder != null and stack.placed_count < 3:
		stack.builder.complete_build_step()
		await _frames(25)
		if stack.placed_count == 2:
			await _shot(name_prefix + "-3-second")
	await _frames(40)
	await _shot(name_prefix + "-4-built")
	manager.build_view_changed.emit(true, stack.global_position)
	await _frames(40)
	await _shot(name_prefix + "-5-teepee-close")
	print("placed ", stack.placed_count, " built ", stack.is_built, " down ", stack.is_down)
	for child: Node in stack.get_children():
		if child is Sandal:
			print("sandal slot ", child.stack_slot, " pos ", child.global_position, " lean ", child.lean_angle)
	DirAccess.remove_absolute("user://diagnose_settings.cfg")
	quit(0)
