class_name BrushPanel
extends StyleBox
## A hand-painted panel background: a ragged, semi-transparent wash with dry-brush accent strokes and no outline.
##
## It carries the hand-drawn look of the title logo into every box and lets the game show through, so the panel blends in and never reads as a framed box.
## The shape depends only on the seed and the size, so it is built once per size and a panel never shimmers.

const GLOW: Color = Color(1.0, 0.55, 0.15, 0.04)
## A dark wash under the text. Without an outline, it keeps text readable when a bright fire or sky shows through the fill.
const TEXT_WASH: Color = Color(0.03, 0.01, 0.08, 0.5)
## Pixels between two points on the ragged edge.
const EDGE_STEP: float = 9.0
const ROUGHNESS: float = 2.4
## Most opaque a fill gets, so the scene always shows through.
const MAX_ALPHA: float = 0.7
## Extra pixels and alpha share of the two soft rims that fade the edge into the scene.
const FEATHER_OUTER: float = 5.0
const FEATHER_MID: float = 2.5
const FEATHER_OUTER_ALPHA: float = 0.28
const FEATHER_MID_ALPHA: float = 0.55
const STROKE_ALPHA: float = 0.6
const STREAK_ALPHA: float = 0.2

var fill: Color = Color(0.09, 0.05, 0.17, MAX_ALPHA)
var accent: Color = Color(1.0, 0.6, 0.18)
var seed_value: int = 1
## Adds a faint accent glow behind the panel when set. Small chips turn it off, so they stay quiet.
var heavy: bool = true
var _shapes: Dictionary[Vector2i, Dictionary] = {}


## Builds a panel style. The margin keeps content clear of the ragged edge and the accent strokes.
static func create(fill_colour: Color, accent_colour: Color, margin: float = 12.0, seed_number: int = 1, heavy_look: bool = true) -> BrushPanel:
	var style := BrushPanel.new()
	style.fill = Color(fill_colour, minf(fill_colour.a, MAX_ALPHA))
	style.accent = accent_colour
	style.seed_value = seed_number
	style.heavy = heavy_look
	style.set_content_margin_all(maxf(margin, ROUGHNESS * 3.0 + FEATHER_OUTER))
	return style


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	var shape: Dictionary = _shape_for(rect.size)
	var origin: Vector2 = rect.position
	if heavy:
		RenderingServer.canvas_item_add_polygon(to_canvas_item, _moved(shape["glow"], origin), PackedColorArray([Color(accent, GLOW.a)]))
	RenderingServer.canvas_item_add_polygon(to_canvas_item, _moved(shape["outer"], origin), PackedColorArray([Color(fill, fill.a * FEATHER_OUTER_ALPHA)]))
	RenderingServer.canvas_item_add_polygon(to_canvas_item, _moved(shape["mid"], origin), PackedColorArray([Color(fill, fill.a * FEATHER_MID_ALPHA)]))
	RenderingServer.canvas_item_add_polygon(to_canvas_item, _moved(shape["base"], origin), PackedColorArray([fill]))
	RenderingServer.canvas_item_add_polygon(to_canvas_item, _moved(shape["wash"], origin), PackedColorArray([TEXT_WASH]))
	for stroke: PackedVector2Array in shape["strokes"]:
		RenderingServer.canvas_item_add_polygon(to_canvas_item, _moved(stroke, origin), PackedColorArray([Color(accent, STROKE_ALPHA)]))
	for streak: PackedVector2Array in shape["streaks"]:
		RenderingServer.canvas_item_add_polygon(to_canvas_item, _moved(streak, origin), PackedColorArray([Color(accent, STREAK_ALPHA)]))


func _get_draw_rect(rect: Rect2) -> Rect2:
	return rect.grow(FEATHER_OUTER + 10.0)


