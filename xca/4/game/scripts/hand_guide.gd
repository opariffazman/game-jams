class_name HandGuide
extends Control
## Shows where the camera sees the hand and tells the player when to show it.
##
## A small corner map gets a dot per hand. A large panel asks for a hand before the first sighting and marks a lost hand.

## Corner map size in pixels.
const MAP_SIZE: Vector2 = Vector2(168.0, 126.0)
## Gap between the corner map and the screen edge in pixels.
const MAP_MARGIN: float = 12.0
## Radius of the hand dot in pixels.
const DOT_RADIUS: float = 9.0
const PANEL_SIZE: Vector2 = Vector2(360.0, 200.0)
const GUIDE_PANEL_COLOR: Color = Color(0.0, 0.0, 0.0, 0.8)
const LOST_PANEL_COLOR: Color = Color(0.55, 0.0, 0.1, 0.9)
const SLOT_COLORS: Array[Color] = [
	Color.WHITE, Color(0.3, 0.9, 1.0), Color(1.0, 0.9, 0.3), Color(1.0, 0.5, 0.9),
]

## Input that supplies hand positions and state.
@export var body_input: BodyInput
## Whether the big "show your hand" panel may appear. The hero select screen turns it off, because the cards need the room.
var panel_enabled: bool = true

var _font: Font = ThemeDB.fallback_font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	visible = body_input.magic
	if visible:
		queue_redraw()


func _draw() -> void:
	_draw_map()
	if not panel_enabled:
		return
	if not body_input.hands_ever_seen:
		_draw_panel("palm", GUIDE_PANEL_COLOR)
	elif not body_input.is_any_aiming():
		_draw_panel("broken_heart", LOST_PANEL_COLOR)


func _draw_map() -> void:
	var origin: Vector2 = Vector2(size.x - MAP_SIZE.x - MAP_MARGIN, size.y - MAP_SIZE.y - MAP_MARGIN)
	draw_rect(Rect2(origin, MAP_SIZE), Color(0.0, 0.0, 0.0, 0.4))
	draw_texture_rect(UiKit.icon("palm"), Rect2(origin + Vector2(6.0, 6.0), Vector2.ONE * 28.0), false, Color.WHITE)
	for slot: int in body_input.get_slot_count():
		if body_input.is_aiming(slot):
			var centre: Vector2 = origin + body_input.get_hand_position(slot) * MAP_SIZE
			draw_circle(centre, DOT_RADIUS, Color(SLOT_COLORS[slot], 0.6))


## Icon-only prompt. A palm asks for a hand and a crossed hand marks a lost one, so the colour is a second cue.
func _draw_panel(icon_name: String, colour: Color) -> void:
	var panel_size: Vector2 = Vector2(minf(PANEL_SIZE.x, size.x - MAP_MARGIN * 2.0), PANEL_SIZE.y)
	var panel: Rect2 = Rect2((size - panel_size) * 0.5, panel_size)
	draw_style_box(UiKit.brush(colour, Color.WHITE, 0.0, 6), panel)
	var icon_size: float = panel_size.y * 0.6
	draw_texture_rect(UiKit.icon(icon_name), Rect2(panel.get_center() - Vector2.ONE * icon_size * 0.5, Vector2.ONE * icon_size), false, Color.WHITE)
