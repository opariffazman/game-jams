class_name Fx
extends Node2D
## World-space effects drawn above the figures: telegraph, bullets, smear, popups.

## Game state to read.
var main: Main

var _font: Font = ThemeDB.fallback_font


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if main.phase == Main.Phase.TELL:
		_draw_telegraph()
	elif main.phase == Main.Phase.FIRE:
		_draw_bullet()
	if main.smear_t > 0.0:
		var a: float = clampf(main.smear_t / 0.3, 0.0, 1.0)
		draw_arc(Main.BOSS_POS + Vector2(0, 30), 86.0, -2.7, -0.45, 28, Color(Palette.INK, a), 10.0 * a + 2.0)
		draw_arc(Main.BOSS_POS + Vector2(0, 30), 100.0, -2.5, -0.65, 28, Color(Palette.CYAN, a * 0.7), 5.0)
	if main.lunge_p > 0.0 and main.phase == Main.Phase.COUNTER:
		draw_line(main.lunge_from, main.hero_base, Color(Palette.CYAN, 0.5 * main.lunge_p), 14.0)
	if main.popup_t > 0.0:
		var pos: Vector2 = main.hero.position + Vector2(-60, -130 - (0.6 - main.popup_t) * 40.0)
		draw_string(_font, pos, main.popup_text, HORIZONTAL_ALIGNMENT_CENTER, 120.0, 22, Color(main.popup_color, minf(main.popup_t * 3.0, 1.0)))


func _draw_telegraph() -> void:
	var tell: int = main.tell
	var pulse: float = 0.75 + 0.25 * sin(main.phase_t * 28.0)
	var tint: Color = Color(Palette.AMBER, pulse)
	if tell == DuelRules.Tell.HIGH:
		draw_dashed_line(Vector2(30, Main.BEAM_Y), Vector2(510, Main.BEAM_Y), tint, 5.0, 16.0)
	else:
		var x: float = Main.TELL_X[tell]
		draw_rect(Rect2(x - 55.0, 215.0, 110.0, 480.0), Color(Palette.AMBER, 0.07))
		draw_dashed_line(Vector2(x, 215), Vector2(x, 690), tint, 5.0, 16.0)
	_draw_icon(Vector2(270, 292), tell, tint)
	draw_string(_font, Vector2(0, 352), DuelRules.TELL_WORDS[tell], HORIZONTAL_ALIGNMENT_CENTER, 540.0, 32, Palette.AMBER)
	var left: float = 1.0 - main.phase_t / main.tell_len
	draw_rect(Rect2(270.0 - 90.0 * left, 364.0, 180.0 * left, 5.0), Palette.AMBER)


func _draw_icon(c: Vector2, tell: int, tint: Color) -> void:
	var s: float = 20.0
	match tell:
		DuelRules.Tell.LEFT:
			draw_colored_polygon([c + Vector2(-s, 0), c + Vector2(s, -s), c + Vector2(s, s)], tint)
		DuelRules.Tell.RIGHT:
			draw_colored_polygon([c + Vector2(s, 0), c + Vector2(-s, -s), c + Vector2(-s, s)], tint)
		DuelRules.Tell.CENTER:
			draw_arc(c, s, 0.0, TAU, 24, tint, 5.0)
			draw_circle(c, s * 0.38, tint)
		_:
			for i: int in 2:
				var y: float = c.y + i * 18.0 - 12.0
				draw_polyline([Vector2(c.x - s, y + 10), Vector2(c.x, y - 8), Vector2(c.x + s, y + 10)], tint, 5.0)


func _draw_bullet() -> void:
	var p: float = clampf(main.phase_t / Main.FIRE_TIME, 0.0, 1.0)
	if main.tell == DuelRules.Tell.HIGH:
		var half: float = lerpf(10.0, 250.0, p)
		draw_rect(Rect2(270.0 - half, Main.BEAM_Y - 9.0, half * 2.0, 18.0), Color(Palette.AMBER, 0.35))
		draw_rect(Rect2(270.0 - half, Main.BEAM_Y - 4.0, half * 2.0, 8.0), Palette.INK)
	else:
		var pos: Vector2 = Vector2(Main.TELL_X[main.tell], lerpf(215.0, 700.0, p))
		draw_circle(pos, 16.0, Color(Palette.AMBER, 0.35))
		draw_circle(pos, 9.0, Palette.INK)
