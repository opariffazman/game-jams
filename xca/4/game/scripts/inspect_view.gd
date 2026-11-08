class_name InspectView
extends Control
## Full-screen hologram-style viewer for the weapon in hand, with zoom, rotate, pan and scrub inputs.
##
## Scrub is a back-and-forth stroke. Every input maps to the same stroke count, so a mouse, a finger, a key and a hand clean at the same pace.

## Emitted for every batch of scrub strokes. Reversals counts strokes since the last emit.
signal scrubbed(reversals: int)
## Emitted when the player closes the viewer.
signal closed
## Emitted when the player asks for the previous (-1) or next (1) weapon.
signal weapon_step(direction: int)

const ZOOM_MIN: float = 0.6
const ZOOM_MAX: float = 2.6
## Largest pan in units of the weapon's fitted size.
const PAN_LIMIT: float = 0.6
const FIELD_OF_VIEW: float = 40.0
const FIT_MARGIN: float = 1.25
const IDLE_SPIN_DELAY: float = 2.0
const IDLE_SPIN_RATE: float = deg_to_rad(24.0)
const KEY_ROTATE_RATE: float = 2.0
const KEY_ZOOM_RATE: float = 1.6
const KEY_SCRUB_STROKES_PER_SECOND: float = 7.0
## Pointer travel that makes one scrub stroke, as a share of the shorter screen side.
const STROKE_SHARE: float = 0.05
## How far a hand must travel in the camera image for one scrub stroke is set by the tracker. The pan factor maps hand travel to screen share.
## Radians of turn per frame share of hand movement. A hand-width of travel turns the weapon about a third of a revolution.
const HAND_TURN_GAIN: float = 2.2
## The hands must stay within these changes of the pose where they started, or the close hold restarts.
const CLOSE_STEADY_MID: float = 0.04
const CLOSE_STEADY_SPREAD: float = 0.05
const CLOSE_STEADY_ANGLE: float = 0.2
## Seconds of steady two palms that close the viewer. It matches the gate that opens it.
const CLOSE_HOLD_SECONDS: float = 1.6
## Seconds without two palms after opening before the close hold arms, so the opening gesture cannot close it again.
const CLOSE_ARM_SECONDS: float = 0.6
const DRAG_ROTATE_RATE: float = 0.01
const WHEEL_STEP: float = 1.12
const SMOOTHING: float = 12.0
const ACCENT: Color = Color(0.3, 0.9, 0.95)
const BACKDROP: Color = Color(0.02, 0.07, 0.1, 0.98)
const TITLE_FONT: int = 40
const HINT_FONT: int = 24
const BUTTON_FONT: int = 28
const MIN_BUTTON: Vector2 = Vector2(72.0, 64.0)
const TOUCH_HINT: String = "Rub the weapon: drag back and forth. Pinch to zoom, twist to roll."
const POINTER_HINT: String = "Rub the weapon: drag back and forth or hold Space. Wheel zooms, arrows turn, Q and E roll."
const HAND_HINT: String = "Two hands: spread to zoom, move to turn, tilt to roll, wave a hand to rub. Hold two palms still to close."

## Tracker data source for the two-hand and scrub fields. Optional.
var body_input: BodyInput

var _bridge: JavaScriptObject
var _viewport: SubViewport
var _camera: Camera3D
var _pivot: Node3D
var _display: MeshInstance3D
var _ring: MeshInstance3D
var _sparkle: CPUParticles3D
var _title: Label
var _grime_label: Label
var _grime_bar: ProgressBar
var _notice: Label
var _hint: Label
var _guide: TutorialHints
var _fit_extent: float = 1.0
var _zoom: float = 1.0
var _zoom_target: float = 1.0
var _orientation: Basis = Basis.IDENTITY
var _pan: Vector2 = Vector2.ZERO
var _idle: float = 0.0
var _is_open: bool = false
var _touches: Dictionary[int, Vector2] = {}
var _mouse_rotating: bool = false
var _mouse_panning: bool = false
var _counter: ScrubCounter = ScrubCounter.new(40.0)
var _pending_strokes: int = 0
var _key_stroke_clock: float = 0.0
var _hand_active: bool = false
var _hand_base: Array = []
var _close_armed: bool = false
var _close_anchor: Array = []
var _close_held: float = 0.0
var _no_palms_for: float = 0.0
var _last_scrub_count: int = 0


