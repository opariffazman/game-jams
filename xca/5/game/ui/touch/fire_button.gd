class_name FireButton
extends Control
## Large round fire button for scheme D, on the right of the screen.
##
## A tap fires at the lock. A drag past the slop moves the lock. A drag back inside the slop
## ends the touch with a cancel. The icon shows what a press does: stack, pass or hit, and a
## cross while the drag is back inside the slop. It never draws text.

## Emitted on touch down, so the lock shows before anything fires.
signal pressed
## Emitted while dragging past the slop. [param bearing] is a unit vector from the button centre to the finger.
signal dragged(bearing: Vector2)
## Emitted on release when the touch should fire.
signal released
## Emitted on release when the touch should cancel.
signal cancelled

## Icon per target kind. Index with [enum ThrowScheme.TargetKind].
@export var kind_icons: Array[Texture2D] = []
## Icon shown while the touch is cancelling.
@export var cancel_icon: Texture2D = preload("res://assets/icons/throw_cancel.svg")
## Ring and icon colour while ready.
@export var ready_color: Color = Color(1.0, 1.0, 1.0, 0.85)
## Fill behind the icon.
@export var backdrop_color: Color = Color(0.06, 0.09, 0.16, 0.7)

## Tuning for sizes. Set by the scheme.
var tuning: Tuning
## Colour of the lock ring, so the button echoes the target colour.
var lock_color: Color = Color(1.0, 1.0, 1.0, 0.85):
	set(value):
		lock_color = value
		queue_redraw()
## Target kind the icon shows.
var kind: int = ThrowScheme.TargetKind.STACK:
	set(value):
		kind = value
		queue_redraw()
## Finger index that owns the touch, or -1.
var finger_index: int = -1
## True while a finger is down.
var held: bool = false
## True while the finger is back inside the slop after it left it.
var cancelling: bool = false

var _centre: Vector2 = Vector2.ZERO
var _radius: float = 36.0
var _slop: float = 16.0
var _left_slop: bool = false


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
		if touch.pressed and finger_index == -1 and _centre.distance_to(touch.position) <= _radius:
			finger_index = touch.index
			held = true
			_left_slop = false
			cancelling = false
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
	draw_circle(_centre - global_position, _radius, backdrop_color)
	var ring: Color = lock_color if held else ready_color
	draw_arc(_centre - global_position, _radius, 0.0, TAU, 56, ring, maxf(4.0, _radius * 0.08))
	var icon: Texture2D = _current_icon()
	if icon != null:
		var side: float = _radius * 1.1
		draw_texture_rect(icon, Rect2(_centre - global_position - Vector2.ONE * side * 0.5, Vector2.ONE * side), false, ring)


## Places the button. Its centre sits left of the dash button with the gap Tuning asks for.
func layout() -> void:
	if tuning == null:
		tuning = Tuning.load_default()
	var viewport: Viewport = get_viewport()
	var per_css: float = RestartUiScale.pixels_per_css(viewport)
	var insets: Vector4 = RestartUiScale.edge_insets(viewport)
	var screen: Vector2 = viewport.get_visible_rect().size
	_radius = tuning.fire_button_css_px * 0.5 * per_css
	_slop = tuning.slop_px * per_css
	var dash_radius: float = DashButton.DEFAULT_RADIUS
	var dash_centre: Vector2 = screen - DashButton.DEFAULT_EDGE_MARGIN
	var gap: float = tuning.fire_dash_gap_css_px * per_css
	var x: float = dash_centre.x - dash_radius - gap - _radius
	var y: float = clampf(dash_centre.y - _radius * 0.6, _radius + insets.y, screen.y - _radius - insets.w)
	_centre = Vector2(x, y)
	queue_redraw()


## Centre of the round hit area in viewport pixels.
func hit_centre() -> Vector2:
	return _centre


## Radius of the round hit area in viewport pixels.
func hit_radius() -> float:
	return _radius


## Gap in viewport pixels between this button's edge and a circle of [param other_radius] at [param other_centre].
func gap_to(other_centre: Vector2, other_radius: float) -> float:
	return _centre.distance_to(other_centre) - _radius - other_radius


## Lets go of the touch without firing. Call when the controlled character changes.
func release() -> void:
	finger_index = -1
	held = false
	cancelling = false
	_left_slop = false
	queue_redraw()


func _follow(position_on_screen: Vector2) -> void:
	var offset: Vector2 = position_on_screen - _centre
	if offset.length() > _slop:
		_left_slop = true
		cancelling = false
		dragged.emit(offset.normalized())
	elif _left_slop:
		cancelling = true
	queue_redraw()


func _finish() -> void:
	var should_cancel: bool = cancelling
	release()
	if should_cancel:
		cancelled.emit()
	else:
		released.emit()


func _current_icon() -> Texture2D:
	if cancelling:
		return cancel_icon
	if kind >= 0 and kind < kind_icons.size():
		return kind_icons[kind]
	return null
