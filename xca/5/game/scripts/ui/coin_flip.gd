class_name CoinFlip
extends SubViewportContainer
## A 3D gold coin that tosses, spins and lands with the result team's face up.
##
## Draws in its own transparent [SubViewport], so it sits on top of the match like any HUD control.

signal landed

const SIZE_PX: int = 260
const COIN_RADIUS: float = 0.5
const COIN_THICKNESS: float = 0.16
const FACE_RADIUS: float = 0.4
const TOSS_HEIGHT: float = 1.1
const HALF_TURNS: int = 7
const REST_TILT: float = 0.35
const GOLD: Color = Color(1.0, 0.78, 0.2)

var _pivot: Node3D
var _face_top: MeshInstance3D
var _face_bottom: MeshInstance3D
var _tween: Tween


func _init() -> void:
	custom_minimum_size = Vector2(SIZE_PX, SIZE_PX)
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var viewport: SubViewport = SubViewport.new()
	viewport.transparent_bg = true
	viewport.size = Vector2i(SIZE_PX, SIZE_PX)
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(viewport)

	var camera: Camera3D = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.6
	camera.position = Vector3(0.0, 0.9, 4.0)
	camera.rotation.x = -0.2
	viewport.add_child(camera)

	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.5, 0.0)
	sun.light_energy = 1.1
	viewport.add_child(sun)
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(1.0, 0.95, 0.85)
	environment.ambient_light_energy = 0.7
	var world_environment: WorldEnvironment = WorldEnvironment.new()
	world_environment.environment = environment
	viewport.add_child(world_environment)

	_pivot = Node3D.new()
	viewport.add_child(_pivot)
	var rim: MeshInstance3D = MeshInstance3D.new()
	var rim_mesh: CylinderMesh = CylinderMesh.new()
	rim_mesh.top_radius = COIN_RADIUS
	rim_mesh.bottom_radius = COIN_RADIUS
	rim_mesh.height = COIN_THICKNESS
	rim_mesh.radial_segments = 48
	rim_mesh.rings = 1
	rim.mesh = rim_mesh
	rim.material_override = _material(GOLD, 0.35, 0.4)
	_pivot.add_child(rim)
	_face_top = _make_face(1.0)
	_face_bottom = _make_face(-1.0)


## Tosses the coin. [param face_colors] holds the colour of team 0 and team 1, [param result_team] lands face up.
func play(face_colors: Array[Color], result_team: int, duration: float) -> void:
	stop()
	_face_top.material_override = _material(face_colors[0], 0.1, 0.6)
	_face_bottom.material_override = _material(face_colors[1], 0.1, 0.6)
	visible = true
	_pivot.position = Vector3.ZERO
	_pivot.rotation = Vector3.ZERO
	var half_turns: int = HALF_TURNS if result_team == 0 else HALF_TURNS + 1
	var final_angle: float = float(half_turns) * PI
	_tween = create_tween()
	_tween.tween_method(_toss.bind(final_angle), 0.0, 1.0, duration)
	_tween.tween_callback(landed.emit)


## Stops the toss and hides the coin.
func stop() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	visible = false


func _toss(progress: float, final_angle: float) -> void:
	var eased: float = 1.0 - pow(1.0 - progress, 2.0)
	_pivot.position.y = 4.0 * TOSS_HEIGHT * progress * (1.0 - progress)
	var tilt: float = REST_TILT * sin(progress * PI)
	_pivot.rotation = Vector3(final_angle * eased + tilt, 0.0, 0.0)


func _make_face(side: float) -> MeshInstance3D:
	var face: MeshInstance3D = MeshInstance3D.new()
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = FACE_RADIUS
	mesh.bottom_radius = FACE_RADIUS
	mesh.height = 0.02
	mesh.radial_segments = 48
	mesh.rings = 1
	face.mesh = mesh
	face.position.y = side * (COIN_THICKNESS * 0.5 + 0.004)
	_pivot.add_child(face)
	return face


func _material(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	return material
