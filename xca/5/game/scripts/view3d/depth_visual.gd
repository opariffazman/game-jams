class_name DepthVisual
extends EntityVisual
## 3D art for the depth skin. This node is a 2D proxy that sits in the 2D world like any other
## [EntityVisual]. It builds a [Node3D] in the shared [World3DView] and copies its own ground position
## to it every frame, so physics and logic never know the art is 3D.
##
## Without a [World3DView] in the tree the visual draws nothing. The arena visual creates the view.

enum Kind { ATTACKER, DEFENDER, SANDAL, PASS_SANDAL, STACK_MARKER, ARENA, TOMBSTONE, HIT_EFFECT, TOPPLE_EFFECT }

const CHARACTER_MODELS: Dictionary = {
	Kind.ATTACKER: "res://assets/kenney/characters/character-raider.glb",
	Kind.DEFENDER: "res://assets/kenney/characters/character-knight.glb",
}
const COLUMN_MODEL: String = "res://assets/kenney/arena/column-damaged.glb"
## Animation names in the Kenney character files, per visual state.
const STATE_ANIMATIONS: Dictionary = {
	&"idle": &"idle",
	&"run": &"sprint",
	&"carry": &"holding-both",
	&"dash": &"sprint",
}
const LOOPING_ANIMATIONS: Array[StringName] = [&"idle", &"sprint", &"walk", &"holding-both"]
const THROW_ANIMATION: StringName = &"attack-melee-right"
const SOLE_COLOR: Color = Color8(144, 87, 65)
const STRAP_COLOR: Color = Color8(230, 185, 110)
const ARENA_FLOOR_COLOR: Color = Color("5c4332")
const LINE_COLOR: Color = Color(0.78, 0.66, 0.45)
const SHADOW_COLOR: Color = Color(0.05, 0.08, 0.04, 0.5)
## Blob shadow size against the drawing radius, and its shift away from the sun, in radii (x, z).
const SHADOW_SIZE_FACTOR: float = 3.0
const SHADOW_OFFSET: Vector2 = Vector2(0.25, 0.3)
const OUTLINE_SHADER: Shader = preload("res://scripts/view3d/outline.gdshader")
const OUTLINE_EDGE_SHADER: Shader = preload("res://scripts/view3d/outline_edge.gdshader")
## Screen-pixel width of the team ring and of the dark keyline outside it.
const OUTLINE_RING_PX: float = 3.0
const OUTLINE_EDGE_PX: float = 1.2
## Both hulls write alpha, so they sort by distance in the transparent pass. Render priority fixes the order.
const OUTLINE_EDGE_PRIORITY: int = 0
const OUTLINE_RING_PRIORITY: int = 1
const OUTLINE_EDGE_COLOR: Color = Color(0.04, 0.06, 0.1, 0.9)
const FLASH_ALPHA: float = 0.85
const DASH_TRANSPARENCY: float = 0.55
const GUIDE_DASH_RADIANS: float = 0.07
const GUIDE_GAP_RADIANS: float = 0.05

## What this scene shows.
@export var kind: Kind = Kind.ATTACKER
## Drawing radius in pixels. Never a hitbox.
@export var radius: float = 18.0
## Height of a character model in pixels.
@export var model_height: float = 64.0
## Colour of rings and flat markers.
@export var color: Color = Color(0.96, 0.84, 0.55)
## Seconds an effect ring lasts.
@export_range(0.05, 2.0, 0.05, "suffix:s") var effect_time: float = 0.35
## Height above the floor of the model origin, in pixels.
@export var lift: float = 0.0

var _node: Node3D
var _flat: Node3D
var _pivot: Node3D
var _view: World3DView
var _yaw: float = 0.0
var _animation_player: AnimationPlayer
var _tint: StandardMaterial3D
var _outline: ShaderMaterial
var _body_meshes: Array[GeometryInstance3D] = []
var _strap_material: StandardMaterial3D
var _ring_material: StandardMaterial3D
static var _shadow_material: StandardMaterial3D
var _extent: Vector2 = Vector2(1080.0, 600.0)
var _guide_radii: Vector2 = Vector2.ZERO
var _tween: Tween
var _state: StringName = &""


