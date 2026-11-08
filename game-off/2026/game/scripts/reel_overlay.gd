class_name ReelOverlay
extends Control
## Screen overlay of the 3D reels: the title card and the slow fade to black. It never flashes: the fade only darkens.

## Seconds the title card stays fully visible.
const CARD_HOLD_S: float = 1.8
## Seconds the title card takes to fade out.
const CARD_FADE_S: float = 0.4

var _dim: ColorRect = ColorRect.new()
var _plate: ColorRect = ColorRect.new()
var _title: Label = Label.new()
var _sub: Label = Label.new()
var _tween: Tween
var _fade_tween: Tween


func _init() -> void:
	size = Vector2(540, 960)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.color = Color(Palette.PANEL, 0.7)
	_plate.position = Vector2(0, 70)
	_plate.size = Vector2(540, 150)
	_dim.color = Color.BLACK
	_dim.size = size
	for rect: ColorRect in [_plate, _dim]:
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.position = Vector2(0, 78)
	_title.size = Vector2(540, 76)
	_sub.position = Vector2(0, 160)
	_sub.size = Vector2(540, 44)
	for label: Label in [_title, _sub]:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_outline_color", Palette.PANEL)
		label.add_theme_constant_override("outline_size", 8)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sub.add_theme_font_size_override("font_size", 30)
	for node: Control in [_plate, _title, _sub, _dim]:
		add_child(node)
	reset()


## Clears the card and the fade.
func reset() -> void:
	for running: Tween in [_tween, _fade_tween]:
		if running:
			running.kill()
	_dim.modulate.a = 0.0
	for node: Control in [_plate, _title, _sub]:
		node.modulate.a = 0.0


## Shows a title card with [param title] in [param color] and a [param sub] line. It fades out by itself.
func show_card(title: String, sub: String, color: Color) -> void:
	_title.text = title
	_title.add_theme_font_size_override("font_size", 60 if title.length() <= 12 else 40)
	_title.add_theme_color_override("font_color", color)
	_sub.text = sub
	_sub.add_theme_color_override("font_color", Palette.INK)
	for node: Control in [_plate, _title, _sub]:
		node.modulate.a = 1.0
	_tween = create_tween().set_ignore_time_scale(true)
	_tween.tween_interval(CARD_HOLD_S)
	for node: Control in [_plate, _title, _sub]:
		_tween.parallel().tween_property(node, "modulate:a", 0.0, CARD_FADE_S).set_delay(CARD_HOLD_S)


## Fades the screen to black over [param seconds] of real time.
func fade_to_black(seconds: float) -> void:
	_fade_tween = create_tween().set_ignore_time_scale(true)
	_fade_tween.tween_property(_dim, "modulate:a", 1.0, seconds).set_trans(Tween.TRANS_SINE)


## Returns the text of the title card line, for the smoke test.
func title_text() -> String:
	return _title.text
