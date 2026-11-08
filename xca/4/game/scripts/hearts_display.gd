class_name HeartsDisplay
extends Control
## Draws the player hearts as icons. A full heart is solid and a lost heart is an outline, so colour is never the only cue.

## Hearts a hero without its own value starts with.
const DEFAULT_HEARTS: int = 5
## Heart width in pixels.
const HEART_SIZE: float = 44.0
## Gap between hearts in pixels.
const SPACING: float = 6.0
## Padding inside the backing panel in pixels.
const PADDING: float = 8.0
## Gap to the left edge in pixels. The hearts sit top left, so a narrow portrait screen never pushes them off.
const LEFT_MARGIN: float = 12.0
const TOP_MARGIN: float = 8.0
const LOST_COLOR: Color = Color(1.0, 1.0, 1.0, 0.75)

## Hearts currently shown as full.
var hearts: int = DEFAULT_HEARTS:
	set(value):
		hearts = clampi(value, 0, max_hearts)
		queue_redraw()
## Hearts shown in total. The hero table sets it.
var max_hearts: int = DEFAULT_HEARTS:
	set(value):
		max_hearts = value
		queue_redraw()


func _draw() -> void:
	var total_width: float = max_hearts * HEART_SIZE + (max_hearts - 1) * SPACING + PADDING * 2.0
	draw_style_box(UiKit.panel_box(), Rect2(LEFT_MARGIN, TOP_MARGIN, total_width, HEART_SIZE + PADDING * 2.0))
	for index: int in max_hearts:
		var full: bool = index < hearts
		var rect: Rect2 = Rect2(LEFT_MARGIN + PADDING + index * (HEART_SIZE + SPACING), TOP_MARGIN + PADDING, HEART_SIZE, HEART_SIZE)
		draw_texture_rect(UiKit.icon("heart" if full else "heart_o"), rect, false, UiKit.HEART_FULL if full else LOST_COLOR)