## Detects back-and-forth strokes in a stream of signed movement. A stroke needs the full stroke distance, so jitter never counts.
class ScrubCounter:
	extends RefCounted

	var stroke_distance: float
	var _position: float = 0.0
	var _extreme: float = 0.0
	var _direction: int = 0

	func _init(distance: float) -> void:
		stroke_distance = distance

	## Adds movement and returns the strokes it completed. The first stroke sets the direction and does not count.
	func feed(movement: float) -> int:
		_position += movement
		if _direction == 0:
			if absf(_position - _extreme) >= stroke_distance:
				_direction = 1 if _position > _extreme else -1
				_extreme = _position
			return 0
		if (_position - _extreme) * float(_direction) > 0.0:
			_extreme = _position
			return 0
		if absf(_position - _extreme) >= stroke_distance:
			_direction = -_direction
			_extreme = _position
			return 1
		return 0

	func reset() -> void:
		_position = 0.0
		_extreme = 0.0
		_direction = 0


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if OS.has_feature("web"):
		_bridge = JavaScriptBridge.get_interface("railsBridge")
	_build_scene()
	_build_ui()


func _process(delta: float) -> void:
	if not _is_open:
		return
	_read_keys(delta)
	_read_hands(delta)
	_idle += delta
	if _idle > IDLE_SPIN_DELAY:
		_orientation = Basis(Vector3.UP, IDLE_SPIN_RATE * delta) * _orientation
	_zoom = lerpf(_zoom, _zoom_target, 1.0 - exp(-SMOOTHING * delta))
	_apply_pose()
	_fit_camera()
	_ring.rotation.y += delta * 0.5
	_counter.stroke_distance = _stroke_distance()
	_flush_strokes()


func _input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).physical_keycode:
			KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER:
				close()
				get_viewport().set_input_as_handled()
		return
	if event is InputEventScreenTouch:
		_on_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_on_touch_drag(event as InputEventScreenDrag)
	elif event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION:
		_on_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION:
		_on_mouse_motion(event as InputEventMouseMotion)


## Shows the viewer with a copy of the weapon mesh. The copy keeps the model in the hero untouched.
func open(weapon: Dictionary, source: MeshInstance3D, overlay: Material, grime_level: float) -> void:
	_is_open = true
	visible = true
	_zoom = 1.0
	_zoom_target = 1.0
	_orientation = Basis.from_euler(Vector3(deg_to_rad(10.0), deg_to_rad(-25.0), 0.0))
	_close_armed = false
	_close_anchor = []
	_close_held = 0.0
	_no_palms_for = 0.0
	_pan = Vector2.ZERO
	_idle = 0.0
	_touches.clear()
	_counter.reset()
	_pending_strokes = 0
	_hand_active = false
	_last_scrub_count = body_input.scrub_count if body_input != null else 0
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_notice.text = ""
	_hint.text = HAND_HINT if body_input != null and body_input.magic else (TOUCH_HINT if DisplayServer.is_touchscreen_available() else POINTER_HINT)
	_guide.visible = not TutorialHints.is_learned()
	if _guide.visible:
		_guide.show_steps(TutorialHints.viewer_steps(body_input != null and body_input.magic))
	_set_two_hands(true)
	show_weapon(weapon, source, overlay, grime_level)


## Swaps the displayed weapon, for the previous and next buttons.
func show_weapon(weapon: Dictionary, source: MeshInstance3D, overlay: Material, grime_level: float) -> void:
	_title.text = String(weapon["label"])
	if _display != null:
		_display.queue_free()
	_display = MeshInstance3D.new()
	_display.mesh = source.mesh
	_display.material_overlay = overlay
	var bounds: AABB = source.mesh.get_aabb()
	_display.position = -bounds.get_center()
	# The longest axis lies sideways, so a bat and a gun both read at their full length.
	var long_axis_is_depth: bool = bounds.size.z > bounds.size.x
	var holder := Node3D.new()
	holder.rotation.y = deg_to_rad(90.0) if long_axis_is_depth else 0.0
	holder.add_child(_display)
	_pivot.add_child(holder)
	for child: Node in _pivot.get_children():
		if child != holder and child is Node3D and child != _sparkle:
			child.queue_free()
	_fit_extent = maxf(bounds.size.x, bounds.size.z) if not long_axis_is_depth else bounds.size.z
	_fit_extent = maxf(_fit_extent, bounds.size.y)
	_ring.position.y = -0.3 * _fit_extent
	_ring.scale = Vector3.ONE * _fit_extent * 0.5
	set_grime(grime_level)


## Updates the dirt readout. The bar and the percent text both carry the value.
func set_grime(level: float) -> void:
	_grime_bar.value = level * 100.0
	_grime_label.text = "Spotless" if level <= 0.0 else "Dirt %d%%" % roundi(level * 100.0)


## Shows a short line under the title, for the clean result.
func show_notice(text: String) -> void:
	_notice.text = text


