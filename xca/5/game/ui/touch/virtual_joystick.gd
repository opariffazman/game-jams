class_name VirtualJoystick
extends Control
## Floating joystick on the left half of the screen.
##
## The base appears under the first finger that lands in the left half. It follows
## that finger index only, so [ThrowPad] can use another finger at the same time.
## Draws shapes only, never text.

## Emitted while the stick is held. [param vector] has length 0.0 to 1.0.
signal moved(vector: Vector2)

## Radius of the base ring in pixels.
@export var base_radius: float = 90.0
## Radius of the thumb knob in pixels.
@export var knob_radius: float = 38.0
## Share of the viewport width, from the left edge, that starts the stick.
@export_range(0.1, 0.9, 0.05) var zone_width_ratio: float = 0.5
## Ring and knob colour.
@export var color: Color = Color(1.0, 1.0, 1.0, 0.55)
## Icon shown as an idle hint while no finger holds the stick.
@export var hint_icon: Texture2D = preload("res://assets/icons/joystick.svg")
## Hint centre as a share of the viewport size.
@export var hint_position_ratio: Vector2 = Vector2(0.1, 0.8)
## Hint icon size in pixels.
@export var hint_size: float = 110.0

## Finger index that owns the stick, or -1.
var finger_index: int = -1
## Current stick value, length 0.0 to 1.0.
var vector: Vector2 = Vector2.ZERO

var _origin: Vector2 = Vector2.ZERO
var _knob: Vector2 = Vector2.ZERO
var _hint_fade: float = 1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(delta: float) -> void:
	var target: float = 0.0 if finger_index != -1 else 1.0
	if not is_equal_approx(_hint_fade, target):
		_hint_fade = move_toward(_hint_fade, target, delta * 5.0)
		queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event
		# A press on the owning index means the release was lost, so the stick restarts instead of staying locked.
		if touch.pressed and (finger_index == -1 or touch.index == finger_index) and _in_zone(touch.position):
			finger_index = touch.index
			_origin = touch.position
			_knob = touch.position
			_publish(Vector2.ZERO)
			get_viewport().set_input_as_handled()
		elif not touch.pressed and touch.index == finger_index:
			release()
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event
		if drag.index == finger_index:
			var offset: Vector2 = (drag.position - _origin).limit_length(base_radius)
			_knob = _origin + offset
			_publish(offset / base_radius)
			get_viewport().set_input_as_handled()


func _draw() -> void:
	_draw_hint()
	if finger_index == -1:
		return
	var local_origin: Vector2 = _origin - global_position
	draw_arc(local_origin, base_radius, 0.0, TAU, 48, color, 4.0)
	draw_circle(_knob - global_position, knob_radius, color)


## Lets go of the stick and centres it. Call when the controlled character changes.
func release() -> void:
	finger_index = -1
	_publish(Vector2.ZERO)


func _draw_hint() -> void:
	if hint_icon == null or _hint_fade <= 0.0 or zone_width_ratio <= 0.0:
		return
	var centre: Vector2 = get_viewport_rect().size * hint_position_ratio - global_position
	var tint: Color = Color(TouchStyle.HINT_COLOR, TouchStyle.HINT_COLOR.a * _hint_fade)
	draw_arc(centre, base_radius, 0.0, TAU, 48, tint, 3.0)
	draw_texture_rect(hint_icon, Rect2(centre - Vector2.ONE * hint_size * 0.5, Vector2.ONE * hint_size), false, tint)


func _in_zone(position_on_screen: Vector2) -> bool:
	var width: float = get_viewport_rect().size.x
	return position_on_screen.x <= width * zone_width_ratio


func _publish(new_vector: Vector2) -> void:
	vector = new_vector
	moved.emit(vector)
	queue_redraw()
