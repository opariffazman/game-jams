class_name World3DView
extends Node
## Renders the match in 3D behind the 2D world.
##
## Gameplay stays 2D physics. Every 3D visual copies the ground position of its 2D logic node here.
## One [SubViewport] holds an orthographic tilted [Camera3D], set by [ViewProjection]. A texture layer
## below the 2D world shows the result, so the aim preview, the HUD and the touch controls draw on top.
##
## A 2D arena point (x, y) is the 3D ground point (x, 0, y). [ViewProjection] owns the matching screen maths,
## so overlays and touch input use the same camera as the picture.

## Group the view joins. Visuals find it by this name.
const GROUP: StringName = &"world3d_view"
## Ground depth scale. The tilted camera needs none, so ground points map one to one.
const GROUND_STRETCH: float = 1.0
## Seconds the camera takes to move in on the build and back out.
const BUILD_DOLLY_TIME: float = 0.45
## Distance of the camera from the point it looks at, in pixels.
const CAMERA_DISTANCE: float = 2400.0
## Render size limits as a multiple of the logical viewport. A phone renders at its screen size.
const MIN_RENDER_SCALE: float = 1.0
const MAX_RENDER_SCALE: float = 2.0
## Quality block. Lower these on a slow device.
const MSAA_MODE: Viewport.MSAA = Viewport.MSAA_4X
const SHADOWS_ENABLED: bool = true
const SHADOW_ATLAS_SIZE: int = 4096
const SHADOW_SPLITS_MODE: DirectionalLight3D.ShadowMode = DirectionalLight3D.SHADOW_ORTHOGONAL
## Far limit of the sun shadow in pixels. The camera sits CAMERA_DISTANCE away. Above about 3300 the cascade spreads too thin and the shadows vanish.
const SHADOW_MAX_DISTANCE: float = 3300.0
const SHADOW_SOFT_QUALITY: RenderingServer.ShadowQuality = RenderingServer.SHADOW_QUALITY_SOFT_ULTRA
## Share of light a shadow removes. Below 1.0 keeps the shadow soft and tinted by the ambient.
const SHADOW_OPACITY: float = 0.85
const SHADOW_BIAS: float = 0.3
const SHADOW_NORMAL_BIAS: float = 2.0
const TONEMAP_MODE: Environment.ToneMapper = Environment.TONE_MAPPER_FILMIC
const SUN_ENERGY: float = 0.8
const AMBIENT_ENERGY: float = 0.5
const GLOW_ENABLED: bool = false
const GLOW_INTENSITY: float = 0.35
const GLOW_BLOOM: float = 0.04
const ADJUST_CONTRAST: float = 1.08
const ADJUST_SATURATION: float = 1.05
## Colour behind the arena. It matches the 2D surround.
const BACKGROUND_COLOR: Color = Color("2a6b3d")
## Canvas layer of the 3D picture. It sits below the default 2D layer.
const CANVAS_LAYER: int = -10

var _viewport: SubViewport
var _scene_root: Node3D
var _camera: Camera3D
var _picture: TextureRect
var _dolly: Tween


static func find(tree: SceneTree) -> World3DView:
	return tree.get_first_node_in_group(GROUP) as World3DView


## Converts a 2D arena point to a 3D position. [param height] is above the floor.
static func ground(point: Vector2, height: float = 0.0) -> Vector3:
	return Vector3(point.x, height, point.y / GROUND_STRETCH)


## Direction angle, around the vertical axis, that makes a +z facing model point along the screen angle [param angle].
static func model_yaw(angle: float) -> float:
	return atan2(cos(angle), sin(angle) / GROUND_STRETCH)


