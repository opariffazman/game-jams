class_name HowToPlay
extends Control
## Four icon-only cards that replay the real 3D gameplay assets: topple, gather, build, defend.
##
## Swipe, the arrow buttons or the arrow keys change the card. The close button or Esc leaves.

signal closed

const CARD_COUNT: int = 4
const LOOP_SECONDS: float = 3.2
const BACKDROP: Color = Color(0.1, 0.07, 0.04, 0.96)
const PANEL: Color = Color("3b2d1e")
const AMBER: Color = Color("ffc857")
const CREAM: Color = Color("fff3da")
const SWIPE_DISTANCE: float = 48.0
const RAIDER: String = "res://assets/kenney/characters/character-raider.glb"
const KNIGHT: String = "res://assets/kenney/characters/character-knight.glb"
const COLUMN: String = "res://assets/kenney/arena/column-damaged.glb"
const FLOOR_COLOR: Color = Color("5c4332")
const SOLE_COLOR: Color = Color8(144, 87, 65)
const STRAP_COLOR: Color = Color8(230, 185, 110)
const BLUE: Color = Color("3d9bff")
const RED: Color = Color("ff5a45")
const GROUND_PITCH_DEGREES: float = 42.0
const MODEL_HEIGHT: float = 96.0
const SANDAL_RADIUS: float = 20.0
const VIEW_WIDTH: float = 520.0
const MIN_VIEW_HEIGHT: float = 340.0
const TEAM_TINT_ALPHA: float = 0.45

var card: int = 0

var _time: float = 0.0
var _previous: TitleIconButton
var _next: TitleIconButton
var _close: TitleIconButton
var _drag_from: float = 0.0
var _dragging: bool = false
var _last_down: bool = false
var _last_msec: int = -1000
var _container: SubViewportContainer
var _viewport: SubViewport
var _camera: Camera3D
var _actors: Node3D
var _rig: Dictionary = {}
var _built_card: int = -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_view()
	_previous = TitleIconButton.new(TitleIconButton.Kind.PREV)
	_next = TitleIconButton.new(TitleIconButton.Kind.NEXT)
	_close = TitleIconButton.new(TitleIconButton.Kind.CLOSE)
	for button: TitleIconButton in [_previous, _next, _close]:
		add_child(button)
	_previous.pressed.connect(show_card.bind(-1, true))
	_next.pressed.connect(show_card.bind(1, true))
	_close.pressed.connect(close)
	resized.connect(layout)
	layout()


func _process(delta: float) -> void:
	_time = fmod(_time + delta, LOOP_SECONDS)
	if visible and _built_card != card:
		_rebuild_scene()
	if visible:
		_animate(_time / LOOP_SECONDS)
	queue_redraw()


## Places the buttons for the current size. Buttons are never under 12 percent of the short side.
func layout() -> void:
	var short: float = minf(size.x, size.y)
	var diameter: float = maxf(short * 0.13, 44.0 * RestartUiScale.pixels_per_css(get_viewport()))
	_place_view()
	var button_size: Vector2 = Vector2.ONE * diameter
	var margin: float = diameter * 0.35
	_close.size = button_size
	_close.position = Vector2(size.x - diameter - margin, margin)
	_previous.size = button_size
	_next.size = button_size
	_previous.position = Vector2(margin, size.y * 0.5 - diameter * 0.5)
	_next.position = Vector2(size.x - diameter - margin, size.y * 0.5 - diameter * 0.5)


func buttons() -> Array[TitleIconButton]:
	return [_previous, _next, _close]


func open() -> void:
	card = 0
	_time = 0.0
	visible = true
	_rebuild_scene()
	layout()
	_close.grab_focus()


func close() -> void:
	visible = false
	closed.emit()


