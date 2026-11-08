class_name ReplayFx
extends Node3D
## Cheap emissive-look effects for the 3D replay: telegraph lines, bullets, muzzle flashes and speed lines.

## Most muzzle flash groups allowed per second, to stay flash-safe.
const MAX_FLASHES_PER_S: int = 3
## Flashes that start within this many milliseconds of each other count as one group.
const FLASH_GROUP_MS: int = 150
## Seconds a muzzle flash stays visible. Four frames at 30 fps, so a recording keeps it.
const FLASH_S: float = 0.13
## Width in world units of a muzzle flash.
const FLASH_SIZE: float = 0.55
## Height of bullets and tracers above the floor.
const CHEST: float = 1.15
const AMBER: Color = Color("ffb020")
const CYAN: Color = Color("19e3ff")
const INK: Color = Color("f6f6f8")
const STREAK_COUNT: int = 18
## Peak opacity of the dim cut. It stays under full black and only darkens, so it never flashes.
const CUT_DIM: float = 0.85

var _amber: StandardMaterial3D = _unshaded(AMBER)
var _amber_trail: StandardMaterial3D = _unshaded(Color(AMBER, 0.35), true)
var _cyan: StandardMaterial3D = _unshaded(CYAN)
var _cyan_trail: StandardMaterial3D = _unshaded(Color(CYAN, 0.35), true)
var _flash_mat: StandardMaterial3D = _unshaded(Color("ffe9a8"), true)
var _ring_mat: StandardMaterial3D = _unshaded(Color(INK, 0.9), true)
var _coat_mat: StandardMaterial3D = _unshaded(Color(AMBER, 0.9), true)
var _streak_mat: StandardMaterial3D = _unshaded(Color(INK, 0.0), true)
var _telegraphs: Node3D = Node3D.new()
var _streaks: Node3D = Node3D.new()
var _cut_mat: StandardMaterial3D = _unshaded(Color(0, 0, 0, 0), true)
var _flash_ms: Array[int] = []
var _streak_tween: Tween


func _init() -> void:
	add_child(_telegraphs)
	_flash_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_flash_mat.albedo_texture = _flash_texture()
	_ring_mat.no_depth_test = true
	_coat_mat.no_depth_test = true
	_streak_mat.no_depth_test = true
	_cut_mat.no_depth_test = true
	_cut_mat.render_priority = 100


## Replaces the telegraph lines with [param lines], each a dictionary with Vector3 keys from and to.
func show_telegraphs(lines: Array[Dictionary]) -> void:
	clear_telegraphs()
	for line: Dictionary in lines:
		var from: Vector3 = line["from"]
		var to: Vector3 = line["to"]
		from.y = 0.04
		to.y = 0.04
		_telegraphs.add_child(beam(from, to, 0.1, 0.03, _amber))


## Removes every telegraph line.
func clear_telegraphs() -> void:
	for child: Node in _telegraphs.get_children():
		child.queue_free()


## Returns a box from [param a] to [param b] with the given cross-section, not yet in the tree.
func beam(a: Vector3, b: Vector3, width: float, height: float, material: Material) -> MeshInstance3D:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3(width, height, maxf(a.distance_to(b), 0.01))
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.position = (a + b) * 0.5
	if a.distance_squared_to(b) > 0.0001:
		var up: Vector3 = Vector3.RIGHT if absf((b - a).normalized().y) > 0.99 else Vector3.UP
		instance.transform = Transform3D(Basis.looking_at(b - a, up), (a + b) * 0.5)
	return instance


## Colors the hero's bullet and its trail with [param color], the equipped coat.
func set_hero_color(color: Color) -> void:
	_cyan.albedo_color = color
	_cyan_trail.albedo_color = Color(color, 0.35)


## Flies a bullet from [param from] to [param to] over [param seconds]. The hero bullet is cyan and thicker.
func bullet(from: Vector3, to: Vector3, seconds: float, hero: bool = false) -> void:
	var thick: float = 0.035 if hero else 0.05
	var head: MeshInstance3D = beam(Vector3.ZERO, Vector3(0, 0, -0.5 if not hero else -0.5), thick, thick, _cyan if hero else _amber)
	var trail: MeshInstance3D = beam(Vector3.ZERO, Vector3(0, 0, 1.0 if hero else 1.4), thick * 0.6, thick * 0.6, _cyan_trail if hero else _amber_trail)
	var holder: Node3D = Node3D.new()
	add_child(holder)
	holder.add_child(head)
	holder.add_child(trail)
	trail.position = Vector3(0, 0, 0.75 if hero else 0.95)
	head.position = Vector3.ZERO
	holder.transform = Transform3D(Basis.looking_at(to - from, Vector3.UP), from) if from.distance_squared_to(to) > 0.0001 else Transform3D(Basis.IDENTITY, from)
	var tween: Tween = create_tween()
	tween.tween_property(holder, "position", to, seconds)
	tween.tween_callback(holder.queue_free)


