class_name Hud
extends Control
## Screen-space HUD: boss health, hearts, focus pips, stance pads, hint and end text.

## Pad rectangles in the bottom 40 percent, ordered LEFT, DUCK, RIGHT.
const PAD_RECTS: Array[Rect2] = [
	Rect2(12, 710, 168, 220), Rect2(186, 710, 168, 220), Rect2(360, 710, 168, 220),
]
## Stance for each pad.
const PAD_STANCES: Array[int] = [DuelRules.Stance.LEFT, DuelRules.Stance.DUCK, DuelRules.Stance.RIGHT]
## Pad captions.
const PAD_NAMES: Array[String] = ["LEFT", "DUCK", "RIGHT"]
## Keyboard hints.
const PAD_KEYS: Array[String] = ["A", "S", "D"]

## Boss health left.
var boss_hp: int = 3
## Hero hearts left.
var hearts: int = 3
## Focus pips held.
var pips: int = 0
## Active stance.
var stance: int = DuelRules.Stance.CENTER
## Text shown after a win or loss.
var end_text: String = ""
## Opacity of the first-input hint.
var hint_alpha: float = 1.0

var _font: Font = ThemeDB.fallback_font


## Returns the pad index under [param point], or -1.
static func pad_at(point: Vector2) -> int:
	for i: int in PAD_RECTS.size():
		if PAD_RECTS[i].has_point(point):
			return i
	return -1


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	for i: int in 3:
		var heart_color: Color = Palette.CYAN if i < hearts else Color(Palette.CYAN, 0.2)
		_draw_heart(Vector2(30.0 + i * 36.0, 30.0), 11.0, heart_color)
		var boss_color: Color = Palette.MAGENTA if i < boss_hp else Color(Palette.MAGENTA, 0.2)
		var c: Vector2 = Vector2(270.0 + (i - 1) * 32.0, 28.0)
		draw_colored_polygon([c + Vector2(0, -11), c + Vector2(11, 0), c + Vector2(0, 11), c + Vector2(-11, 0)], boss_color)
		var focus_c: Vector2 = Vector2(270.0 + (i - 1) * 34.0, 676.0)
		draw_arc(focus_c, 11.0, 0.0, TAU, 20, Color(Palette.AMBER, 0.6), 2.0)
		if i < pips:
			draw_circle(focus_c, 8.0, Palette.AMBER)
	for i: int in PAD_RECTS.size():
		_draw_pad(i)
	_text(end_text, 590.0, 34, Palette.INK, 1.0)
	_text("Tap a pad to shift stance. Dodge the shot.", 626.0, 17, Palette.INK, hint_alpha * 0.8)


func _draw_pad(i: int) -> void:
	var rect: Rect2 = PAD_RECTS[i]
	var active: bool = stance == PAD_STANCES[i]
	draw_rect(rect, Color(Palette.CYAN, 0.28) if active else Color("#101018"))
	draw_rect(rect, Palette.CYAN if active else Color(Palette.CYAN, 0.5), false, 4.0 if active else 2.0)
	var c: Vector2 = rect.get_center() + Vector2(0, -22)
	var shape: Array[Vector2]
	match PAD_STANCES[i]:
		DuelRules.Stance.LEFT:
			shape = [c + Vector2(-22, 0), c + Vector2(16, -24), c + Vector2(16, 24)]
		DuelRules.Stance.RIGHT:
			shape = [c + Vector2(22, 0), c + Vector2(-16, -24), c + Vector2(-16, 24)]
		_:
			shape = [c + Vector2(0, 20), c + Vector2(-26, -14), c + Vector2(26, -14)]
	draw_colored_polygon(shape, Palette.CYAN)
	_text(PAD_NAMES[i], rect.position.y + 150.0, 26, Palette.INK, 1.0, rect.position.x, rect.size.x)
	_text(PAD_KEYS[i], rect.position.y + 200.0, 16, Palette.CYAN, 0.7, rect.position.x, rect.size.x)


func _draw_heart(c: Vector2, s: float, tint: Color) -> void:
	draw_circle(c + Vector2(-s * 0.5, -s * 0.3), s * 0.58, tint)
	draw_circle(c + Vector2(s * 0.5, -s * 0.3), s * 0.58, tint)
	draw_colored_polygon([c + Vector2(-s * 1.04, -s * 0.1), c + Vector2(s * 1.04, -s * 0.1), c + Vector2(0, s * 1.05)], tint)


func _text(text: String, y: float, size: int, tint: Color, alpha: float, x: float = 0.0, width: float = 540.0) -> void:
	if text.is_empty() or alpha <= 0.0:
		return
	draw_string(_font, Vector2(x, y), text, HORIZONTAL_ALIGNMENT_CENTER, width, size, Color(tint, alpha))