func show_card(step: int, wrap: bool = false) -> void:
	card = posmod(card + step, CARD_COUNT) if wrap else clampi(card + step, 0, CARD_COUNT - 1)
	_time = 0.0
	_rebuild_scene()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and not key.echo:
		match key.keycode:
			KEY_ESCAPE:
				close()
			KEY_RIGHT, KEY_D:
				show_card(1, true)
			KEY_LEFT, KEY_A:
				show_card(-1, true)
			_:
				return
		get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	var down: bool
	var at: float
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		down = (event as InputEventMouseButton).pressed
		at = (event as InputEventMouseButton).position.x
	elif event is InputEventScreenTouch:
		down = (event as InputEventScreenTouch).pressed
		at = (event as InputEventScreenTouch).position.x
	else:
		return
	var now: int = Time.get_ticks_msec()
	if down == _last_down and now - _last_msec < 60:
		accept_event()
		return
	_last_down = down
	_last_msec = now
	if down:
		_drag_from = at
		_dragging = true
	elif _dragging:
		_dragging = false
		var travel: float = at - _drag_from
		if absf(travel) >= SWIPE_DISTANCE:
			show_card(-1 if travel > 0.0 else 1, true)
		else:
			show_card(1, true)
	accept_event()


func _panel_rect() -> Rect2:
	var short: float = minf(size.x, size.y)
	var panel_size: Vector2 = Vector2(size.x * 0.62, short * 0.68)
	return Rect2(size * 0.5 - panel_size * 0.5, panel_size)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BACKDROP)
	var short: float = minf(size.x, size.y)
	var panel: Rect2 = _panel_rect()
	draw_rect(panel, PANEL)
	draw_rect(panel, Color(AMBER, 0.9), false, maxf(2.0, short * 0.006))
	var dot_radius: float = short * 0.014
	for index: int in CARD_COUNT:
		var spot: Vector2 = Vector2(size.x * 0.5 + (index - (CARD_COUNT - 1) * 0.5) * dot_radius * 4.0, panel.end.y + short * 0.06)
		draw_circle(spot, dot_radius * (1.3 if index == card else 1.0), AMBER if index == card else Color(CREAM, 0.45))


# The cards use their own 3D world, so the match view is never touched. It looks through the same tilted camera.
func _build_view() -> void:
	_container = SubViewportContainer.new()
	_container.stretch = true
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_container)
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	_container.add_child(_viewport)
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("1c1710")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(1.0, 0.9, 0.76)
	environment.ambient_light_energy = 0.75
	var holder: WorldEnvironment = WorldEnvironment.new()
	holder.environment = environment
	_viewport.add_child(holder)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.light_energy = 0.7
	sun.light_color = Color(1.0, 0.88, 0.7)
	sun.rotation_degrees = Vector3(-55.0, -25.0, 0.0)
	_viewport.add_child(sun)
	var floor_mesh: MeshInstance3D = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(1600.0, 1200.0)
	floor_mesh.mesh = plane
	floor_mesh.material_override = _flat(FLOOR_COLOR)
	floor_mesh.position.y = -0.5
	_viewport.add_child(floor_mesh)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.near = 1.0
	_camera.far = 6000.0
	var basis: Basis = Basis.from_euler(Vector3(-deg_to_rad(GROUND_PITCH_DEGREES), 0.0, 0.0))
	_camera.basis = basis
	_camera.position = basis.z * 1500.0
	_viewport.add_child(_camera)
	_actors = Node3D.new()
	_viewport.add_child(_actors)


func _place_view() -> void:
	if _container == null:
		return
	var panel: Rect2 = _panel_rect().grow(-minf(size.x, size.y) * 0.02)
	_container.position = panel.position
	_container.size = panel.size
	_viewport.size = Vector2i(maxi(int(panel.size.x), 2), maxi(int(panel.size.y), 2))
	_camera.size = maxf(MIN_VIEW_HEIGHT, VIEW_WIDTH * panel.size.y / maxf(panel.size.x, 1.0))


func _flat(albedo: Color) -> StandardMaterial3D:
	return MeshBuilder3D.flat_material(albedo)


func _character(model_path: String, tint: Color) -> Dictionary:
	var node: Node3D = Node3D.new()
	var model: Node3D = (load(model_path) as PackedScene).instantiate() as Node3D
	model.scale = Vector3.ONE * MODEL_HEIGHT
	node.add_child(model)
	var overlay: StandardMaterial3D = _flat(Color(tint, TEAM_TINT_ALPHA))
	for mesh: Node in model.find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).material_overlay = overlay
	var player: AnimationPlayer = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player != null:
		for name: StringName in [&"idle", &"sprint", &"holding-both"]:
			if player.has_animation(name):
				player.get_animation(name).loop_mode = Animation.LOOP_LINEAR
	_actors.add_child(node)
	return {"node": node, "player": player}