## Bursts sparkles around the weapon.
func sparkle() -> void:
	_sparkle.restart()
	_sparkle.emitting = true


## Hides the viewer and returns the tracker to one hand.
func close() -> void:
	if not _is_open:
		return
	_is_open = false
	visible = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_set_two_hands(false)
	closed.emit()


func is_open() -> bool:
	return _is_open


## Returns the zoom factor, for tests.
func get_zoom() -> float:
	return _zoom_target


## Returns the turn about the vertical axis in radians, for tests and the cleaning strokes.
func get_yaw() -> float:
	return _orientation.get_euler(EULER_ORDER_YXZ).y


## Returns the pan, for tests.
func get_pan() -> Vector2:
	return _pan


## Zooms by a factor. The result stays inside the zoom range.
func zoom_by(factor: float) -> void:
	_zoom_target = clampf(_zoom_target * factor, ZOOM_MIN, ZOOM_MAX)
	_idle = 0.0


## Turns the weapon about the screen axes, in radians. There is no limit, so every side can face the camera.
func rotate_by(yaw_step: float, pitch_step: float, roll_step: float = 0.0) -> void:
	_orientation = _screen_turn(yaw_step, pitch_step, roll_step) * _orientation
	_idle = 0.0


## Screen axes stay fixed while the weapon turns, so a drag to the right always spins the near side to the right.
func _screen_turn(yaw_step: float, pitch_step: float, roll_step: float) -> Basis:
	return Basis(Vector3.BACK, roll_step) * Basis(Vector3.RIGHT, pitch_step) * Basis(Vector3.UP, yaw_step)


## Moves the weapon in screen shares. The result stays inside the pan range.
func pan_by(share: Vector2) -> void:
	_pan = (_pan + share * _fit_extent).clampf(-PAN_LIMIT * _fit_extent, PAN_LIMIT * _fit_extent)
	_idle = 0.0


## Hides the icon strip once the player has learned to clean.
func hide_guide() -> void:
	_guide.visible = false


## Adds scrub strokes from any source.
func add_strokes(count: int) -> void:
	_pending_strokes += count


func _set_two_hands(on: bool) -> void:
	if _bridge != null:
		_bridge.setTwoHands(on)


func _stroke_distance() -> float:
	var size: Vector2 = get_viewport_rect().size
	return minf(size.x, size.y) * STROKE_SHARE


func _flush_strokes() -> void:
	if _pending_strokes > 0:
		var count: int = _pending_strokes
		_pending_strokes = 0
		scrubbed.emit(count)


func _build_scene() -> void:
	var container := SubViewportContainer.new()
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(container)
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	container.add_child(_viewport)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.75, 0.85, 0.9)
	environment.ambient_light_energy = 0.7
	_camera = Camera3D.new()
	_camera.fov = FIELD_OF_VIEW
	_camera.environment = environment
	_camera.near = 0.05
	_viewport.add_child(_camera)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35.0, -30.0, 0.0)
	key.light_energy = 1.0
	_viewport.add_child(key)
	# A cyan light from behind makes a rim on the edges, so a flat low-poly model keeps its outline.
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-15.0, 150.0, 0.0)
	rim.light_color = ACCENT
	rim.light_energy = 1.6
	_viewport.add_child(rim)
	_pivot = Node3D.new()
	_viewport.add_child(_pivot)
	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.95
	torus.outer_radius = 1.0
	torus.rings = 32
	torus.ring_segments = 6
	_ring.mesh = torus
	var ring_material := StandardMaterial3D.new()
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_material.albedo_color = Color(ACCENT, 0.8)
	ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring.material_override = ring_material
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_viewport.add_child(_ring)
	_sparkle = _make_sparkle()
	_viewport.add_child(_sparkle)


func _make_sparkle() -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.one_shot = true
	particles.emitting = false
	particles.amount = 40
	particles.lifetime = 0.9
	particles.explosiveness = 1.0
	particles.direction = Vector3.UP
	particles.spread = 180.0
	particles.initial_velocity_min = 0.6
	particles.initial_velocity_max = 1.6
	particles.gravity = Vector3(0.0, -0.8, 0.0)
	var mesh := SphereMesh.new()
	mesh.radius = 0.03
	mesh.height = 0.06
	mesh.radial_segments = 6
	mesh.rings = 3
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.95, 0.6)
	mesh.material = material
	particles.mesh = mesh
	return particles


