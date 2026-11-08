extends SceneTree
## Plays a real match with heroes, dashes, powers and hits, and measures the outline colour around each character
## on screen. Run under a virtual display:
## xvfb-run -a godot --path game --rendering-driver opengl3 --resolution 844x390 --script res://tests/diagnose_outline.gd -- <out_dir>

const SAMPLE_EVERY: int = 6
const TOTAL_FRAMES: int = 1500
const CROP: int = 46
const EDGE: Color = Color(0.04, 0.06, 0.1)

var _manager: RoundManager
var _view: World3DView
var _rows: Array = []


func _initialize() -> void:
	_run()


func _frames(count: int) -> void:
	for _i: int in count:
		await process_frame


func _near(a: Color, b: Color, tolerance: float) -> bool:
	return absf(a.r - b.r) < tolerance and absf(a.g - b.g) < tolerance and absf(a.b - b.b) < tolerance


func _run() -> void:
	var settings: Node = root.get_node("Settings")
	settings.path = "user://diagnose_outline_settings.cfg"
	settings.set_view(SettingsRef.VIEW_DEPTH)
	settings.set("skip_title", true)
	settings.set("coin_flip_seen", true)
	settings.call("mark_how_to_seen")
	SkinRef.reload()
	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	await _frames(30)
	_manager = scene.get_node("RoundManager") as RoundManager
	_view = World3DView.find(self)
	var out_dir: String = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	var worst: float = 0.0
	for frame: int in TOTAL_FRAMES:
		await process_frame
		_poke(frame)
		if frame % SAMPLE_EVERY != 0:
			continue
		var image: Image = root.get_viewport().get_texture().get_image()
		for character: Character in _characters():
			var sample: Dictionary = _measure(character, image)
			if sample.is_empty():
				continue
			var line: String = "f%d team%d %s role%d dark=%.2f team_px=%d dark_px=%d edge_col=%s ring_col=%s alpha=%s" % [frame, character.team, character.name, character.role, sample.ratio, sample.team_px, sample.dark_px, sample.edge, sample.ring, sample.flash]
			_rows.append(line)
			var crop: Image = image.get_region(Rect2i(Vector2i(sample.point) - Vector2i(CROP, CROP), Vector2i(CROP * 2, CROP * 2)).intersection(Rect2i(Vector2i.ZERO, image.get_size())))
			DirAccess.make_dir_recursive_absolute(out_dir + "/crops")
			crop.save_png("%s/crops/%s_f%04d.png" % [out_dir, str(character.name).replace("@", ""), frame])
			if sample.ratio > worst and sample.team_px + sample.dark_px > 40:
				worst = sample.ratio
				image.save_png(out_dir + "/worst.png")
	var f: FileAccess = FileAccess.open(out_dir + "/rows.txt", FileAccess.WRITE)
	for row: String in _rows:
		f.store_line(row)
	f.close()
	print("worst dark ratio: ", worst, " rows: ", _rows.size())
	quit()


func _characters() -> Array:
	var all: Array = []
	for team: int in 2:
		all.append_array(_manager.arena.get_characters(team))
	return all


func _poke(frame: int) -> void:
	for character: Character in _characters():
		if not is_instance_valid(character) or not character.alive:
			continue
		if frame % 90 == int(character.get_instance_id() % 90):
			character.try_power()
		if frame % 70 == int(character.get_instance_id() % 70):
			character.dash()
		if frame % 55 == int(character.get_instance_id() % 55) and character.visual != null:
			character.visual.play(&"hit")
		character.move_intent = Vector2.from_angle(float(frame) * 0.02 + float(character.get_instance_id() % 7))


func _measure(character: Character, image: Image) -> Dictionary:
	if not is_instance_valid(character) or character.visual == null or not character.visual.has_method("play"):
		return {}
	var point: Vector2 = character.get_global_transform_with_canvas().origin + Vector2(0.0, -26.0)
	point *= Vector2(image.get_size()) / root.get_visible_rect().size
	var team_px: int = 0
	var dark_px: int = 0
	var team: Color = character.visual.team_color
	for dy: int in range(-CROP, CROP):
		for dx: int in range(-CROP, CROP):
			var at: Vector2i = Vector2i(point) + Vector2i(dx, dy)
			if at.x < 0 or at.y < 0 or at.x >= image.get_width() or at.y >= image.get_height():
				continue
			var pixel: Color = image.get_pixelv(at)
			if _near(pixel, team, 0.12):
				team_px += 1
			elif pixel.v < 0.2 and pixel.s < 0.6 and _near(pixel, EDGE, 0.1):
				dark_px += 1
	var ratio: float = float(dark_px) / maxf(float(team_px + dark_px), 1.0)
	var overlay: Material = null
	var body: Array = character.visual.get("_body_meshes")
	if body != null and body.size() > 0:
		overlay = (body[0] as MeshInstance3D).material_overlay
	var edge_state: String = "none"
	var ring_state: String = "none"
	var flash: String = "-"
	if overlay is StandardMaterial3D:
		flash = "%.2f" % (overlay as StandardMaterial3D).albedo_color.a
		var edge: ShaderMaterial = overlay.next_pass as ShaderMaterial
		if edge != null:
			edge_state = "%s/%s" % [edge.get_shader_parameter(&"outline_color"), edge.get_shader_parameter(&"thickness")]
			var ring: ShaderMaterial = edge.next_pass as ShaderMaterial
			if ring != null:
				ring_state = "%s/%s" % [ring.get_shader_parameter(&"outline_color"), ring.get_shader_parameter(&"thickness")]
	var fade: float = 0.0
	if body != null and body.size() > 0:
		fade = (body[0] as MeshInstance3D).transparency
	flash += " fade=%.2f inv=%s pow=%.1f" % [fade, character.is_invulnerable(), character.power_time_left]
	return {point = point, ratio = ratio, team_px = team_px, dark_px = dark_px, edge = edge_state, ring = ring_state, flash = flash}