func _play(actor: Dictionary, animation: StringName) -> void:
	var player: AnimationPlayer = actor["player"]
	if player != null and player.has_animation(animation) and player.current_animation != animation:
		player.play(animation)


# The same sole and straps as the sandal of the match view, lying along +z.
func _sandal(tint: Color) -> Node3D:
	var node: Node3D = Node3D.new()
	var length: float = SANDAL_RADIUS * 3.0
	var width: float = SANDAL_RADIUS * 1.7
	var sole: MeshInstance3D = MeshInstance3D.new()
	var sole_mesh: CylinderMesh = CylinderMesh.new()
	sole_mesh.top_radius = 0.5
	sole_mesh.bottom_radius = 0.5
	sole_mesh.height = 5.0
	sole_mesh.radial_segments = 16
	sole_mesh.rings = 1
	sole.mesh = sole_mesh
	sole.scale = Vector3(width, 1.0, length)
	sole.position.y = 2.5
	sole.material_override = _flat(SOLE_COLOR)
	node.add_child(sole)
	var strap_material: StandardMaterial3D = _flat(tint)
	for strap: Array in [[Vector3(width * 0.8, 3.0, length * 0.14), length * 0.12], [Vector3(width * 0.2, 3.0, length * 0.2), length * 0.36]]:
		var instance: MeshInstance3D = MeshInstance3D.new()
		var box: BoxMesh = BoxMesh.new()
		box.size = strap[0]
		instance.mesh = box
		instance.position = Vector3(0.0, 6.5, strap[1])
		instance.material_override = strap_material
		node.add_child(instance)
	_actors.add_child(node)
	return node


func _ring(radius: float, tint: Color) -> void:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.mesh = MeshBuilder3D.annulus(radius - 3.0, radius + 3.0)
	instance.material_override = _flat(tint)
	instance.position.y = 0.3
	_actors.add_child(instance)


func _face(node: Node3D, toward: Vector3) -> void:
	var flat: Vector3 = toward
	flat.y = 0.0
	if flat.length_squared() > 0.01:
		node.rotation.y = atan2(flat.x, flat.z)


func _rebuild_scene() -> void:
	if _actors == null:
		return
	for child: Node in _actors.get_children():
		_actors.remove_child(child)
		child.queue_free()
	_rig = {}
	_built_card = card
	match card:
		0:
			_rig["thrower"] = _character(KNIGHT, BLUE)
			_rig["flying"] = _sandal(BLUE)
			var stack: Array = []
			for index: int in 3:
				stack.append(_sandal(STRAP_COLOR))
			_rig["stack"] = stack
		1:
			_ring(SANDAL_RADIUS * 4.0, AMBER)
			var carriers: Array = []
			var loads: Array = []
			for index: int in 3:
				carriers.append(_character(RAIDER, RED))
				loads.append(_sandal(RED))
			_rig["carriers"] = carriers
			_rig["loads"] = loads
		2:
			_ring(SANDAL_RADIUS * 3.2, AMBER)
			_rig["builder"] = _character(RAIDER, RED)
			var legs: Array = []
			for index: int in 3:
				legs.append(_sandal(RED))
			_rig["legs"] = legs
		_:
			_ring(SANDAL_RADIUS * 7.0, CREAM)
			_rig["left"] = _character(KNIGHT, BLUE)
			_rig["right"] = _character(KNIGHT, BLUE)
			_rig["pass"] = _sandal(BLUE)
			_rig["attacker"] = _character(RAIDER, RED)
			var column: Node3D = (load(COLUMN) as PackedScene).instantiate() as Node3D
			column.scale = Vector3.ONE * SANDAL_RADIUS * 2.8
			_actors.add_child(column)
			_rig["column"] = column
	_animate(0.0)