func _build_ui() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = BACKDROP
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	move_child(backdrop, 0)
	var top := HBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 8.0
	top.offset_right = -8.0
	top.offset_top = 8.0
	top.add_theme_constant_override("separation", 8)
	add_child(top)
	top.add_child(_make_button("previous", func() -> void: weapon_step.emit(-1), "Previous weapon"))
	_title = Label.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", TITLE_FONT)
	_title.add_theme_color_override("font_color", ACCENT)
	top.add_child(_title)
	top.add_child(_make_button("next", func() -> void: weapon_step.emit(1), "Next weapon"))
	_notice = Label.new()
	_notice.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_notice.offset_top = 84.0
	_notice.offset_bottom = 124.0
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice.add_theme_font_size_override("font_size", 28)
	_notice.add_theme_color_override("font_color", Color(1.0, 0.92, 0.45))
	_notice.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	_notice.add_theme_constant_override("shadow_offset_y", 2)
	_notice.add_theme_constant_override("shadow_outline_size", 6)
	add_child(_notice)
	var bottom := VBoxContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.offset_left = 8.0
	bottom.offset_right = -8.0
	bottom.offset_bottom = -8.0
	bottom.add_theme_constant_override("separation", 6)
	add_child(bottom)
	_guide = TutorialHints.new()
	bottom.add_child(_guide)
	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.add_theme_font_size_override("font_size", HINT_FONT)
	bottom.add_child(_hint)
	_grime_label = Label.new()
	_grime_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_grime_label.add_theme_font_size_override("font_size", 26)
	bottom.add_child(_grime_label)
	_grime_bar = ProgressBar.new()
	_grime_bar.show_percentage = false
	_grime_bar.custom_minimum_size = Vector2(0.0, 18.0)
	_grime_bar.add_theme_stylebox_override("fill", _flat(Color(0.75, 0.5, 0.2)))
	_grime_bar.add_theme_stylebox_override("background", _flat(Color(0.15, 0.2, 0.22)))
	bottom.add_child(_grime_bar)
	var done := _make_button("check", close, "Close the viewer")
	UiKit.primary(done)
	done.custom_minimum_size = Vector2(160.0, 64.0)
	done.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bottom.add_child(done)


