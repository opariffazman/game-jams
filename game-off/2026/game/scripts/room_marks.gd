class_name RoomMarks
extends RefCounted
## Draws the planning marks of the turn about to be played: jam cross, advance and knife arrows, knife danger zone, reinforcement ring.
## Reads the simulation only ([TurnSteps] gives the step targets), so the marks cannot disagree with the rules.

## Font size of the short mark labels.
const LABEL_SIZE: int = 26
## Radius of the reinforcement ring.
const RING_RADIUS: float = 28.0


## Returns the one-line banner for the events of the planned turn, or an empty string.
static func banner(state: RoomState) -> String:
	var words: Array[String] = []
	if not state.events_now("jam").is_empty():
		words.append("JAM")
	if not state.events_now("advance").is_empty():
		words.append("ADVANCE")
	if not state.events_now("reinforce").is_empty():
		words.append("+1 GUNMAN")
	return "" if words.is_empty() else "THIS TURN  " + "  ".join(words)


## Draws every mark of the planned turn onto [param canvas].
static func draw(canvas: CanvasItem, state: RoomState) -> void:
	for event: Dictionary in state.events_now("jam"):
		var params: Dictionary = event["params"]
		var gun: int = int(params["gun"])
		if state.alive[gun]:
			_draw_jam(canvas, state, gun)
	for i: int in state.guns.size():
		if state.alive[i] and state.kinds[i] == RoomState.Kind.KNIFE:
			_draw_zone(canvas, state.guns[i])
	for step: Dictionary in TurnSteps.plan_steps(state):
		_draw_arrow(canvas, step["from"], step["to"], Palette.MAGENTA if step["cause"] == "knife" else Palette.INK)
	for event: Dictionary in state.events_now("reinforce"):
		var params: Dictionary = event["params"]
		_draw_ring(canvas, params["pos"])


static func _draw_jam(canvas: CanvasItem, state: RoomState, gun: int) -> void:
	var pos: Vector2 = state.guns[gun]
	var dir: Vector2 = pos.direction_to(state.hero)
	var muzzle: Vector2 = pos + Vector2(0, -10) + dir * 24.0
	for pass_width: float in [10.0, 5.0]:
		var color: Color = Palette.PANEL if pass_width > 6.0 else Palette.AMBER
		canvas.draw_line(muzzle + Vector2(-11, -11), muzzle + Vector2(11, 11), color, pass_width, true)
		canvas.draw_line(muzzle + Vector2(-11, 11), muzzle + Vector2(11, -11), color, pass_width, true)
	_draw_label(canvas, pos + Vector2(40, 8), "JAM", Palette.AMBER)


static func _draw_zone(canvas: CanvasItem, knife: Vector2) -> void:
	var size: Vector2 = Rooms.cell_size()
	var center: Vector2i = Rooms.cell_of(knife)
	for cell: Vector2i in TurnSteps.knife_zone_cells(knife):
		var corner: Vector2 = Rooms.FLOOR.position + Vector2(cell) * size
		canvas.draw_rect(Rect2(corner, size), Color(Palette.MAGENTA, 0.16))
		for side: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var next: Vector2i = cell + side
			if absi(next.x - center.x) + absi(next.y - center.y) > TurnSteps.KNIFE_REACH:
				var start: Vector2 = corner + Vector2(size.x if side == Vector2i.RIGHT else 0.0, size.y if side == Vector2i.DOWN else 0.0)
				var along: Vector2 = Vector2(size.x, 0.0) if side.x == 0 else Vector2(0.0, size.y)
				canvas.draw_line(start, start + along, Color(Palette.MAGENTA, 0.9), 3.0)


static func _draw_ring(canvas: CanvasItem, center: Vector2) -> void:
	for dash: int in 10:
		var start: float = TAU * dash / 10.0
		canvas.draw_arc(center, RING_RADIUS, start, start + TAU / 20.0, 5, Palette.CYAN, 5.0, true)
	_draw_label(canvas, center + Vector2(-16, 9), "+1", Palette.CYAN)


static func _draw_arrow(canvas: CanvasItem, from: Vector2, to: Vector2, color: Color) -> void:
	var dir: Vector2 = from.direction_to(to)
	var side: Vector2 = dir.orthogonal()
	var start: Vector2 = from + dir * 30.0
	var tip: Vector2 = from + dir * 60.0
	canvas.draw_line(start, tip - dir * 6.0, color, 7.0, true)
	canvas.draw_colored_polygon(PackedVector2Array([tip, tip - dir * 16.0 + side * 10.0, tip - dir * 16.0 - side * 10.0]), color)


static func _draw_label(canvas: CanvasItem, at: Vector2, text: String, color: Color) -> void:
	var font: Font = ThemeDB.fallback_font
	canvas.draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, 8, Palette.PANEL)
	canvas.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, color)