func _shape_for(size: Vector2) -> Dictionary:
	var key := Vector2i(int(size.x), int(size.y))
	if _shapes.has(key):
		return _shapes[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 7919 + key.x * 31 + key.y
	var inset: float = FEATHER_OUTER + 2.0
	var body := Rect2(Vector2.ONE * inset, size - Vector2.ONE * inset * 2.0)
	var shape: Dictionary = {
		"base": _ragged(body, rng, ROUGHNESS),
		"outer": _ragged(body.grow(FEATHER_OUTER), rng, ROUGHNESS * 1.4),
		"mid": _ragged(body.grow(FEATHER_MID), rng, ROUGHNESS * 1.2),
		"wash": _ragged(body.grow(-minf(6.0, minf(body.size.x, body.size.y) * 0.2)), rng, ROUGHNESS),
		"glow": _ragged(body.grow(10.0), rng, ROUGHNESS * 2.0),
		"strokes": _strokes(body, rng),
		"streaks": _streaks(body, rng),
	}
	_shapes[key] = shape
	return shape


## Walks the rectangle edge with a small random push on every point, and cuts the corners so the shape reads as a swipe of paint.
func _ragged(rect: Rect2, rng: RandomNumberGenerator, roughness: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var cut: float = minf(14.0, minf(rect.size.x, rect.size.y) * 0.25)
	var corners: Array[Vector2] = [
		rect.position + Vector2(cut, 0.0), rect.position + Vector2(rect.size.x - cut, 0.0),
		rect.position + Vector2(rect.size.x, cut), rect.position + Vector2(rect.size.x, rect.size.y - cut),
		rect.position + Vector2(rect.size.x - cut, rect.size.y), rect.position + Vector2(cut, rect.size.y),
		rect.position + Vector2(0.0, rect.size.y - cut), rect.position + Vector2(0.0, cut),
	]
	for index: int in corners.size():
		var from: Vector2 = corners[index]
		var to: Vector2 = corners[(index + 1) % corners.size()]
		var steps: int = maxi(1, int(from.distance_to(to) / EDGE_STEP))
		var along: Vector2 = (to - from).normalized()
		var normal := Vector2(along.y, -along.x)
		for step: int in steps:
			var point: Vector2 = from.lerp(to, float(step) / steps)
			points.append(point + normal * rng.randf_range(-roughness, roughness) * 0.5 + along * rng.randf_range(-1.0, 1.0))
	return points


## Two or three tapered paint strokes on the top and bottom edge, with gaps where the brush ran dry.
func _strokes(body: Rect2, rng: RandomNumberGenerator) -> Array[PackedVector2Array]:
	var strokes: Array[PackedVector2Array] = []
	for edge: int in 2:
		var y: float = body.position.y + 3.0 if edge == 0 else body.end.y - 3.0
		var direction: float = 1.0 if edge == 0 else -1.0
		var cursor: float = body.position.x + body.size.x * rng.randf_range(0.03, 0.1)
		var limit: float = body.end.x - body.size.x * rng.randf_range(0.03, 0.1)
		while cursor < limit - 12.0:
			var length: float = minf(rng.randf_range(0.3, 0.6) * body.size.x, limit - cursor)
			var thick: float = rng.randf_range(3.0, 5.0)
			var wobble: float = rng.randf_range(-1.5, 1.5)
			var tip: float = rng.randf_range(0.3, 0.7)
			var stroke := PackedVector2Array([
				Vector2(cursor, y), Vector2(cursor + length * 0.5, y + wobble),
				Vector2(cursor + length, y + wobble * 0.5 + direction * thick * tip),
				Vector2(cursor + length * 0.55, y + direction * thick + wobble),
				Vector2(cursor + length * 0.05, y + direction * thick * 0.6),
			])
			strokes.append(stroke)
			cursor += length + rng.randf_range(6.0, 16.0)
	return strokes


## Thin faint lines across the fill that look like bristle marks. They stay far below text contrast.
func _streaks(body: Rect2, rng: RandomNumberGenerator) -> Array[PackedVector2Array]:
	var streaks: Array[PackedVector2Array] = []
	var count: int = clampi(int(body.size.y / 22.0), 1, 4)
	for index: int in count:
		var y: float = body.position.y + body.size.y * (index + 1.0) / (count + 1.0) + rng.randf_range(-3.0, 3.0)
		var start: float = body.position.x + body.size.x * rng.randf_range(0.05, 0.4)
		var end: float = start + body.size.x * rng.randf_range(0.2, 0.5)
		end = minf(end, body.end.x - 6.0)
		streaks.append(PackedVector2Array([Vector2(start, y), Vector2(end, y + rng.randf_range(-1.0, 1.0)), Vector2(end - 6.0, y + 2.0), Vector2(start + 4.0, y + 1.5)]))
	return streaks


func _moved(points: PackedVector2Array, offset: Vector2) -> PackedVector2Array:
	var moved := PackedVector2Array()
	moved.resize(points.size())
	for index: int in points.size():
		moved[index] = points[index] + offset
	return moved