## Shows a small muzzle flash at [param at], unless three flash groups already fired in the last second.
## Flashes that start together count as one group.
func muzzle_flash(at: Vector3) -> void:
	var now: int = Time.get_ticks_msec()
	_flash_ms = _flash_ms.filter(func(t: int) -> bool: return now - t < 1000)
	var joins_group: bool = not _flash_ms.is_empty() and now - _flash_ms[-1] < FLASH_GROUP_MS
	if not joins_group:
		if _flash_ms.size() >= MAX_FLASHES_PER_S:
			return
		_flash_ms.append(now)
	var quad: MeshInstance3D = MeshInstance3D.new()
	var mesh: QuadMesh = QuadMesh.new()
	mesh.size = Vector2(FLASH_SIZE, FLASH_SIZE)
	quad.mesh = mesh
	quad.material_override = _flash_mat
	quad.position = at
	add_child(quad)
	var tween: Tween = create_tween().set_ignore_time_scale(true)
	tween.tween_property(quad, "scale", Vector3.ONE * 1.5, FLASH_S).from(Vector3.ONE * 0.6)
	tween.tween_callback(quad.queue_free)


## Pops a thin ring at [param at] facing [param toward], the spark of a blocked shot. It grows and fades in about 0.25 s.
func spark_ring(at: Vector3, toward: Vector3) -> void:
	var ring: MeshInstance3D = _ring_instance(_ring_mat, 0.2, 0.26)
	ring.position = at
	add_child(ring)
	ring.look_at(toward)
	ring.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	_pop(ring, 0.25, 2.2)


## Pops an amber ring around the edge of [param camera], the cue of a spent Bulletproof Coat.
func coat_ring(camera: Camera3D) -> void:
	var ring: MeshInstance3D = _ring_instance(_coat_mat, 0.25, 0.29)
	ring.position = Vector3(0, 0, -0.5)
	ring.rotation.x = PI * 0.5
	camera.add_child(ring)
	_pop(ring, 0.5, 1.7)


## Dims the lens in over [param half_s], calls [param at_dark], then dims out over [param half_s]. It replaces a dash that would cross a wall.
## Real time, and it only darkens, never brightens, so it is flash-safe.
func dim_cut(camera: Camera3D, half_s: float, at_dark: Callable) -> void:
	var quad: MeshInstance3D = MeshInstance3D.new()
	var mesh: QuadMesh = QuadMesh.new()
	mesh.size = Vector2(6.0, 6.0)
	quad.mesh = mesh
	quad.material_override = _cut_mat
	quad.position = Vector3(0, 0, -0.3)
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	camera.add_child(quad)
	var tween: Tween = create_tween().set_ignore_time_scale(true)
	tween.tween_property(_cut_mat, "albedo_color:a", CUT_DIM, half_s)
	tween.tween_callback(at_dark)
	tween.tween_property(_cut_mat, "albedo_color:a", 0.0, half_s)
	tween.tween_callback(quad.queue_free)


## Attaches speed lines to [param camera] and plays them for [param seconds].
func speed_lines(camera: Camera3D, seconds: float) -> void:
	if _streaks.get_child_count() == 0:
		for i: int in STREAK_COUNT:
			var angle: float = TAU * float(i) / STREAK_COUNT + float(i % 3) * 0.13
			var radius: float = 0.9 + float(i % 4) * 0.45
			var line: MeshInstance3D = beam(Vector3.ZERO, Vector3(0, 0, -2.0), 0.02, 0.02, _streak_mat)
			line.position = Vector3(cos(angle) * radius, sin(angle) * radius * 1.4, -3.0)
			_streaks.add_child(line)
	if _streaks.get_parent() != camera:
		camera.add_child(_streaks)
	if _streak_tween:
		_streak_tween.kill()
	_streaks.scale = Vector3(1, 1, 0.4)
	_streak_tween = create_tween().set_ignore_time_scale(true).set_parallel(true)
	_streak_tween.tween_property(_streaks, "scale:z", 1.2, seconds)
	_streak_tween.tween_property(_streak_mat, "albedo_color:a", 0.0, seconds).from(0.7)


func _ring_instance(material: Material, inner: float, outer: float) -> MeshInstance3D:
	var mesh: TorusMesh = TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.rings = 20
	mesh.ring_segments = 4
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


## Grows [param node] by [param grow] over [param seconds] of real time, then frees it. The shared ring material keeps its alpha.
func _pop(node: Node3D, seconds: float, grow: float) -> void:
	var tween: Tween = create_tween().set_ignore_time_scale(true)
	tween.tween_property(node, "scale", Vector3.ONE * grow, seconds).from(Vector3.ONE * 0.6).set_ease(Tween.EASE_OUT)
	tween.tween_callback(node.queue_free)


func _flash_texture() -> GradientTexture2D:
	var gradient: Gradient = Gradient.new()
	gradient.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0)])
	gradient.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 64
	texture.height = 64
	return texture


func _unshaded(color: Color, alpha: bool = false) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	if alpha:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material
