class_name ReplayStage
extends CanvasLayer
## Full-screen 3D layer for the replay. It owns a SubViewport with its own World3D, the room geometry, the gunmen and the hero camera.

## Camera shake in world units on a hit. Set to 0.0 to turn the shake off.
const SHAKE: float = 0.04
## Pixels per world unit when mapping the 2D room to the 3D floor.
const PX_PER_UNIT: float = 60.0
## Hero eye height in world units.
const EYE_HEIGHT: float = 1.6
## Resting horizontal field of view in degrees.
const BASE_FOV: float = 80.0
## Narrower field of view while the camera looks at the swapped gunman, so he reads larger.
const FOCUS_FOV: float = 62.0
## Distance in world units from the arena edge to the backdrop walls.
const WALL_MARGIN: float = 6.0
## Height of the backdrop walls in world units.
const WALL_HEIGHT: float = 30.0
## Cover block height. Tall enough to block chest-high bullets.
const COVER_HEIGHT: float = 1.9
## Camera pitch in radians. A slight look down puts more floor and the gunmen in the middle of the frame.
const LOOK_DOWN: float = -0.14
const VOID_COLOR: Color = Color("08080c")
const CYAN: Color = Color("19e3ff")

## Effects node for telegraphs, bullets and flashes.
var fx: ReplayFx = ReplayFx.new()
## One figure per gunman, same indices as the room data.
var figures: Array[Figure3D] = []
## Camera, a child of the rig.
var camera: Camera3D = Camera3D.new()
## Title card and fade to black.
var overlay: ReelOverlay = ReelOverlay.new()

var _viewport: SubViewport = SubViewport.new()
var _world: Node3D = Node3D.new()
var _rig: Node3D = Node3D.new()
var _shake_amp: float = 0.0
var _floor_mat: ShaderMaterial
var _cover_mat: StandardMaterial3D = _unshaded(Color("14141c"))
var _edge_mat: StandardMaterial3D = _unshaded(CYAN)


func _init() -> void:
	layer = 5
	visible = false
	var container: SubViewportContainer = SubViewportContainer.new()
	container.stretch = true
	container.size = Vector2(540, 960)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)
	_viewport.own_world_3d = true
	_viewport.size = Vector2i(540, 960)
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.handle_input_locally = false
	container.add_child(_viewport)
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = VOID_COLOR
	var world_env: WorldEnvironment = WorldEnvironment.new()
	world_env.environment = environment
	_viewport.add_child(world_env)
	_viewport.add_child(_world)
	_world.add_child(fx)
	_viewport.add_child(_rig)
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.fov = BASE_FOV
	camera.near = 0.05
	camera.rotation.x = LOOK_DOWN
	camera.far = 60.0
	_rig.add_child(camera)
	_floor_mat = ShaderMaterial.new()
	_floor_mat.shader = load("res://shaders/floor_grid.gdshader")
	add_child(overlay)
	_add_backdrop()


func _process(_delta: float) -> void:
	if _shake_amp <= 0.001:
		return
	camera.h_offset = randf_range(-1.0, 1.0) * _shake_amp
	camera.v_offset = randf_range(-1.0, 1.0) * _shake_amp
	_shake_amp = lerpf(_shake_amp, 0.0, 0.25)
	if _shake_amp <= 0.001:
		camera.h_offset = 0.0
		camera.v_offset = 0.0


## Maps a 2D room point to the 3D floor.
static func to3(point: Vector2, height: float = 0.0) -> Vector3:
	return Vector3(point.x / PX_PER_UNIT, height, point.y / PX_PER_UNIT)


## Returns the camera yaw that looks from [param from] toward [param to] on the floor.
static func yaw_to(from: Vector3, to: Vector3) -> float:
	return atan2(-(to.x - from.x), -(to.z - from.z))


## Colors the hero's bullets with [param color]. A bought coat ([param coated]) also tints the arena outline.
func set_hero_color(color: Color, coated: bool) -> void:
	fx.set_hero_color(color)
	_edge_mat.albedo_color = color if coated else CYAN


## Shows or hides the layer and pauses 3D rendering while hidden.
func show_view(shown: bool) -> void:
	visible = shown
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if shown else SubViewport.UPDATE_DISABLED