func _ready() -> void:
	if kind == Kind.ARENA and World3DView.find(get_tree()) == null:
		_view = World3DView.new()
		add_child(_view)
	else:
		_view = World3DView.find(get_tree())
	if _view == null:
		return
	_node = Node3D.new()
	_node.name = "Depth_%s" % Kind.keys()[kind]
	_view.add_to_scene(_node)
	_flat = Node3D.new()
	_flat.scale = Vector3(1.0, 1.0, 1.0 / World3DView.GROUND_STRETCH)
	_node.add_child(_flat)
	_pivot = Node3D.new()
	_node.add_child(_pivot)
	if kind != Kind.ARENA:
		_sync_transform()
	_build()
	if kind == Kind.HIT_EFFECT or kind == Kind.TOPPLE_EFFECT:
		_run_effect()


func _exit_tree() -> void:
	if _node != null and is_instance_valid(_node):
		_node.queue_free()
	_node = null


func _process(_delta: float) -> void:
	if _node == null or kind == Kind.ARENA:
		return
	_sync_transform()


func play(state: StringName) -> void:
	if _node == null:
		return
	_state = state
	match state:
		&"throw":
			_play_once(THROW_ANIMATION)
		&"hit":
			_flash()
		&"dash":
			_play_loop(STATE_ANIMATIONS[state])
			_fade_dash()
		&"die":
			pass
		_:
			if STATE_ANIMATIONS.has(state):
				_play_loop(STATE_ANIMATIONS[state])


func set_facing(angle: float) -> void:
	_yaw = World3DView.model_yaw(angle)


func set_team_color(new_color: Color) -> void:
	super.set_team_color(new_color)
	if _outline != null:
		_outline.set_shader_parameter(&"outline_color", new_color)
	if _strap_material != null:
		_strap_material.albedo_color = new_color


func set_extent(extent: Vector2) -> void:
	_extent = extent
	_rebuild_arena()


func set_guide_radii(throw_radius: float, orbit_radius: float) -> void:
	_guide_radii = Vector2(throw_radius, orbit_radius)
	_rebuild_arena()


func _sync_transform() -> void:
	_node.visible = is_visible_in_tree()
	_node.position = World3DView.ground(global_position, lift * scale.x)
	_pivot.transform = _standing_transform() if _is_standing() else Transform3D(Basis(Vector3.UP, _yaw), Vector3.ZERO)


## True for a sandal that a stack holds in a teepee slot. Loose sandals lie flat.
func _is_standing() -> bool:
	if kind != Kind.SANDAL and kind != Kind.PASS_SANDAL:
		return false
	var holder: Node = get_parent()
	var angle: Variant = holder.get("lean_angle") if holder != null else null
	return angle is float and angle > 0.0


# The model lies along +z. It stands on its edge with the length up and the sole plane tangent to the ring,
# then tilts about its foot toward the centre, so the three tips meet at the apex.
func _standing_transform() -> Transform3D:
	var holder: Node = get_parent()
	var lean: Vector2 = holder.get("lean_direction")
	var toward: Vector3 = World3DView.ground(lean)
	var stand: Basis = Basis(Vector3.UP, atan2(-toward.x, -toward.z)) * Basis(Vector3.RIGHT, -PI * 0.5)
	var tilt: Basis = Basis(Vector3.UP.cross(toward).normalized(), float(holder.get("lean_angle")))
	return Transform3D(tilt, Vector3.ZERO) * Transform3D(stand, Vector3(0.0, radius * 1.5, 0.0))


func _build() -> void:
	match kind:
		Kind.ATTACKER, Kind.DEFENDER:
			_build_character()
		Kind.SANDAL, Kind.PASS_SANDAL:
			_build_sandal()
		Kind.STACK_MARKER:
			_add_ring(radius * 0.8, radius, color)
		Kind.TOMBSTONE:
			_build_tombstone()
		Kind.ARENA:
			_rebuild_arena()
		Kind.HIT_EFFECT, Kind.TOPPLE_EFFECT:
			_ring_material = MeshBuilder3D.flat_material(color)
			_add_mesh(MeshBuilder3D.annulus(radius * 0.85, radius), _ring_material)
	_node.scale = Vector3.ONE * scale.x


# Team colour shows as an outline, never as a tint, so every model keeps its own colours. A thin dark keyline
# outside the team ring keeps red and blue readable on the pitch. The ring always paints over the keyline.
func _make_outline() -> ShaderMaterial:
	var chain: Array[ShaderMaterial] = DepthVisual.outline_chain(team_color)
	_outline = chain[1]
	return chain[0]