func _animate(progress: float) -> void:
	var unit: float = SANDAL_RADIUS
	match card:
		0:
			var thrower: Dictionary = _rig["thrower"]
			(thrower["node"] as Node3D).position = Vector3(-unit * 9.0, 0.0, 0.0)
			_face(thrower["node"], Vector3.RIGHT)
			_play(thrower, &"idle")
			var fly: float = clampf(progress / 0.45, 0.0, 1.0)
			var hit: float = clampf((progress - 0.45) / 0.4, 0.0, 1.0)
			var flying: Node3D = _rig["flying"]
			flying.visible = progress < 0.45
			flying.position = Vector3(lerpf(-unit * 7.0, unit * 4.0, fly), sin(fly * PI) * unit * 2.5, 0.0)
			flying.rotation.y = fly * TAU * 2.0
			var stack: Array = _rig["stack"]
			for index: int in 3:
				var home: Vector3 = Vector3(unit * 6.0, 0.0, (index - 1) * unit * 2.2)
				var away: Vector3 = home + Vector3(unit * (2.0 + index * 1.6), 0.0, (index - 1) * unit * 3.0)
				var piece: Node3D = stack[index]
				piece.position = home.lerp(away, hit) + Vector3(0.0, sin(hit * PI) * unit * 1.6, 0.0)
				piece.rotation.y = hit * (index + 1) * 2.0 + PI * 0.5
		1:
			var carriers: Array = _rig["carriers"]
			var loads: Array = _rig["loads"]
			var corners: Array = [Vector3(-unit * 8.0, 0.0, -unit * 4.0), Vector3(unit * 8.0, 0.0, -unit * 3.0), Vector3(0.0, 0.0, unit * 6.0)]
			for index: int in 3:
				var window: float = clampf((progress * 3.0 - index) * 1.4, 0.0, 1.0)
				var spot: Vector3 = Vector3((index - 1) * unit * 2.0, 0.0, unit * 0.5)
				var actor: Dictionary = carriers[index]
				var body: Node3D = actor["node"]
				var path: Vector3 = (corners[index] as Vector3).lerp(spot + Vector3(0.0, 0.0, unit * 2.2), window)
				body.position = path
				_face(body, spot - corners[index])
				_play(actor, &"holding-both" if window < 1.0 else &"idle")
				var piece: Node3D = loads[index]
				piece.position = path + Vector3(0.0, MODEL_HEIGHT * 0.45, -unit) if window < 1.0 else spot
				piece.rotation.y = PI * 0.5
		2:
			var builder: Dictionary = _rig["builder"]
			(builder["node"] as Node3D).position = Vector3(-unit * 6.0, 0.0, unit * 2.0)
			_face(builder["node"], Vector3(1.0, 0.0, -0.3))
			_play(builder, &"holding-both")
			var legs: Array = _rig["legs"]
			for index: int in 3:
				var placed: float = clampf(progress * 3.0 - index, 0.0, 1.0)
				var angle: float = TAU * index / 3.0 + PI * 0.5
				var foot: Vector3 = Vector3(cos(angle), 0.0, sin(angle)) * unit * 2.0
				var piece: Node3D = legs[index]
				piece.position = foot + Vector3(0.0, (1.0 - placed) * unit * 5.0, 0.0) + Vector3(unit * 3.0, 0.0, 0.0)
				piece.basis = Basis(Vector3.UP, atan2(-cos(angle), -sin(angle))) * Basis(Vector3.RIGHT, -PI * 0.5 * placed)
				piece.position.y += unit * 1.5 * placed
		_:
			var radius: float = unit * 7.0
			var spin: float = progress * PI
			var left: Dictionary = _rig["left"]
			var right: Dictionary = _rig["right"]
			var left_at: Vector3 = Vector3(cos(PI + spin), 0.0, sin(PI + spin)) * radius
			var right_at: Vector3 = Vector3(cos(spin), 0.0, sin(spin)) * radius
			(left["node"] as Node3D).position = left_at
			(right["node"] as Node3D).position = right_at
			_face(left["node"], right_at - left_at)
			_face(right["node"], left_at - right_at)
			_play(left, &"idle")
			_play(right, &"idle")
			var pass_t: float = fmod(progress * 2.0, 1.0)
			var carried: Node3D = _rig["pass"]
			carried.position = left_at.lerp(right_at, pass_t) + Vector3(0.0, MODEL_HEIGHT * 0.5 + sin(pass_t * PI) * unit * 2.0, 0.0)
			carried.rotation.y = pass_t * TAU * 2.0
			var attacker: Dictionary = _rig["attacker"]
			var alive: bool = progress < 0.7
			(attacker["node"] as Node3D).visible = alive
			(attacker["node"] as Node3D).position = Vector3(0.0, 0.0, unit * 0.5)
			_play(attacker, &"idle")
			var column: Node3D = _rig["column"]
			column.visible = not alive
			column.position = Vector3(0.0, 0.0, unit * 0.5)

