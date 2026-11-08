extends SceneTree
## Headless test of the flat and depth views: persistence, building, switching at round start, and leaks.
##
## Run in real time: godot --headless --path game --script res://tests/view_test.gd

const MAIN_SCENE: String = "res://scenes/main.tscn"
const SETTLE_FRAMES: int = 20
const CYCLES: int = 3

var _failures: int = 0
var _settings: Node
var _orphans: Array[int] = []


func _initialize() -> void:
	_settings = root.get_node("Settings")
	_test_persistence()
	await _test_views_build()
	await _test_switch_applies_at_round_start()
	await _test_kampong_scenery()
	await _test_projection()
	await _test_camera_settings()
	await _test_rings_only_on_human()
	await _test_no_leak_over_restarts()
	print("view_test: %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	_settings.set_view(SettingsRef.VIEW_FLAT)
	quit(_failures)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   ", label)
	else:
		print("  FAIL ", label)
		_failures += 1


func _frames(count: int) -> void:
	for _i: int in count:
		await process_frame


func _load_main(view: int) -> Node:
	_settings.set_view(view)
	SkinRef.reload()
	var scene: Node = (load(MAIN_SCENE) as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	await _frames(SETTLE_FRAMES)
	return scene


func _unload(scene: Node) -> void:
	root.remove_child(scene)
	scene.free()
	await _frames(2)


func _test_persistence() -> void:
	var scratch: String = "user://view_test_settings.cfg"
	var first: Node = load("res://autoload/settings.gd").new()
	first.path = scratch
	first.view = SettingsRef.VIEW_DEPTH
	first.save_settings()
	var second: Node = load("res://autoload/settings.gd").new()
	second.path = scratch
	second.load_settings()
	_check(second.view == SettingsRef.VIEW_DEPTH, "depth view persists")
	var fresh: Node = load("res://autoload/settings.gd").new()
	fresh.path = "user://view_test_missing.cfg"
	fresh.load_settings()
	_check(fresh.view == SettingsRef.VIEW_DEPTH, "default view is 3D")
	for node: Node in [first, second, fresh]:
		node.free()
	DirAccess.remove_absolute(scratch)


func _test_views_build() -> void:
	var flat: Node = await _load_main(SettingsRef.VIEW_FLAT)
	_check(World3DView.find(self) == null, "flat view has no 3D world")
	_check(get_nodes_in_group(Character.HUMAN_GROUP).size() >= 1, "flat view has a human character")
	await _unload(flat)
	var depth: Node = await _load_main(SettingsRef.VIEW_DEPTH)
	_check(World3DView.find(self) != null, "depth view has a 3D world")
	var arena: Arena = get_first_node_in_group(Arena.GROUP) as Arena
	_check(arena != null and arena.stack != null, "depth view has an arena and a stack")
	_check(get_nodes_in_group(Character.HUMAN_GROUP).size() >= 1, "depth view has a human character")
	await _unload(depth)


func _test_switch_applies_at_round_start() -> void:
	var scene: Node = await _load_main(SettingsRef.VIEW_FLAT)
	_settings.set_view(SettingsRef.VIEW_DEPTH)
	await _frames(5)
	_check(World3DView.find(self) == null, "view change does not apply mid-round")
	var manager: RoundManager = scene.find_child("RoundManager", true, false) as RoundManager
	manager._spawn_round()
	await _frames(SETTLE_FRAMES)
	_check(World3DView.find(self) != null, "view change applies at the next round start")
	_settings.set_view(SettingsRef.VIEW_FLAT)
	manager._spawn_round()
	await _frames(SETTLE_FRAMES)
	_check(World3DView.find(self) == null, "switching back removes the 3D world")
	await _unload(scene)


func _test_no_leak_over_restarts() -> void:
	for view: int in [SettingsRef.VIEW_FLAT, SettingsRef.VIEW_DEPTH]:
		_orphans.clear()
		for _cycle: int in CYCLES:
			var scene: Node = await _load_main(view)
			await _unload(scene)
			await _frames(5)
			_orphans.append(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)))
		_check(_orphans[CYCLES - 1] <= _orphans[0], "view %d: orphan nodes do not grow over restarts (%s)" % [view, str(_orphans)])