func _ready() -> void:
	add_to_group(GROUP)
	ViewProjection.active = true
	ViewProjection.build_blend = 0.0
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.msaa_3d = MSAA_MODE
	_viewport.use_hdr_2d = false
	RenderingServer.directional_shadow_atlas_set_size(SHADOW_ATLAS_SIZE, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(SHADOW_SOFT_QUALITY)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.transparent_bg = false
	add_child(_viewport)
	_scene_root = Node3D.new()
	_scene_root.name = "Scene3D"
	_viewport.add_child(_scene_root)
	_build_environment()
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.near = 1.0
	_camera.far = CAMERA_DISTANCE * 3.0
	_camera.basis = ViewProjection.camera_basis()
	_viewport.add_child(_camera)
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = CANVAS_LAYER
	add_child(layer)
	_picture = TextureRect.new()
	_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_picture.set_anchors_preset(Control.PRESET_FULL_RECT)
	_picture.stretch_mode = TextureRect.STRETCH_SCALE
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.texture = _viewport.get_texture()
	layer.add_child(_picture)
	_follow_main_camera()
	_connect_round_manager.call_deferred()


func _exit_tree() -> void:
	ViewProjection.aspect_fit = 1.0
	ViewProjection.active = false
	ViewProjection.build_blend = 0.0


func _process(_delta: float) -> void:
	_follow_main_camera()


# The round manager is a sibling that enters the tree after the arena, so the link is made one frame later.
func _connect_round_manager() -> void:
	if not is_inside_tree():
		return
	var manager: RoundManager = get_tree().get_first_node_in_group(RoundManager.GROUP) as RoundManager
	if manager != null and not manager.build_view_changed.is_connected(set_build_view):
		manager.build_view_changed.connect(set_build_view)


## Moves the camera in on [param focus] while [param active] is true, and back out when it is false.
func set_build_view(active: bool, focus: Vector2 = Vector2.ZERO) -> void:
	if active:
		ViewProjection.build_focus = focus
	if _dolly != null and _dolly.is_valid():
		_dolly.kill()
	_dolly = create_tween()
	_dolly.tween_property(ViewProjection, "build_blend", 1.0 if active else 0.0, BUILD_DOLLY_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Adds [param node] to the 3D scene.
func add_to_scene(node: Node3D) -> void:
	_scene_root.add_child(node)


func _build_environment() -> void:
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = BACKGROUND_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.86, 0.93, 1.0)
	environment.ambient_light_energy = AMBIENT_ENERGY
	environment.tonemap_mode = TONEMAP_MODE
	environment.glow_enabled = GLOW_ENABLED
	environment.glow_intensity = GLOW_INTENSITY
	environment.glow_bloom = GLOW_BLOOM
	environment.glow_hdr_threshold = 1.0
	environment.adjustment_enabled = true
	environment.adjustment_contrast = ADJUST_CONTRAST
	environment.adjustment_saturation = ADJUST_SATURATION
	var holder: WorldEnvironment = WorldEnvironment.new()
	holder.environment = environment
	_viewport.add_child(holder)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.shadow_enabled = SHADOWS_ENABLED
	sun.directional_shadow_mode = SHADOW_SPLITS_MODE
	sun.directional_shadow_max_distance = SHADOW_MAX_DISTANCE
	sun.shadow_bias = SHADOW_BIAS
	sun.shadow_normal_bias = SHADOW_NORMAL_BIAS
	sun.shadow_opacity = SHADOW_OPACITY
	sun.shadow_blur = 1.0
	sun.light_energy = SUN_ENERGY
	sun.light_color = Color(1.0, 0.92, 0.76)
	sun.rotation_degrees = Vector3(-36.0, -35.0, 0.0)
	_viewport.add_child(sun)


# The 2D camera zooms and shakes. The 3D camera copies the canvas transform, so both show the same area.
func _follow_main_camera() -> void:
	var main: Viewport = get_viewport()
	var visible_size: Vector2 = main.get_visible_rect().size
	if visible_size.x < 1.0 or visible_size.y < 1.0:
		return
	var window_height: float = float(get_window().size.y)
	var render_scale: float = clampf(window_height / visible_size.y, MIN_RENDER_SCALE, MAX_RENDER_SCALE)
	var wanted: Vector2i = Vector2i((visible_size * render_scale).round())
	if _viewport.size != wanted:
		_viewport.size = wanted
	ViewProjection.aspect_fit = ViewProjection.fit_for(visible_size)
	_camera.basis = ViewProjection.camera_basis()
	var centre: Vector2 = ViewProjection.centre(main)
	_camera.position = ground(centre) + ViewProjection.camera_basis().z * CAMERA_DISTANCE
	_camera.size = visible_size.y / (ViewProjection.zoom(main) * ViewProjection.fit * ViewProjection.aspect_fit)
