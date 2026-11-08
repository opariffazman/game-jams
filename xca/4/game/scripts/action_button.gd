class_name ActionButton
extends Button
## A large touch button with a cooldown fill that drains from full to empty, plus the seconds left in its text.

const FILL_COLOR: Color = Color(0.0, 0.0, 0.0, 0.55)
const READY_COLOR: Color = Color(0.05, 0.3, 0.12)
const WAIT_COLOR: Color = Color(0.12, 0.12, 0.16)
const BORDER_COLOR: Color = Color.WHITE

## Share of the cooldown left, from 0 (ready) to 1 (just used). The scene sets it every frame.
var remaining_share: float = 0.0:
	set(value):
		if is_equal_approx(value, remaining_share):
			return
		remaining_share = value
		queue_redraw()

var _base_text: String = ""
var _seconds_left: float = 0.0


func _init(label: String = "", min_size: Vector2 = Vector2(150.0, 72.0)) -> void:
	_base_text = label
	text = label
	custom_minimum_size = min_size
	add_theme_font_override("font", UiKit.font())
	add_theme_font_size_override("font_size", 26)
	add_theme_color_override("font_color", Color.WHITE)
	add_theme_color_override("font_hover_color", Color.WHITE)
	add_theme_color_override("font_pressed_color", Color.WHITE)
	add_theme_color_override("font_disabled_color", Color(0.85, 0.85, 0.9))
	for style_name: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(style_name, UiKit.brush(READY_COLOR if style_name != "disabled" else WAIT_COLOR, BORDER_COLOR, 8.0, 9))


## Changes the label shown while the button is ready.
func set_label(label: String) -> void:
	_base_text = label
	text = label


## Sets the cooldown state. The button disables while the cooldown runs, so a tap during it does nothing.
func set_cooldown(seconds_left: float, share: float) -> void:
	_seconds_left = seconds_left
	remaining_share = share
	disabled = seconds_left > 0.0
	var wanted: String = _base_text if seconds_left <= 0.0 else "%s %.0f" % [_base_text, ceilf(seconds_left)]
	if text != wanted:
		text = wanted


func _draw() -> void:
	if remaining_share <= 0.0:
		return
	var height: float = size.y * remaining_share
	draw_rect(Rect2(0.0, size.y - height, size.x, height), FILL_COLOR)