## Rebuilds the floor, cover blocks and gunmen for [param room], and puts the camera at the hero.
func build(room: Dictionary) -> void:
	for child: Node in _world.get_children():
		if child != fx:
			child.queue_free()
	fx.clear_telegraphs()
	figures.clear()
	var floor_rect: Rect2 = Rooms.FLOOR
	var floor_mesh: PlaneMesh = PlaneMesh.new()
	floor_mesh.size = floor_rect.size / PX_PER_UNIT
	var floor_node: MeshInstance3D = MeshInstance3D.new()
	floor_node.mesh = floor_mesh
	floor_node.material_override = _floor_mat
	floor_node.position = to3(floor_rect.get_center())
	_world.add_child(floor_node)
	_add_outline(floor_rect, 0.05, 0.04)
	for cover: Rect2 in room["covers"]:
		_add_cover(cover)
	var hero: Vector2 = room["hero"]
	var state: RoomState = RoomState.from_room(room)
	var alive: Array = room.get("alive", [])
	for i: int in state.guns.size():
		var figure: Figure3D = add_figure(to3(state.guns[i]), to3(hero), state.kinds[i], state.facings[i])
		figure.set_ring(false)
		figure.visible = i >= alive.size() or bool(alive[i])
	overlay.reset()
	set_eye(to3(hero), 0.0)
	camera.fov = BASE_FOV


## Adds a gunman at floor point [param at] facing [param toward], and returns him. A new reinforcement shows its ring.
func add_figure(at: Vector3, toward: Vector3, kind: int = RoomState.Kind.PISTOL, facing: int = RoomState.Facing.UP) -> Figure3D:
	var figure: Figure3D = Figure3D.new()
	figure.position = at
	_world.add_child(figure)
	figure.configure(kind, facing)
	figure.face(toward)
	figure.set_ring(true)
	figures.append(figure)
	return figure


## Returns the floor point under the camera rig.
func hero_floor_pos() -> Vector3:
	return Vector3(_rig.position.x, 0.0, _rig.position.z)


## Places the camera rig at floor point [param floor_pos] at eye height, facing [param yaw].
func set_eye(floor_pos: Vector3, yaw: float) -> void:
	_rig.position = Vector3(floor_pos.x, EYE_HEIGHT, floor_pos.z)
	_rig.rotation.y = yaw


## Returns the camera rig, which tweens use for position and yaw.
func rig() -> Node3D:
	return _rig


## Starts a camera shake scaled by [constant SHAKE].
func shake() -> void:
	_shake_amp = SHAKE


## Adds four wall quads around the arena. One shader draws the dark panels, the neon window strips and the horizon band.
func _add_backdrop() -> void:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = load("res://shaders/backdrop.gdshader")
	var center: Vector3 = to3(Rooms.FLOOR.get_center())
	var half: Vector3 = Vector3(Rooms.FLOOR.size.x, 0.0, Rooms.FLOOR.size.y) / PX_PER_UNIT * 0.5 + Vector3(WALL_MARGIN, 0.0, WALL_MARGIN)
	var walls: Array[Dictionary] = [
		{"at": Vector3(half.x, 0, 0), "yaw": -PI * 0.5, "width": half.z * 2.0},
		{"at": Vector3(-half.x, 0, 0), "yaw": PI * 0.5, "width": half.z * 2.0},
		{"at": Vector3(0, 0, half.z), "yaw": PI, "width": half.x * 2.0},
		{"at": Vector3(0, 0, -half.z), "yaw": 0.0, "width": half.x * 2.0}]
	for wall: Dictionary in walls:
		var quad: QuadMesh = QuadMesh.new()
		quad.size = Vector2(float(wall["width"]) + WALL_MARGIN * 2.0, WALL_HEIGHT)
		var node: MeshInstance3D = MeshInstance3D.new()
		node.mesh = quad
		node.material_override = material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.position = center + Vector3(wall["at"]) + Vector3(0, WALL_HEIGHT * 0.5, 0)
		node.rotation.y = float(wall["yaw"])
		_viewport.add_child(node)


func _add_cover(cover: Rect2) -> void:
	var size: Vector3 = Vector3(cover.size.x, 0.0, cover.size.y) / PX_PER_UNIT
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(size.x, COVER_HEIGHT, size.z)
	var node: MeshInstance3D = MeshInstance3D.new()
	node.mesh = box
	node.material_override = _cover_mat
	node.position = to3(cover.get_center(), COVER_HEIGHT * 0.5)
	_world.add_child(node)
	_add_outline(cover, COVER_HEIGHT, 0.03)
	_add_outline(cover, 0.02, 0.03)
	for corner: Vector2 in [cover.position, Vector2(cover.end.x, cover.position.y), cover.end, Vector2(cover.position.x, cover.end.y)]:
		var post: MeshInstance3D = fx.beam(to3(corner, 0.0), to3(corner, COVER_HEIGHT), 0.03, 0.03, _edge_mat)
		_world.add_child(post)


func _add_outline(rect: Rect2, height: float, width: float) -> void:
	var corners: Array[Vector3] = [to3(rect.position, height), to3(Vector2(rect.end.x, rect.position.y), height), to3(rect.end, height), to3(Vector2(rect.position.x, rect.end.y), height)]
	for i: int in 4:
		_world.add_child(fx.beam(corners[i], corners[(i + 1) % 4], width, width, _edge_mat))


func _unshaded(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	return material