## Returns [keyline, ring]. Set the keyline as the mesh overlay. The ring is its next pass and takes the team colour.
static func outline_chain(ring_color: Color) -> Array[ShaderMaterial]:
	var ring: ShaderMaterial = ShaderMaterial.new()
	ring.shader = OUTLINE_SHADER
	ring.render_priority = OUTLINE_RING_PRIORITY
	ring.set_shader_parameter(&"outline_color", ring_color)
	ring.set_shader_parameter(&"width_px", OUTLINE_RING_PX)
	var keyline: ShaderMaterial = ShaderMaterial.new()
	keyline.shader = OUTLINE_EDGE_SHADER
	keyline.render_priority = OUTLINE_EDGE_PRIORITY
	keyline.set_shader_parameter(&"outline_color", OUTLINE_EDGE_COLOR)
	keyline.set_shader_parameter(&"width_px", OUTLINE_RING_PX + OUTLINE_EDGE_PX)
	keyline.next_pass = ring
	return [keyline, ring]


func _build_character() -> void:
	var path: String = model_path if model_path != "" else CHARACTER_MODELS[kind]
	var packed: PackedScene = load(path) as PackedScene
	var model: Node3D = packed.instantiate() as Node3D
	model.scale = Vector3.ONE * model_height * model_scale
	_pivot.add_child(model)
	_tint = MeshBuilder3D.flat_material(Color(Color.WHITE, 0.0))
	_tint.next_pass = _make_outline()
	for mesh: Node in model.find_children("*", "MeshInstance3D", true, false):
		var instance: MeshInstance3D = mesh as MeshInstance3D
		instance.material_overlay = _tint
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		_body_meshes.append(instance)
	_animation_player = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _animation_player != null:
		for animation_name: StringName in LOOPING_ANIMATIONS:
			if _animation_player.has_animation(animation_name):
				_animation_player.get_animation(animation_name).loop_mode = Animation.LOOP_LINEAR
		_play_loop(&"idle")
	var disc: MeshInstance3D = MeshInstance3D.new()
	var disc_mesh: PlaneMesh = PlaneMesh.new()
	disc_mesh.size = Vector2.ONE * radius * SHADOW_SIZE_FACTOR
	disc.mesh = disc_mesh
	disc.material_override = _soft_shadow_material()
	disc.position = Vector3(radius * SHADOW_OFFSET.x, -0.2, radius * SHADOW_OFFSET.y)
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flat.add_child(disc)
	if has_team_color:
		set_team_color(team_color)


# The pitch is unshaded, so a real light shadow cannot land on it. A radial-fade blob stays cheap on web
# and has no hard edge.
func _soft_shadow_material() -> StandardMaterial3D:
	if _shadow_material == null:
		var fade: Gradient = Gradient.new()
		fade.set_color(0, SHADOW_COLOR)
		fade.set_color(1, Color(SHADOW_COLOR, 0.0))
		var texture: GradientTexture2D = GradientTexture2D.new()
		texture.gradient = fade
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(0.5, 0.5)
		texture.fill_to = Vector2(0.5, 0.0)
		texture.width = 64
		texture.height = 64
		var material: StandardMaterial3D = MeshBuilder3D.flat_material(Color.WHITE)
		material.albedo_texture = texture
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_shadow_material = material
	return _shadow_material


func _build_sandal() -> void:
	var length: float = radius * 3.0
	var width: float = radius * 1.7
	var sole_height: float = 5.0
	var sole: MeshInstance3D = MeshInstance3D.new()
	var sole_mesh: CylinderMesh = CylinderMesh.new()
	sole_mesh.top_radius = 0.5
	sole_mesh.bottom_radius = 0.5
	sole_mesh.height = sole_height
	sole_mesh.radial_segments = 16
	sole_mesh.rings = 1
	sole.mesh = sole_mesh
	sole.scale = Vector3(width, 1.0, length)
	sole.position.y = sole_height * 0.5
	sole.material_override = MeshBuilder3D.flat_material(SOLE_COLOR)
	sole.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	sole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pivot.add_child(sole)
	_strap_material = MeshBuilder3D.flat_material(STRAP_COLOR)
	_strap_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_add_strap(Vector3(width * 0.8, 3.0, length * 0.14), Vector3(0.0, sole_height + 1.5, length * 0.12))
	_add_strap(Vector3(width * 0.2, 3.0, length * 0.2), Vector3(0.0, sole_height + 1.5, length * 0.36))
	if kind == Kind.PASS_SANDAL:
		var ring: StandardMaterial3D = MeshBuilder3D.flat_material(Color(1.0, 0.953, 0.769))
		_add_mesh(MeshBuilder3D.annulus(radius * 1.5 - 2.0, radius * 1.5 + 2.0), ring)
	if has_team_color:
		set_team_color(team_color)