func _test_kampong_scenery() -> void:
	var scene: Node = await _load_main(SettingsRef.VIEW_DEPTH)
	var world: World3DView = World3DView.find(self)
	var nodes: int = _count_nodes(world)
	_check(nodes < 150, "depth view node count stays under 150 (%d)" % nodes)
	var half: Vector2 = Vector2(540.0, 300.0)
	var scenery: KampongScenery = KampongScenery.new(1.0 / World3DView.GROUND_STRETCH)
	var placements: Dictionary = scenery.layout(half)
	var inside: int = 0
	var ring: int = 0
	for path: String in placements:
		if path.ends_with("/floor.glb") or path.ends_with("floor-detail.glb") or path.contains("patch-"):
			continue
		for placed: Transform3D in placements[path]:
			var ground: Vector2 = Vector2(placed.origin.x, placed.origin.z * World3DView.GROUND_STRETCH)
			if absf(ground.x) < half.x and absf(ground.y) < half.y:
				inside += 1
			if ground.length() < 260.0:
				ring += 1
	_check(not placements.is_empty() and inside == 0, "no upright scenery prop stands inside the play field (%d)" % inside)
	_check(ring == 0, "no scenery prop stands inside the throw ring (%d)" % ring)
	var tuning: Tuning = Tuning.load_default()
	var lane_clear: bool = true
	var dressing: Array[Vector4] = scenery.dressing_spots(half)
	for spot: Vector4 in dressing:
		var from_centre: float = Vector2(spot.x, spot.y).length()
		# Characters stand on the throw ring (radius throw_radius) and the orbit ring, and sandals on the stack.
		if absf(from_centre - tuning.throw_radius) < 60.0 or from_centre < tuning.throw_radius + 80.0 or absf(spot.x) > half.x - 20.0 or absf(spot.y) > half.y - 20.0:
			lane_clear = false
	_check(lane_clear and dressing.size() < 20, "floor dressing stays at the field edge, off the throw ring (%d spots)" % dressing.size())
	var tiles: Array[Vector2] = scenery.floor_tiles(half)
	_check(tiles.size() >= 40 and tiles.size() <= 80, "sand floor tiles cover the field (%d)" % tiles.size())
	await _unload(scene)


