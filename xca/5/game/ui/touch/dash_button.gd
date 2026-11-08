class_name DashButton
extends Control
## Round touch button with an icon only, bottom right.
##
## Add it to the tree after the throw controls so it sees touches first. It follows one
## finger index and shows the cooldown as an arc.

## Emitted when the button is pressed.
signal pressed

## Radius of the round hit area in pixels. Other controls read it to keep a gap.
const DEFAULT_RADIUS: float = 62.0
## Distance from the right and bottom screen edges to the button centre.
const DEFAULT_EDGE_MARGIN: Vector2 = Vector2(120.0, 120.0)

## Radius of the round hit area in pixels.
@export var radius: float = DEFAULT_RADIUS
## Distance from the right and bottom screen edges to the button centre.
@export var edge_margin: Vector2 = DEFAULT_EDGE_MARGIN
## Icon drawn on the button.
@export var icon: Texture2D = preload("res://assets/icons/fire-dash.svg")
## Button colour while ready.
@export var ready_color: Color = Color(1.0, 1.0, 1.0, 0.6)
## Button colour while cooling down.
@export var cooldown_color: Color = Color(1.0, 1.0, 1.0, 0.25)

## Share of the cooldown still left, 0.0 (ready) to 1.0 (just used). Set by the controller.
var cooldown_ratio: float = 0.0:
	set(value):
		cooldown_ratio = clampf(value, 0.0, 1.0)
		queue_redraw()
## Finger index that owns the press, or -1.
var finger_index: int = -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	get_viewport().size_changed.connect(queue_redraw)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event
		if touch.pressed and finger_index == -1 and is_visible_in_tree() and _centre().distance_to(touch.position) <= radius:
			finger_index = touch.index
			pressed.emit()
			queue_redraw()
			get_viewport().set_input_as_handled()
		elif not touch.pressed and touch.index == finger_index:
			finger_index = -1
			queue_redraw()
			get_viewport().set_input_as_handled()


func _draw() -> void:
	var centre: Vector2 = _centre() - global_position
	var tint: Color = ready_color if cooldown_ratio <= 0.0 else cooldown_color
	draw_circle(centre, radius, Color(0.06, 0.09, 0.16, 0.5))
	draw_arc(centre, radius, 0.0, TAU, 48, tint, 4.0)
	if icon != null:
		var box: Rect2 = Rect2(centre - Vector2.ONE * radius * 0.55, Vector2.ONE * radius * 1.1)
		draw_texture_rect(icon, box, false, tint)
	if cooldown_ratio > 0.0:
		draw_arc(centre, radius - 8.0, -PI * 0.5, -PI * 0.5 + TAU * cooldown_ratio, 48, Color(1.0, 0.9, 0.55, 0.9), 6.0)


func _centre() -> Vector2:
	var size_on_screen: Vector2 = get_viewport_rect().size
	return size_on_screen - edge_margin
