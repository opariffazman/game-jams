extends SceneTree
## Parks one character at a grid of pitch positions and counts team-coloured and dark outline pixels around it.
## Exits 1 when the team ring is missing at any position, which is how the black outline looked. Run under a virtual display:
## xvfb-run -a godot --path game --rendering-driver opengl3 --resolution 844x390 --script res://tests/diagnose_outline_grid.gd -- <out_dir>
##
## The countdown digit sits in the middle column and the stands crop the top row, so those cells are skipped.

const EDGE: Color = Color(0.04, 0.06, 0.1)
const MIN_RING_PIXELS: int = 40

var _failures: int = 0


func _initialize() -> void:
	_run()


func _frames(count: int) -> void:
	for _i: int in count:
		await process_frame


func _near(a: Color, b: Color, tolerance: float) -> bool:
	return absf(a.r - b.r) < tolerance and absf(a.g - b.g) < tolerance and absf(a.b - b.b) < tolerance


func _run() -> void:
	var settings: Node = root.get_node("Settings")
	settings.path = "user://diagnose_outline_grid.cfg"
	settings.set_view(SettingsRef.VIEW_DEPTH)
	settings.set("skip_title", true)
	settings.set("coin_flip_seen", true)
	settings.call("mark_how_to_seen")
	SkinRef.reload()
	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	await _frames(60)
	var manager: RoundManager = scene.get_node("RoundManager") as RoundManager
	var all: Array = []
	for team: int in 2:
		all.append_array(manager.arena.get_characters(team))
	var subject: Character = all[all.size() - 1] as Character
	manager.set_physics_process(false)
	get_root().get_tree().paused = false
	for other: Character in all:
		other.set_physics_process(false)
		other.set_process(false)
		if other != subject:
			other.global_position = Vector2(-5000.0, -5000.0)
	var half: Vector2 = manager.arena.tuning.arena_half_extents - Vector2.ONE * 60.0
	var bounds: Rect2 = Rect2(manager.arena.centre_spot - half, half * 2.0)
	var results: Array = []
	for gy: int in 5:
		for gx: int in 7:
			var at: Vector2 = bounds.position + bounds.size * Vector2((gx + 0.5) / 7.0, (gy + 0.5) / 5.0)
			subject.global_position = at
			await _frames(3)
			var image: Image = root.get_viewport().get_texture().get_image()
			var point: Vector2 = subject.get_global_transform_with_canvas().origin + Vector2(0.0, -26.0)
			point *= Vector2(image.get_size()) / root.get_visible_rect().size
			var team_px: int = 0
			var dark_px: int = 0
			var team: Color = subject.visual.team_color
			for dy: int in range(-40, 40):
				for dx: int in range(-30, 30):
					var p: Vector2i = Vector2i(point) + Vector2i(dx, dy)
					if p.x < 0 or p.y < 0 or p.x >= image.get_width() or p.y >= image.get_height():
						continue
					var pixel: Color = image.get_pixelv(p)
					if _near(pixel, team, 0.12):
						team_px += 1
					elif _near(pixel, EDGE, 0.08):
						dark_px += 1
			results.append([at, team_px, dark_px])
			image.get_region(Rect2i(Vector2i(point) - Vector2i(40, 50), Vector2i(80, 90)).intersection(Rect2i(Vector2i.ZERO, image.get_size()))).save_png("%s/g_%d_%d.png" % [OS.get_cmdline_user_args()[0], gx, gy])
			var skipped: bool = gx == 3 or gy == 0
			var ok: bool = skipped or (team_px >= MIN_RING_PIXELS and dark_px < team_px)
			if not ok:
				_failures += 1
			print("%s pos %s team_px=%d dark_px=%d" % ["skip" if skipped else ("ok  " if ok else "FAIL"), at, team_px, dark_px])
	print("diagnose_outline_grid: %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(_failures)