func _test_projection() -> void:
	var scene: Node = await _load_main(SettingsRef.VIEW_DEPTH)
	_check(ViewProjection.active, "tilted projection is on in the depth view")
	var camera: Camera3D = _find_camera(World3DView.find(self))
	_check(camera != null and camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "depth camera is orthographic")
	_check(camera != null and is_equal_approx(rad_to_deg(camera.rotation.x), -ViewProjection.pitch_degrees), "depth camera pitch matches ViewProjection (%.1f)" % (rad_to_deg(camera.rotation.x) if camera != null else 0.0))
	_check(camera != null and absf(absf(rad_to_deg(camera.rotation.y)) - ViewProjection.YAW_DEGREES) < 0.01, "depth camera yaw matches ViewProjection")
	var viewport: Viewport = root
	var worst: float = 0.0
	for point: Vector2 in [Vector2(640.0, 360.0), Vector2(100.0, 60.0), Vector2(1180.0, 660.0), Vector2(-300.0, 900.0), Vector2(777.0, 12.0)]:
		var back: Vector2 = ViewProjection.to_world(viewport, ViewProjection.to_screen(viewport, point))
		worst = maxf(worst, back.distance_to(point))
	_check(worst < 0.01, "screen and ground round trip (worst error %.4f px)" % worst)
	var matches: bool = camera != null
	if camera != null:
		for point: Vector2 in [Vector2(640.0, 360.0), Vector2(100.0, 60.0), Vector2(1100.0, 640.0)]:
			var from_camera: Vector2 = camera.unproject_position(World3DView.ground(point)) / Vector2(camera.get_viewport().size) * viewport.get_visible_rect().size
			if from_camera.distance_to(ViewProjection.to_screen(viewport, point)) > 1.0:
				matches = false
	_check(matches, "ViewProjection matches the Camera3D projection")
	var up_world: Vector2 = ViewProjection.screen_dir_to_world(Vector2.UP)
	var back_up: Vector2 = ViewProjection.world_dir_to_screen(up_world)
	_check(back_up.distance_to(Vector2.UP) < 0.001, "thumb up maps to a ground direction and back")
	var step: Vector2 = ViewProjection.to_screen(viewport, Vector2(640.0, 360.0) + up_world * 100.0) - ViewProjection.to_screen(viewport, Vector2(640.0, 360.0))
	_check(step.y < 0.0 and absf(step.x) < 0.001, "moving along the mapped thumb direction goes straight up the screen")
	var tuning: Tuning = Tuning.load_default()
	var extent: Rect2 = Rect2(ViewProjection.to_screen(viewport, tuning.arena_centre), Vector2.ZERO)
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			extent = extent.expand(ViewProjection.to_screen(viewport, tuning.arena_centre + tuning.arena_half_extents * Vector2(sx, sy)))
	var screen: Vector2 = viewport.get_visible_rect().size
	_check(Rect2(Vector2.ZERO, screen).encloses(extent), "the whole field fits the screen (%s in %s)" % [str(extent), str(screen)])
	await _unload(scene)
	_check(not ViewProjection.active, "projection is off again after the depth view leaves")
	var flat: Node = await _load_main(SettingsRef.VIEW_FLAT)
	var flat_point: Vector2 = Vector2(300.0, 200.0)
	_check(ViewProjection.to_screen(root, flat_point).distance_to(root.get_canvas_transform() * flat_point) < 0.001, "flat view keeps the canvas transform")
	_check(ViewProjection.screen_dir_to_world(Vector2.UP) == Vector2.UP, "flat view keeps thumb directions")
	await _unload(flat)