func _flat(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(4)
	return box


func _make_button(icon_name: String, action: Callable, tooltip: String) -> Button:
	var button: Button = UiKit.icon_button(icon_name, action, "", tooltip, MIN_BUTTON)
	button.focus_mode = Control.FOCUS_NONE
	return button


func _apply_pose() -> void:
	_pivot.basis = _orientation.orthonormalized()
	_pivot.scale = Vector3.ONE * _zoom
	_pivot.position = Vector3(_pan.x, -_pan.y, 0.0)


# A portrait screen fits the width and a landscape screen fits the height, so the weapon is never cropped.
func _fit_camera() -> void:
	var size: Vector2 = get_viewport_rect().size
	_camera.keep_aspect = Camera3D.KEEP_WIDTH if size.y > size.x else Camera3D.KEEP_HEIGHT
	var span: float = _fit_extent * FIT_MARGIN
	var distance: float = span / (2.0 * tan(deg_to_rad(FIELD_OF_VIEW) * 0.5))
	_camera.position = Vector3(0.0, 0.0, distance + _fit_extent * 0.5)


func _read_keys(delta: float) -> void:
	var turn: float = Input.get_axis("ui_left", "ui_right")
	var tilt: float = Input.get_axis("ui_up", "ui_down")
	var roll: float = float(Input.is_physical_key_pressed(KEY_E)) - float(Input.is_physical_key_pressed(KEY_Q))
	if turn != 0.0 or tilt != 0.0 or roll != 0.0:
		rotate_by(turn * KEY_ROTATE_RATE * delta, tilt * KEY_ROTATE_RATE * delta, roll * KEY_ROTATE_RATE * delta)
	var zoom_in: bool = Input.is_physical_key_pressed(KEY_EQUAL) or Input.is_physical_key_pressed(KEY_KP_ADD)
	var zoom_out: bool = Input.is_physical_key_pressed(KEY_MINUS) or Input.is_physical_key_pressed(KEY_KP_SUBTRACT)
	if zoom_in != zoom_out:
		zoom_by(pow(KEY_ZOOM_RATE, delta if zoom_in else -delta))
	if Input.is_physical_key_pressed(KEY_SPACE):
		_idle = 0.0
		_key_stroke_clock += delta * KEY_SCRUB_STROKES_PER_SECOND
		var whole: int = int(_key_stroke_clock)
		if whole > 0:
			_key_stroke_clock -= float(whole)
			add_strokes(whole)
	else:
		_key_stroke_clock = 0.0


# Spread zooms. Moving both hands turns the weapon about the screen axes, and tilting the line between them rolls it.
# Each frame applies only its change since the last one, so the turn never snaps back and has no limit.
func _read_hands(delta: float) -> void:
	if body_input == null:
		return
	if body_input.scrub_count > _last_scrub_count:
		add_strokes(body_input.scrub_count - _last_scrub_count)
		_idle = 0.0
	_last_scrub_count = body_input.scrub_count
	_track_close_gate(delta)
	var hands: Array = body_input.two_hand
	if hands.size() < 4:
		_hand_active = false
		return
	if not _hand_active:
		_hand_active = true
		_hand_base = hands.duplicate()
		return
	_idle = 0.0
	var before_distance: float = maxf(float(_hand_base[0]), 0.05)
	zoom_by(float(hands[0]) / before_distance)
	var roll: float = -angle_difference(float(_hand_base[1]), float(hands[1]))
	var yaw: float = (float(hands[2]) - float(_hand_base[2])) * HAND_TURN_GAIN
	var pitch: float = (float(hands[3]) - float(_hand_base[3])) * HAND_TURN_GAIN
	rotate_by(yaw, pitch, roll)
	_hand_base = hands.duplicate()


# Two palms held still close the viewer. The gate arms only after the hands have left the pose once,
# because the hold that opened the viewer is still up when it appears.
func _track_close_gate(delta: float) -> void:
	var hands: Array = body_input.two_hand
	if not body_input.two_palms or hands.size() < 4:
		_no_palms_for += delta
		_close_armed = _close_armed or _no_palms_for >= CLOSE_ARM_SECONDS
		_cancel_close_hold()
		return
	_no_palms_for = 0.0
	if not _close_armed:
		return
	var pose: Array = [float(hands[0]), float(hands[1]), float(hands[2]), float(hands[3])]
	if _close_anchor.is_empty() or _moved_from_anchor(pose):
		_close_anchor = pose
		_close_held = 0.0
		_notice.text = ""
		return
	_close_held += delta
	if _close_held >= CLOSE_HOLD_SECONDS:
		close()
		return
	_notice.text = "Hold still to close" if _close_held > 0.5 else ""


func _moved_from_anchor(pose: Array) -> bool:
	var mid_shift: float = Vector2(pose[2] - float(_close_anchor[2]), pose[3] - float(_close_anchor[3])).length()
	return (
		mid_shift > CLOSE_STEADY_MID
		or absf(pose[0] - float(_close_anchor[0])) > CLOSE_STEADY_SPREAD
		or absf(angle_difference(float(_close_anchor[1]), pose[1])) > CLOSE_STEADY_ANGLE
	)


func _cancel_close_hold() -> void:
	if not _close_anchor.is_empty():
		_close_anchor = []
		_close_held = 0.0
		_notice.text = ""


func _on_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		_touches[event.index] = event.position
	else:
		_touches.erase(event.index)
	_counter.reset()


func _on_touch_drag(event: InputEventScreenDrag) -> void:
	if not _touches.has(event.index):
		return
	if _touches.size() == 1:
		_pan_and_scrub(event.relative)
		_touches[event.index] = event.position
		return
	var before: Array[Vector2] = _touches.values()
	_touches[event.index] = event.position
	var after: Array[Vector2] = _touches.values()
	var before_gap: Vector2 = before[1] - before[0]
	var after_gap: Vector2 = after[1] - after[0]
	if before_gap.length() > 1.0 and after_gap.length() > 1.0:
		zoom_by(after_gap.length() / before_gap.length())
		rotate_by(0.0, 0.0, -angle_difference(before_gap.angle(), after_gap.angle()))


func _on_mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			zoom_by(WHEEL_STEP)
		MOUSE_BUTTON_WHEEL_DOWN:
			zoom_by(1.0 / WHEEL_STEP)
		MOUSE_BUTTON_LEFT:
			_mouse_rotating = event.pressed
			_counter.reset()
		MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
			_mouse_panning = event.pressed


func _on_mouse_motion(event: InputEventMouseMotion) -> void:
	var size: Vector2 = get_viewport_rect().size
	if _mouse_panning:
		pan_by(Vector2(event.relative.x / size.x, event.relative.y / size.y) * 2.0)
	elif _mouse_rotating:
		rotate_by(event.relative.x * DRAG_ROTATE_RATE, event.relative.y * DRAG_ROTATE_RATE)
		add_strokes(_counter.feed(event.relative.x))


func _pan_and_scrub(relative: Vector2) -> void:
	var size: Vector2 = get_viewport_rect().size
	pan_by(Vector2(relative.x / size.x, relative.y / size.y) * 2.0)
	add_strokes(_counter.feed(relative.x))
