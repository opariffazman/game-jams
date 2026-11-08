class_name BossBackdrop
extends Node2D
## Magenta silhouette of the manager with a tie, drawn behind the boss room. Decoration only: it takes no part in the rules.

## Fill opacity while a room is played.
const PLAY_ALPHA: float = 0.26
## Fill opacity on the intro and stinger cards.
const CARD_ALPHA: float = 0.55

## Opacity of the silhouette fill. The tie draws brighter.
var intensity: float = PLAY_ALPHA:
	set(value):
		intensity = value
		queue_redraw()


func _draw() -> void:
	var fill: Color = Color(Palette.MAGENTA, intensity)
	draw_circle(Vector2(270, 222), 58.0, fill)
	draw_colored_polygon(PackedVector2Array([Vector2(238, 272), Vector2(302, 272), Vector2(500, 330), Vector2(540, 960), Vector2(0, 960), Vector2(40, 330)]), fill)
	draw_colored_polygon(PackedVector2Array([Vector2(270, 370), Vector2(234, 276), Vector2(306, 276)]), Color("08080c"))
	var tie: Color = Color(Palette.MAGENTA, minf(intensity + 0.35, 1.0))
	draw_colored_polygon(PackedVector2Array([Vector2(256, 300), Vector2(284, 300), Vector2(290, 330), Vector2(250, 330)]), tie)
	draw_colored_polygon(PackedVector2Array([Vector2(250, 334), Vector2(290, 334), Vector2(304, 540), Vector2(270, 584), Vector2(236, 540)]), tie)
