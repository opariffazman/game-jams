class_name MatchEndOverlay
extends Control
## Icon-only overlay at match end: a trophy or a tombstone and one large restart button.
##
## It covers the game with a dark scrim. A single tap on the button restarts, with no hold.
## Touches that start elsewhere are swallowed so the controls under the overlay stay quiet.

## Emitted when the player taps the restart button or presses R or Enter.
signal restart_requested

## Restart button diameter in CSS pixels. It is above the 64 px minimum.
const BUTTON_DIAMETER_CSS_PX: float = 80.0
## Smallest button radius in viewport pixels.
const MIN_BUTTON_RADIUS: float = 36.0
## Result icon size as a share of the viewport height.
const RESULT_ICON_RATIO: float = 0.24
## Gap between the result icon and the button as a share of the viewport height.
const GAP_RATIO: float = 0.06
## A held finger that moves farther than this many radii from the centre cancels the tap.
const CANCEL_RATIO: float = 1.6
## Fill behind the restart icon.
const BACKDROP_COLOR: Color = Color(0.06, 0.09, 0.16, 0.85)

## Icon shown when the human team wins.
@export var trophy_icon: Texture2D = preload("res://assets/icons/hud_trophy.svg")
## Icon shown when the human team loses.
@export var tombstone_icon: Texture2D = preload("res://assets/icons/hud_tombstone.svg")
## Icon on the restart button.
@export var restart_icon: Texture2D = preload("res://assets/icons/restart_rotate.svg")
## Colour over the whole game while the overlay shows.
@export var scrim_color: Color = Color(0.04, 0.06, 0.1, 0.88)
## Colour of the result icon, the button ring and the button icon.
@export var icon_color: Color = Color(0.95, 0.95, 0.95, 1.0)
## Button colour while a finger presses it.
@export var pressed_color: Color = Color(1.0, 0.9, 0.55, 1.0)

## Finger index that owns the press, or -1.
var finger_index: int = -1

var _human_won: bool = false
var _radius: float = MIN_BUTTON_RADIUS
var _button_centre: Vector2 = Vector2.ZERO
var _icon_box: Rect2 = Rect2()
var _pressed: bool = false


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	get_viewport().size_changed.connect(layout)
	layout()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event
		if touch.pressed:
			if finger_index == -1 and _button_centre.distance_to(touch.position) <= _radius:
				finger_index = touch.index
				_set_pressed(true)
			get_viewport().set_input_as_handled()
		elif touch.index == finger_index:
			var inside: bool = _pressed
			finger_index = -1
			_set_pressed(false)
			get_viewport().set_input_as_handled()
			if inside:
				restart_requested.emit()
	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event
		if drag.index == finger_index:
			if _button_centre.distance_to(drag.position) > _radius * CANCEL_RATIO:
				_set_pressed(false)
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and not key.echo:
		if key.physical_keycode == KEY_R or key.physical_keycode == KEY_ENTER or key.physical_keycode == KEY_KP_ENTER:
			restart_requested.emit()


func _draw() -> void:
	var screen_size: Vector2 = get_viewport().get_visible_rect().size
	draw_rect(Rect2(Vector2.ZERO, screen_size), scrim_color)
	var result_icon: Texture2D = trophy_icon if _human_won else tombstone_icon
	if result_icon != null:
		draw_texture_rect(result_icon, _icon_box, false, icon_color)
	var tint: Color = pressed_color if _pressed else icon_color
	var stroke: float = maxf(5.0, _radius * 0.08)
	draw_circle(_button_centre, _radius, BACKDROP_COLOR)
	draw_arc(_button_centre, _radius, 0.0, TAU, 64, tint, stroke)
	if restart_icon != null:
		var box: Rect2 = Rect2(_button_centre - Vector2.ONE * _radius * 0.55, Vector2.ONE * _radius * 1.1)
		draw_texture_rect(restart_icon, box, false, tint)


## Shows the overlay. A trophy marks a win for the human team and a tombstone marks a loss.
func show_result(human_won: bool) -> void:
	_human_won = human_won
	finger_index = -1
	_pressed = false
	layout()
	visible = true
	queue_redraw()


## Hides the overlay.
func hide_result() -> void:
	visible = false
	finger_index = -1
	_pressed = false


## Places the result icon and the button in the middle of the screen.
func layout() -> void:
	var viewport: Viewport = get_viewport()
	var screen_size: Vector2 = viewport.get_visible_rect().size
	var per_css: float = RestartUiScale.pixels_per_css(viewport)
	_radius = maxf(BUTTON_DIAMETER_CSS_PX * 0.5 * per_css, MIN_BUTTON_RADIUS)
	var icon_px: float = screen_size.y * RESULT_ICON_RATIO
	var gap: float = screen_size.y * GAP_RATIO
	var total: float = icon_px + gap + _radius * 2.0
	var top: float = (screen_size.y - total) * 0.5
	_icon_box = Rect2(Vector2((screen_size.x - icon_px) * 0.5, top), Vector2.ONE * icon_px)
	_button_centre = Vector2(screen_size.x * 0.5, top + icon_px + gap + _radius)
	queue_redraw()


## Centre of the round restart button in viewport pixels.
func button_centre() -> Vector2:
	return _button_centre


## Radius of the round restart button in viewport pixels.
func button_radius() -> float:
	return _radius


## True while a finger presses the restart button.
func is_pressed() -> bool:
	return _pressed


func _set_pressed(value: bool) -> void:
	if _pressed != value:
		_pressed = value
		queue_redraw()
