class_name TitleIconButton
extends Control
## Round icon button drawn by hand, so the title and the how-to cards need no extra textures.
##
## The glyph is a shape, never a word. The ring is amber on dark brown, which reads above 7:1.

signal pressed

enum Kind { PLAY, HELP, CLOSE, PREV, NEXT }

const FACE: Color = Color("2a1f14")
const RING: Color = Color("ffc857")
const GLYPH: Color = Color("fff3da")

var kind: int = Kind.PLAY
## Pulses the ring to draw the eye. The play button uses it.
var pulse: bool = false

var _held: bool = false
var _last_down: bool = false
var _last_msec: int = -1000


func _init(button_kind: int = Kind.PLAY) -> void:
	kind = button_kind
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL


func _gui_input(event: InputEvent) -> void:
	var down: bool
	var at: Vector2
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		down = (event as InputEventMouseButton).pressed
		at = (event as InputEventMouseButton).position
	elif event is InputEventScreenTouch:
		down = (event as InputEventScreenTouch).pressed
		at = (event as InputEventScreenTouch).position
	elif event.is_action_pressed("ui_accept") and has_focus():
		pressed.emit()
		accept_event()
		return
	else:
		return
	# Desktop mouse clicks arrive as a mouse event and as an emulated touch, so a repeat within a few ms is the same click.
	var now: int = Time.get_ticks_msec()
	if down == _last_down and now - _last_msec < 60:
		accept_event()
		return
	_last_down = down
	_last_msec = now
	if down:
		_held = true
	else:
		if _held and Rect2(Vector2.ZERO, size).has_point(at):
			pressed.emit()
		_held = false
	queue_redraw()
	accept_event()


func _process(_delta: float) -> void:
	if pulse:
		queue_redraw()


func _draw() -> void:
	var radius: float = minf(size.x, size.y) * 0.5
	var centre: Vector2 = size * 0.5
	var wobble: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * TAU / 1.6) if pulse else 0.0
	if pulse:
		draw_circle(centre, radius * (1.0 + 0.12 * wobble), Color(RING, 0.18 + 0.12 * wobble))
	draw_circle(centre, radius * (0.9 if _held else 1.0), FACE)
	draw_arc(centre, radius * 0.94, 0.0, TAU, 48, RING, maxf(2.0, radius * 0.07), true)
	if has_focus():
		draw_arc(centre, radius * 1.06, 0.0, TAU, 48, GLYPH, maxf(2.0, radius * 0.05), true)
	var unit: float = radius * 0.4
	match kind:
		Kind.PLAY:
			draw_colored_polygon(PackedVector2Array([centre + Vector2(-0.7, -1.0) * unit, centre + Vector2(1.1, 0.0) * unit, centre + Vector2(-0.7, 1.0) * unit]), GLYPH)
		Kind.HELP:
			draw_arc(centre + Vector2(0, -0.35) * unit, unit * 0.7, PI * 1.05, PI * 2.45, 24, GLYPH, unit * 0.32, true)
			draw_circle(centre + Vector2(0, 1.25) * unit, unit * 0.2, GLYPH)
			draw_line(centre + Vector2(0, 0.55) * unit, centre + Vector2(0, 0.25) * unit, GLYPH, unit * 0.32)
		Kind.CLOSE:
			draw_line(centre + Vector2(-1, -1) * unit, centre + Vector2(1, 1) * unit, GLYPH, unit * 0.34, true)
			draw_line(centre + Vector2(1, -1) * unit, centre + Vector2(-1, 1) * unit, GLYPH, unit * 0.34, true)
		Kind.PREV:
			draw_polyline(PackedVector2Array([centre + Vector2(0.5, -1.0) * unit, centre + Vector2(-0.6, 0.0) * unit, centre + Vector2(0.5, 1.0) * unit]), GLYPH, unit * 0.34, true)
		Kind.NEXT:
			draw_polyline(PackedVector2Array([centre + Vector2(-0.5, -1.0) * unit, centre + Vector2(0.6, 0.0) * unit, centre + Vector2(-0.5, 1.0) * unit]), GLYPH, unit * 0.34, true)
