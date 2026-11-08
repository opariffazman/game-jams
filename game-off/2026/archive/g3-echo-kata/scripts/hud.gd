class_name Hud
extends Control
## Take counter, 6 second timer bar, dummies left, timeline strip, banners and hint.

const TRACK_COLORS: Array[Color] = [Palette.MAGENTA, Palette.INK, Palette.CYAN]
const BAR_X: float = 20.0
const BAR_W: float = 500.0

var take_number: int = 1
var tick: int = 0
var tick_total: int = 360
var left: int = 6
## Strike flags per track, one array per timeline row.
var strikes: Array[PackedByteArray] = []
## Rows that are complete, drawn full width.
var rows_full: int = 0
var _take_label: Label
var _left_label: Label
var _banner: Label
var _result: Label
var _again: Label
var _hint: Label


func _ready() -> void:
	_take_label = _make_label(22, Palette.CYAN, Vector2(20.0, 12.0), 250.0, HORIZONTAL_ALIGNMENT_LEFT)
	_left_label = _make_label(22, Palette.MAGENTA, Vector2(270.0, 12.0), 250.0, HORIZONTAL_ALIGNMENT_RIGHT)
	_banner = _make_label(30, Palette.INK, Vector2(20.0, 320.0), 500.0, HORIZONTAL_ALIGNMENT_CENTER)
	_result = _make_label(52, Palette.INK, Vector2(20.0, 300.0), 500.0, HORIZONTAL_ALIGNMENT_CENTER)
	_again = _make_label(24, Palette.AMBER, Vector2(20.0, 380.0), 500.0, HORIZONTAL_ALIGNMENT_CENTER)
	_hint = _make_label(15, Palette.INK, Vector2(20.0, 610.0), 500.0, HORIZONTAL_ALIGNMENT_CENTER)
	_hint.text = "Drag to move - tap to strike - past takes replay as ghosts"
	_result.hide()
	_again.hide()
	_banner.hide()


func _process(_delta: float) -> void:
	_take_label.text = "TAKE %d/3" % take_number
	_left_label.text = "LEFT %d" % left
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(0.0, 576.0, 540.0, 384.0), Color(Palette.INK, 0.04), true)
	draw_line(Vector2(0.0, 576.0), Vector2(540.0, 576.0), Color(Palette.INK, 0.2), 1.0)
	draw_rect(Rect2(BAR_X, 46.0, BAR_W, 8.0), Color(Palette.INK, 0.15), true)
	var progress: float = clampf(float(tick) / tick_total, 0.0, 1.0)
	draw_rect(Rect2(BAR_X, 46.0, BAR_W * progress, 8.0), Palette.CYAN, true)
	for row: int in 3:
		var y: float = 66.0 + row * 8.0
		draw_rect(Rect2(BAR_X, y, BAR_W, 5.0), Color(Palette.INK, 0.08), true)
		var filled: float = 1.0 if row < rows_full else (progress if row == rows_full else 0.0)
		draw_rect(Rect2(BAR_X, y, BAR_W * filled, 5.0), Color(TRACK_COLORS[row], 0.4), true)
		if row < strikes.size():
			for t: int in strikes[row].size():
				if strikes[row][t] != 0 and t <= tick_total * filled:
					draw_rect(Rect2(BAR_X + BAR_W * t / tick_total - 1.0, y - 1.0, 3.0, 7.0), Palette.AMBER, true)
	draw_rect(Rect2(BAR_X + BAR_W * progress - 1.0, 62.0, 2.0, 28.0), Palette.INK, true)


## Hide the one-line hint after the first input.
func dismiss_hint() -> void:
	if _hint.visible and _hint.modulate.a == 1.0:
		create_tween().tween_property(_hint, "modulate:a", 0.0, 0.4)


## Show or hide the intro banner.
func set_banner(text: String) -> void:
	_banner.text = text
	_banner.visible = text != ""


## Show the final score and restart prompt, or hide them when [param text] is empty.
func set_result(text: String) -> void:
	_result.text = text
	_result.visible = text != ""
	_again.text = "tap to go again"
	_again.visible = text != ""


func _make_label(size: int, color: Color, at: Vector2, width: float, align: HorizontalAlignment) -> Label:
	var label: Label = Label.new()
	var settings: LabelSettings = LabelSettings.new()
	settings.font_size = size
	settings.font_color = color
	settings.outline_size = 4
	settings.outline_color = Palette.BG
	label.label_settings = settings
	label.position = at
	label.size = Vector2(width, size * 2.4)
	label.horizontal_alignment = align
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label
