class_name AimReticle
extends Control
## Draws the hand or pointer reticle on the intro screens. The run itself needs no aim.

## Reticle radius in pixels.
const RADIUS: float = 26.0
## Line width in pixels.
const LINE_WIDTH: float = 5.0
## Extra width of the dark outline that keeps the reticle visible on any background.
const OUTLINE_EXTRA: float = 4.0
## Reticle colour while firing.
const FIRE_COLOR: Color = Color(1.0, 0.09, 0.27)
## Colour per slot so players tell their reticles apart.
const SLOT_COLORS: Array[Color] = [
	Color.WHITE, Color(0.3, 0.9, 1.0), Color(1.0, 0.9, 0.3), Color(1.0, 0.5, 0.9),
]

## Inputs whose slots are drawn.
@export var inputs: Array[PlayerInput] = []


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var drawn: bool = false
	for input_index: int in inputs.size():
		var input: PlayerInput = inputs[input_index]
		for slot: int in input.get_slot_count():
			# The mouse keeps aiming after it moves once, so a lower-priority input never adds a second cursor.
			if input.is_aiming(slot) and not drawn:
				_draw_reticle(input.get_aim_point(slot) * size, slot, input.is_firing(slot))
				drawn = true


func _draw_reticle(centre: Vector2, slot: int, firing: bool) -> void:
	var colour: Color = FIRE_COLOR if firing else SLOT_COLORS[slot % SLOT_COLORS.size()]
	var reach: float = RADIUS + 10.0
	draw_arc(centre, RADIUS, 0.0, TAU, 32, Color.BLACK, LINE_WIDTH + OUTLINE_EXTRA)
	draw_line(centre + Vector2(-reach, 0.0), centre + Vector2(reach, 0.0), Color.BLACK, LINE_WIDTH + OUTLINE_EXTRA)
	draw_line(centre + Vector2(0.0, -reach), centre + Vector2(0.0, reach), Color.BLACK, LINE_WIDTH + OUTLINE_EXTRA)
	draw_arc(centre, RADIUS, 0.0, TAU, 32, colour, LINE_WIDTH)
	draw_line(centre + Vector2(-reach, 0.0), centre + Vector2(reach, 0.0), colour, LINE_WIDTH)
	draw_line(centre + Vector2(0.0, -reach), centre + Vector2(0.0, reach), colour, LINE_WIDTH)
	if firing:
		draw_circle(centre, RADIUS, Color(FIRE_COLOR, 0.5))
