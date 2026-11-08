class_name PlayControls
extends CanvasLayer
## In-room controls: the UNDO button, the RETRY button, and the NO WAY OUT banner. Draws shapes and text only, and decides nothing about the rules.

## UNDO button, in the strip below the room floor.
const UNDO_RECT: Rect2 = Rect2(20, 912, 170, 48)
## RETRY button, shown when a dead end has no undo left.
const RETRY_RECT: Rect2 = Rect2(250, 912, 270, 48)
## NO WAY OUT banner, between the top rows and the room floor.
const PANEL_RECT: Rect2 = Rect2(20, 206, 500, 116)
## Font size of the button words.
const BUTTON_FONT: int = 28
## Alpha of a disabled button.
const DISABLED_ALPHA: float = 0.45

var _shapes: Control
var _undo_label: Label
var _retry_label: Label
var _title: Label
var _reason: Label
var _active: bool = false
var _undo_left: int = 0
var _dead_end: bool = false
var _retry_on: bool = false


func _init() -> void:
	_shapes = Control.new()
	_shapes.size = Vector2(540, 960)
	_shapes.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shapes.draw.connect(_draw_shapes)
	add_child(_shapes)
	_undo_label = _make_label(UNDO_RECT, BUTTON_FONT)
	_retry_label = _make_label(RETRY_RECT, BUTTON_FONT - 2)
	_retry_label.text = "RETRY  -1 HEART"
	_title = _make_label(Rect2(PANEL_RECT.position.x, PANEL_RECT.position.y + 4, PANEL_RECT.size.x, 48), 40)
	_title.text = "NO WAY OUT"
	_title.add_theme_color_override("font_color", Palette.MAGENTA)
	_reason = _make_label(Rect2(PANEL_RECT.position.x + 12, PANEL_RECT.position.y + 52, PANEL_RECT.size.x - 24, 60), 24)
	_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	set_undo(0)
	hide_dead_end()
	set_active(false)


## Shows or hides every control. Off outside the rooms.
func set_active(on: bool) -> void:
	if on == _active:
		return
	_active = on
	_refresh()


## Sets the undos left. The button reads UNDO and the count, and dims at 0.
func set_undo(left: int) -> void:
	_undo_left = left
	_undo_label.text = "UNDO %d" % left
	_refresh()


## Shows the NO WAY OUT banner with [param reason]. With [param undo_ready] the UNDO button lights up, else RETRY shows.
func show_dead_end(reason: String, undo_ready: bool) -> void:
	_dead_end = true
	_retry_on = not undo_ready
	_reason.text = reason
	_refresh()


## Hides the banner and the RETRY button.
func hide_dead_end() -> void:
	_dead_end = false
	_retry_on = false
	_refresh()


## Returns the banner reason line while the banner shows, else an empty string.
func dead_end_reason() -> String:
	return _reason.text if _active and _dead_end else ""


## Returns true while the UNDO button is lit by the banner.
func undo_lit() -> bool:
	return _active and _dead_end and not _retry_on and _undo_left > 0


## Returns true while the RETRY button shows.
func retry_shown() -> bool:
	return _active and _retry_on


## Returns true when [param screen_pos] is on the UNDO button, enabled or not.
func undo_at(screen_pos: Vector2) -> bool:
	return _active and UNDO_RECT.has_point(screen_pos)


## Returns true when [param screen_pos] is on the RETRY button while it shows.
func retry_at(screen_pos: Vector2) -> bool:
	return retry_shown() and RETRY_RECT.has_point(screen_pos)


func _refresh() -> void:
	_shapes.visible = _active
	_undo_label.visible = _active
	_retry_label.visible = _active and _retry_on
	_title.visible = _active and _dead_end
	_reason.visible = _active and _dead_end
	var lit: bool = undo_lit()
	_undo_label.add_theme_color_override("font_color", Palette.PANEL if lit else Color(Palette.INK, 1.0 if _undo_left > 0 else DISABLED_ALPHA))
	_undo_label.add_theme_constant_override("outline_size", 0 if lit else 6)
	_shapes.queue_redraw()


func _draw_shapes() -> void:
	if _dead_end:
		_shapes.draw_rect(PANEL_RECT, Color(Palette.PANEL, 0.95))
		_shapes.draw_rect(PANEL_RECT, Palette.MAGENTA, false, 4.0)
	var enabled: bool = _undo_left > 0
	var accent: Color = Palette.CYAN if enabled else Color(Palette.INK, DISABLED_ALPHA)
	if undo_lit():
		_shapes.draw_rect(UNDO_RECT, Palette.AMBER)
		_shapes.draw_rect(UNDO_RECT, Palette.INK, false, 4.0)
	else:
		_shapes.draw_rect(UNDO_RECT, Palette.PANEL)
		_shapes.draw_rect(UNDO_RECT, accent, false, 3.0)
	if _retry_on:
		_shapes.draw_rect(RETRY_RECT, Palette.PANEL)
		_shapes.draw_rect(RETRY_RECT, Palette.AMBER, false, 4.0)


func _make_label(rect: Rect2, font_size: int) -> Label:
	var label: Label = Label.new()
	label.position = rect.position
	label.size = rect.size
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Palette.INK)
	label.add_theme_color_override("font_outline_color", Palette.PANEL)
	label.add_theme_constant_override("outline_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label