func _test_camera_settings() -> void:
	var scene: Node = await _load_main(SettingsRef.VIEW_DEPTH)
	var camera: Camera3D = _find_camera(World3DView.find(self))
	var worst: float = 0.0
	var matched: bool = true
	for pitch: float in [ViewProjection.MIN_PITCH_DEGREES, 42.0, ViewProjection.MAX_PITCH_DEGREES]:
		for zoom: float in [ViewProjection.MIN_FIT, 1.0, ViewProjection.MAX_FIT]:
			SettingsRef.set_camera(pitch, zoom, false)
			await _frames(3)
			for point: Vector2 in [Vector2(640.0, 360.0), Vector2(120.0, 80.0), Vector2(1150.0, 650.0)]:
				var back: Vector2 = ViewProjection.to_world(root, ViewProjection.to_screen(root, point))
				worst = maxf(worst, back.distance_to(point))
				var from_camera: Vector2 = camera.unproject_position(World3DView.ground(point)) / Vector2(camera.get_viewport().size) * root.get_visible_rect().size
				if from_camera.distance_to(ViewProjection.to_screen(root, point)) > 1.0:
					matched = false
			var up_world: Vector2 = ViewProjection.screen_dir_to_world(Vector2.UP)
			if ViewProjection.world_dir_to_screen(up_world).distance_to(Vector2.UP) > 0.001:
				matched = false
	_check(worst < 0.01, "round trip holds at every pitch and zoom (worst %.4f px)" % worst)
	_check(matched, "Camera3D matches ViewProjection and thumb mapping at every pitch and zoom")
	_check(is_equal_approx(ViewProjection.squash(), sin(deg_to_rad(ViewProjection.MAX_PITCH_DEGREES))), "overlay squash follows the live pitch")
	SettingsRef.set_camera(100.0, 9.0, false)
	_check(is_equal_approx(SettingsRef.camera_pitch(), ViewProjection.MAX_PITCH_DEGREES) and is_equal_approx(SettingsRef.camera_zoom(), ViewProjection.MAX_FIT), "camera values clamp to their limits")
	var settings: Node = SettingsRef.node()
	var saved_path: String = settings.path
	settings.path = "user://view_test_settings.cfg"
	SettingsRef.set_camera(33.0, 1.25)
	settings.camera_pitch = 1.0
	settings.camera_zoom = 1.0
	settings.load_settings()
	_check(is_equal_approx(settings.camera_pitch, 33.0) and is_equal_approx(settings.camera_zoom, 1.25), "camera pitch and zoom persist in settings.cfg")
	SettingsRef.reset_camera()
	_check(is_equal_approx(SettingsRef.camera_pitch(), ViewProjection.DEFAULT_PITCH_DEGREES) and is_equal_approx(SettingsRef.camera_zoom(), ViewProjection.DEFAULT_FIT), "reset restores the default camera")
	DirAccess.remove_absolute("user://view_test_settings.cfg")
	settings.path = saved_path
	var layer: SettingsLayer = scene.find_child("SettingsLayer", true, false) as SettingsLayer
	if layer == null:
		for node: Node in root.find_children("*", "CanvasLayer", true, false):
			if node is SettingsLayer:
				layer = node
	_check(layer != null, "settings layer found")
	if layer != null:
		layer.set_open(true)
		await _frames(2)
		var screen: Vector2 = root.get_visible_rect().size
		for slider: StringName in [&"camera_pitch", &"camera_zoom"]:
			var rect: Rect2 = layer.slider_rect(slider)
			_check(rect.size.y >= 44.0 and Rect2(Vector2.ZERO, screen).encloses(rect), "slider %s is at least 44 px tall and on screen (%s)" % [slider, str(rect)])
		var reset: Dictionary = layer.tile_hit(&"camera_reset")
		_check(float(reset["radius"]) >= 22.0, "reset button is at least 44 px wide")
		SettingsRef.set_view(SettingsRef.VIEW_FLAT)
		await _frames(2)
		_check(layer.slider_rect(&"camera_pitch").size == Vector2.ZERO, "sliders hide in the flat view")
		SettingsRef.set_view(SettingsRef.VIEW_DEPTH)
		layer.set_open(false)
	SettingsRef.reset_camera()
	await _unload(scene)


func _test_rings_only_on_human() -> void:
	for view: int in [SettingsRef.VIEW_FLAT, SettingsRef.VIEW_DEPTH]:
		var scene: Node = await _load_main(view)
		var manager: RoundManager = scene.find_child("RoundManager", true, false) as RoundManager
		await _frames(10)
		var characters: Array[Node] = []
		for team: int in 2:
			for entry: Variant in manager.arena.get_characters(team):
				characters.append(entry as Node)
		var human_rings: int = 0
		var other_rings: int = 0
		for node: Node in characters:
			var character: Character = node as Character
			var rings: int = _count_team_rings(character)
			if character.is_in_group(Character.HUMAN_GROUP):
				human_rings += rings
			else:
				other_rings += rings
		_check(other_rings == 0, "view %d: no team ring on a character the human does not control (%d)" % [view, other_rings])
		await _unload(scene)


# A team ring is an annulus mesh under the character visual in the depth view. The flat view draws none.
func _count_team_rings(character: Character) -> int:
	var depth: DepthVisual = character.visual as DepthVisual
	if depth == null:
		return 0
	var count: int = 0
	var node: Node3D = depth.get("_node") as Node3D
	if node == null:
		return 0
	for mesh: Node in node.find_children("*", "MeshInstance3D", true, false):
		var instance: MeshInstance3D = mesh as MeshInstance3D
		if instance.mesh is ArrayMesh and instance.get_parent().get_parent() == node and instance.position.y > 0.1 and instance.position.y < 0.3:
			count += 1
	return count


func _find_camera(node: Node) -> Camera3D:
	for found: Node in node.find_children("*", "Camera3D", true, false):
		return found as Camera3D
	return null


func _count_nodes(node: Node) -> int:
	var total: int = 1
	for child: Node in node.get_children():
		total += _count_nodes(child)
	return total
