class_name Hallway
extends Node2D
## Neon hallway backdrop: perspective rays, floor lines, lane markers.

## Boss-side vanishing point.
const VANISH: Vector2 = Vector2(270.0, 150.0)


func _draw() -> void:
	for i: int in range(-4, 5):
		draw_line(VANISH, Vector2(270.0 + i * 150.0, 960.0), Color(Palette.MAGENTA, 0.1), 2.0)
	for y: float in [200.0, 240.0, 300.0, 390.0, 520.0, 690.0]:
		draw_line(Vector2(0.0, y), Vector2(540.0, y), Color(Palette.CYAN, 0.07), 2.0)
	draw_line(VANISH, Vector2(0.0, 700.0), Color(Palette.CYAN, 0.4), 3.0)
	draw_line(VANISH, Vector2(540.0, 700.0), Color(Palette.MAGENTA, 0.4), 3.0)
	for x: float in [195.0, 345.0]:
		draw_dashed_line(Vector2(x, 240.0), Vector2(x, 700.0), Color(Palette.INK, 0.1), 2.0, 12.0)
	for x: float in [120.0, 270.0, 420.0]:
		draw_line(Vector2(x - 40.0, 552.0), Vector2(x + 40.0, 552.0), Color(Palette.CYAN, 0.35), 3.0)