func _add_strap(size: Vector3, at: Vector3) -> void:
	var strap: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = size
	strap.mesh = box
	strap.position = at
	strap.material_override = _strap_material
	strap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pivot.add_child(strap)


func _build_tombstone() -> void:
	var packed: PackedScene = load(COLUMN_MODEL) as PackedScene
	var model: Node3D = packed.instantiate() as Node3D
	model.scale = Vector3.ONE * radius * 1.4
	_node.add_child(model)
	_add_ring(radius * 0.9, radius * 1.1, color)


func _add_ring(inner: float, outer: float, ring_color: Color) -> void:
	_ring_material = MeshBuilder3D.flat_material(ring_color)
	_add_mesh(MeshBuilder3D.annulus(inner, outer), _ring_material)


func _add_mesh(mesh: Mesh, material: Material, at: Vector3 = Vector3(0.0, 0.2, 0.0)) -> MeshInstance3D:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flat.add_child(instance)
	return instance


func _rebuild_arena() -> void:
	if _node == null or kind != Kind.ARENA:
		return
	for child: Node in _node.get_children():
		if child != _flat and child != _pivot:
			child.queue_free()
	var half: Vector2 = _extent * 0.5
	var centre: Vector3 = World3DView.ground(global_position)
	_node.position = centre
	var floor_mesh: MeshInstance3D = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(_extent.x, _extent.y)
	floor_mesh.mesh = plane
	floor_mesh.material_override = MeshBuilder3D.lit_material(ARENA_FLOOR_COLOR)
	floor_mesh.scale = Vector3(1.0, 1.0, 1.0 / World3DView.GROUND_STRETCH)
	floor_mesh.position.y = -0.5
	_node.add_child(floor_mesh)
	var lines: MeshBuilder3D.Lines = MeshBuilder3D.Lines.new()
	lines.outline(half, 4.0, LINE_COLOR)
	lines.rect(Rect2(-1.0, -half.y, 2.0, half.y * 2.0), Color(LINE_COLOR, 0.35))
	if _guide_radii.x > 0.0:
		lines.dashed_ring(_guide_radii.x, 3.0, GUIDE_DASH_RADIANS, GUIDE_GAP_RADIANS, LINE_COLOR)
	if _guide_radii.y > 0.0:
		lines.dashed_ring(_guide_radii.y, 2.0, GUIDE_DASH_RADIANS, GUIDE_GAP_RADIANS, LINE_COLOR)
	var line_node: MeshInstance3D = MeshInstance3D.new()
	line_node.mesh = lines.build()
	line_node.material_override = MeshBuilder3D.flat_material(Color.WHITE, true)
	line_node.position.y = 0.3
	line_node.scale = Vector3(1.0, 1.0, 1.0 / World3DView.GROUND_STRETCH)
	_node.add_child(line_node)
	KampongScenery.new(1.0 / World3DView.GROUND_STRETCH).build(_node, half)


func _play_loop(animation_name: StringName) -> void:
	if _animation_player != null and _animation_player.has_animation(animation_name):
		if _animation_player.current_animation != animation_name:
			_animation_player.play(animation_name, 0.12)


func _play_once(animation_name: StringName) -> void:
	if _animation_player == null or not _animation_player.has_animation(animation_name):
		return
	_animation_player.play(animation_name, 0.05)
	_animation_player.queue(&"idle")


func _flash() -> void:
	if _tint == null:
		return
	_restart_tween()
	_tint.albedo_color = Color(Color.WHITE, FLASH_ALPHA)
	_tween.tween_property(_tint, "albedo_color", Color(Color.WHITE, 0.0), 0.25)


func _fade_dash() -> void:
	_restart_tween()
	_set_transparency(DASH_TRANSPARENCY)
	_tween.tween_interval(0.25)
	_tween.tween_method(_set_transparency, DASH_TRANSPARENCY, 0.0, 0.1)


func _set_transparency(value: float) -> void:
	for mesh: GeometryInstance3D in _body_meshes:
		mesh.transparency = value


func _restart_tween() -> void:
	if _tween != null:
		_tween.kill()
	_tween = create_tween()


func _run_effect() -> void:
	_restart_tween()
	_tween.set_parallel(true)
	_tween.tween_property(_node, "scale", _node.scale * 2.4, effect_time)
	_tween.tween_property(_ring_material, "albedo_color:a", 0.0, effect_time)
	_tween.chain().tween_callback(queue_free)
