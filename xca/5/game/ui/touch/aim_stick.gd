class_name AimStick
extends Control
## Fixed aim stick for scheme A, on the right of the screen.
##
## The thumb drags from the stick centre and the aim points where the thumb points. The drag
## length sets the power, 0.0 at the slop radius and 1.0 at the stick edge. A release outside the
## slop fires. A release back inside the slop after the thumb left it cancels. A touch that never
## leaves the slop is a tap. It never draws text.

## Emitted on touch down.
signal pressed
## Emitted while dragging. [param bearing] is a unit vector, [param length_ratio] is the drag power 0 to 1.
signal aimed(bearing: Vector2, length_ratio: float)
## Emitted on release past the slop. [param bearing] is the last aim.
signal released(bearing: Vector2)
## Emitted on release inside the slop after the thumb left it.
signal cancelled
## Emitted on release of a touch that never left the slop.
signal tapped

## Icon in the stick centre.
@export var icon: Texture2D = preload("res://assets/icons/scheme_aim.svg")
## Ring and icon colour.
@export var ring_color: Color = Color(1.0, 1.0, 1.0, 0.85)
## Fill behind the stick.
@export var backdrop_color: Color = Color(0.06, 0.09, 0.16, 0.7)

## Tuning for sizes. Set by the scheme.
var tuning: Tuning
## Finger index that owns the touch, or -1.
var finger_index: int = -1
## True while a finger is down.
var held: bool = false
## Current aim, a unit vector. Zero until the finger leaves the slop.
var bearing: Vector2 = Vector2.ZERO
## Drag length as a share of the stick radius, 0 to 1.
var length_ratio: float = 0.0
## True while the finger is inside the slop, so a release cancels.
var inside_slop: bool = true
## Drag power from 0.0 at the slop radius to 1.0 at the stick edge.
var power: float = 0.0
## True once the finger left the slop in this touch.
var left_slop: bool = false

var _centre: Vector2 = Vector2.ZERO
var _radius: float = 66.0
var _slop: float = 16.0
var _knob: Vector2 = Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	get_viewport().size_changed.connect(layout)
	layout()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event
		if touch.pressed and finger_index == -1 and _centre.distance_to(touch.position) <= _radius * 1.25:
			finger_index = touch.index
			held = true
			inside_slop = true
			left_slop = false
			bearing = Vector2.ZERO
			length_ratio = 0.0
			power = 0.0
			_knob = _centre
			AudioRef.play(&"ui_press")
			pressed.emit()
			queue_redraw()
			get_viewport().set_input_as_handled()
		elif not touch.pressed and touch.index == finger_index:
			_finish()
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event
		if drag.index == finger_index:
			_follow(drag.position)
			get_viewport().set_input_as_handled()


func _draw() -> void:
	var local: Vector2 = _centre - global_position
	draw_circle(local, _radius, backdrop_color)
	draw_arc(local, _radius, 0.0, TAU, 56, ring_color, maxf(4.0, _radius * 0.05))
	draw_arc(local, _slop, 0.0, TAU, 32, Color(ring_color, 0.5), 2.0)
	if held:
		draw_circle(_knob - global_position, _radius * 0.3, ring_color)
		if bearing != Vector2.ZERO:
			draw_circle(local, lerpf(_slop, _radius, power), Color(ring_color, 0.22))
			draw_arc(local, lerpf(_slop, _radius, power), 0.0, TAU, 48, ring_color, 3.0)
			draw_line(local, local + bearing * _radius, Color(ring_color, 0.6), 3.0)
	elif icon != null:
		var side: float = _radius * 0.9
		draw_texture_rect(icon, Rect2(local - Vector2.ONE * side * 0.5, Vector2.ONE * side), false, ring_color)


## Places the stick. It sits left of the dash button, above the bottom edge, so a thumb finds it.
func layout() -> void:
	if tuning == null:
		tuning = Tuning.load_default()
	var viewport: Viewport = get_viewport()
	var per_css: float = RestartUiScale.pixels_per_css(viewport)
	var insets: Vector4 = RestartUiScale.edge_insets(viewport)
	var screen: Vector2 = viewport.get_visible_rect().size
	_radius = tuning.aim_stick_css_px * 0.5 * per_css
	_slop = tuning.slop_px * per_css
	var dash_centre: Vector2 = screen - DashButton.DEFAULT_EDGE_MARGIN
	var gap: float = tuning.fire_dash_gap_css_px * per_css
	var x: float = dash_centre.x - DashButton.DEFAULT_RADIUS - gap - _radius
	var y: float = clampf(dash_centre.y - _radius * 0.3, _radius + insets.y, screen.y - _radius - insets.w)
	_centre = Vector2(x, y)
	queue_redraw()


## Centre of the stick in viewport pixels.
func hit_centre() -> Vector2:
	return _centre


## Radius of the stick in viewport pixels.
func hit_radius() -> float:
	return _radius


## Lets go of the touch without firing. Call when the controlled character changes.
func release() -> void:
	finger_index = -1
	held = false
	bearing = Vector2.ZERO
	length_ratio = 0.0
	power = 0.0
	left_slop = false
	inside_slop = true
	queue_redraw()


func _follow(position_on_screen: Vector2) -> void:
	var offset: Vector2 = position_on_screen - _centre
	_knob = _centre + offset.limit_length(_radius)
	length_ratio = clampf(offset.length() / _radius, 0.0, 1.0)
	inside_slop = offset.length() <= _slop
	if inside_slop:
		bearing = Vector2.ZERO
		power = 0.0
	else:
		left_slop = true
		bearing = offset.normalized()
		power = clampf((offset.length() - _slop) / maxf(_radius - _slop, 1.0), 0.0, 1.0)
		aimed.emit(bearing, power)
	queue_redraw()


func _finish() -> void:
	var last: Vector2 = bearing
	var inside: bool = inside_slop
	var was_tap: bool = not left_slop
	release()
	if was_tap:
		tapped.emit()
	elif inside or last == Vector2.ZERO:
		cancelled.emit()
	else:
		released.emit(last)
