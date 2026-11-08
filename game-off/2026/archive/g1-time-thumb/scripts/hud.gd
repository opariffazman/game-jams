class_name Hud
extends CanvasLayer
## Time-flow gauge, wave counter, start hint, and the loss prompt.

const GAUGE_RECT := Rect2(20.0, 24.0, 300.0, 12.0)
const INK := Color("f6f6f8")
const CYAN := Color("19e3ff")

var _fill: ColorRect
var _wave: Label
var _hint: Label
var _over: Label
var _hint_dismissed: bool = false


func _ready() -> void:
	var back := ColorRect.new()
	back.position = GAUGE_RECT.position
	back.size = GAUGE_RECT.size
	back.color = Color(INK, 0.18)
	add_child(back)
	_fill = ColorRect.new()
	_fill.position = GAUGE_RECT.position
	_fill.size = Vector2(0.0, GAUGE_RECT.size.y)
	_fill.color = CYAN
	add_child(_fill)
	_wave = _make_label(Vector2(320.0, 14.0), Vector2(200.0, 30.0), HORIZONTAL_ALIGNMENT_RIGHT, 22)
	_hint = _make_label(Vector2(0.0, 640.0), Vector2(540.0, 30.0), HORIZONTAL_ALIGNMENT_CENTER, 20)
	_hint.text = "Drag below to move. Stop to freeze time."
	_over = _make_label(Vector2(0.0, 430.0), Vector2(540.0, 40.0), HORIZONTAL_ALIGNMENT_CENTER, 32)
	_over.text = "TAP TO RESTART"
	_over.visible = false


## Fills the gauge. [param flow] runs from 0 to 1.
func set_flow(flow: float) -> void:
	_fill.size.x = GAUGE_RECT.size.x * clampf(flow, 0.0, 1.0)


## Shows the wave number.
func set_wave(wave: int) -> void:
	_wave.text = "WAVE %d" % wave


## Shows or hides the loss prompt.
func show_over(shown: bool) -> void:
	_over.visible = shown


## Fades the start hint after the first input.
func dismiss_hint() -> void:
	if _hint_dismissed:
		return
	_hint_dismissed = true
	create_tween().tween_property(_hint, "modulate:a", 0.0, 0.6)


func _make_label(at: Vector2, label_size: Vector2, align: HorizontalAlignment, font_size: int) -> Label:
	var label := Label.new()
	label.position = at
	label.size = label_size
	label.horizontal_alignment = align
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", INK)
	add_child(label)
	return label
