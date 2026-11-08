class_name PrimitiveSkinVisual
extends EntityVisual
## Flat-shape art for the primitives skin. One script draws every slot.
##
## Only this skin draws in code. Logic nodes never do.

## Sandal icon drawn for the sandal slots. It points along +x after the draw rotation.
const SANDAL_ICON_PATH: String = "res://assets/icons/sandal_wide.svg"
## Sandal icon width as a multiple of [member radius].
const SANDAL_WIDTH_SCALE: float = 3.0
## Sandal icon height as a multiple of [member radius]. Keep it under the stack spacing.
const SANDAL_HEIGHT_SCALE: float = 1.7
## The icon is rasterised at this multiple of its drawn size so phones stay sharp.
const SANDAL_RASTER_SCALE: int = 3
## Width of the foot of a standing sandal as a multiple of [member radius].
const STANDING_FOOT_WIDTH: float = 1.3
## Colour of the dot on the tip of a standing sandal.
const LIGHT_TIP_COLOR: Color = Color(1.0, 1.0, 1.0, 0.9)
## Dark outline that keeps shapes readable on the floor.
const OUTLINE_COLOR: Color = Color("0f1729")
## Floor colour outside the play area. Fills any extra screen area.
const SURROUND_COLOR: Color = Color("111a2c")
## Line colour of the arena border and markings.
const LINE_COLOR: Color = Color(0.42, 0.48, 0.6)
## Line width of the ring that marks the pass sandal.
const PASS_RING_WIDTH: float = 4.0
## Colour of both guide rings. It keeps at least 3:1 contrast on the arena floor, 3.71 measured.
const THROW_RING_COLOR: Color = Color(0.42, 0.48, 0.6)
## Length of one dash of a guide ring, in radians.
const GUIDE_DASH_RADIANS: float = 0.07
## Gap between two dashes of a guide ring, in radians.
const GUIDE_GAP_RADIANS: float = 0.05
## Size in pixels of the area drawn around the play area, so wide screens show no empty space.
const SURROUND_SIZE: float = 4000.0

enum Shape { CIRCLE, SQUARE, SANDAL, STACK_MARKER, ARENA, TOMBSTONE, EFFECT_RING }

## Shape this scene draws.
@export var shape: Shape = Shape.CIRCLE
## Default fill colour. [method set_team_color] overrides it.
@export var color: Color = Color(0.251, 0.749, 1.0)
## Half size of the shape in pixels. Only a drawing size, never a hitbox.
@export var radius: float = 18.0
## Extra tint for the ring of a pass sandal.
@export var ring_color: Color = Color(0.0, 0.0, 0.0, 0.0)
## Lifetime of an effect ring in seconds.
@export_range(0.05, 2.0, 0.05, "suffix:s") var effect_time: float = 0.35

static var _icon_cache: Dictionary = {}

var _extent: Vector2 = Vector2(1080.0, 600.0)
var _throw_ring_radius: float = 0.0
var _orbit_ring_radius: float = 0.0
var _icon: Texture2D
var _carrying: bool = false
var _flash: float = 0.0
var _tween: Tween
var _standing: bool = false


func _ready() -> void:
	if shape == Shape.SANDAL:
		_icon = _sandal_icon()
	if shape == Shape.EFFECT_RING:
		_run_effect()


func _process(delta: float) -> void:
	if shape == Shape.SANDAL:
		var standing: bool = _lean_angle() > 0.0
		if standing != _standing:
			_standing = standing
			queue_redraw()
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 4.0, 0.0)
		queue_redraw()


func play(state: StringName) -> void:
	match state:
		&"carry":
			_carrying = true
		&"idle", &"run":
			_carrying = false
			modulate.a = 1.0
		&"hit":
			_flash = 1.0
		&"dash":
			modulate.a = 0.55
			_restore_alpha(0.25)
		&"die":
			_carrying = false
			modulate.a = 0.3
	queue_redraw()


func set_team_color(new_color: Color) -> void:
	super.set_team_color(new_color)
	color = new_color
	queue_redraw()


func set_extent(extent: Vector2) -> void:
	_extent = extent
	queue_redraw()


func set_guide_radii(throw_ring: float, orbit_ring: float) -> void:
	_throw_ring_radius = throw_ring
	_orbit_ring_radius = orbit_ring
	queue_redraw()


func _draw() -> void:
	var fill: Color = color.lerp(Color.WHITE, _flash)
	match shape:
		Shape.CIRCLE:
			draw_circle(Vector2.ZERO, radius + 2.0, OUTLINE_COLOR)
			draw_circle(Vector2.ZERO, radius, fill)
			_draw_facing_tick()
			_draw_carry_marker()
		Shape.SQUARE:
			var outer: float = radius + 2.0
			draw_rect(Rect2(-outer, -outer, outer * 2.0, outer * 2.0), OUTLINE_COLOR)
			draw_rect(Rect2(-radius, -radius, radius * 2.0, radius * 2.0), fill)
			_draw_facing_tick()
			_draw_carry_marker()
		Shape.SANDAL:
			_draw_sandal(fill)
		Shape.STACK_MARKER:
			draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, color, 3.0)
		Shape.ARENA:
			_draw_arena()
		Shape.TOMBSTONE:
			draw_rect(Rect2(-radius * 0.6, -radius * 0.2, radius * 1.2, radius * 1.2), color)
			draw_circle(Vector2(0.0, -radius * 0.2), radius * 0.6, color)
			draw_line(Vector2(0.0, -radius * 0.2), Vector2(0.0, radius * 0.7), Color(0.06, 0.09, 0.16), 3.0)
			draw_line(Vector2(-radius * 0.3, radius * 0.1), Vector2(radius * 0.3, radius * 0.1), Color(0.06, 0.09, 0.16), 3.0)
		Shape.EFFECT_RING:
			draw_arc(Vector2.ZERO, radius, 0.0, TAU, 40, color, 4.0)


func _draw_facing_tick() -> void:
	draw_line(Vector2(radius * 0.3, 0.0), Vector2(radius * 0.75, 0.0), OUTLINE_COLOR, 2.0)


func _draw_carry_marker() -> void:
	if _carrying:
		draw_circle(Vector2(0.0, -radius - 6.0), radius * 0.3, Color(0.96, 0.84, 0.55))


# The view is top-down, so the side-view icon is drawn wide and flat. Its height must stay under
# the stack spacing, or neighbours in the stack overlap into one blob.
func _draw_sandal(fill: Color) -> void:
	var lean: float = _lean_angle()
	if lean > 0.0:
		_draw_standing_sandal(fill, lean)
		return
	var size: Vector2 = Vector2(radius * SANDAL_WIDTH_SCALE, radius * SANDAL_HEIGHT_SCALE)
	if _icon != null:
		draw_texture_rect(_icon, Rect2(-size * 0.5, size), false, OUTLINE_COLOR)
		var inner: Vector2 = size * 0.88
		draw_texture_rect(_icon, Rect2(-inner * 0.5, inner), false, fill)
	if ring_color.a > 0.0:
		draw_arc(Vector2.ZERO, radius * 1.5, 0.0, TAU, 32, ring_color, PASS_RING_WIDTH)


# Seen from above, a sandal that stands on its edge and leans is a wedge. The foot is wide and the tip lies
# toward the centre, so the three wedges of a teepee point at one apex. The node rotation already faces the centre.
func _draw_standing_sandal(fill: Color, lean: float) -> void:
	var reach: float = radius * SANDAL_WIDTH_SCALE * sin(lean)
	var half_foot: float = radius * STANDING_FOOT_WIDTH * 0.5
	var outline: float = 2.0
	var wedge: PackedVector2Array = PackedVector2Array([Vector2(0.0, -half_foot), Vector2(reach, 0.0), Vector2(0.0, half_foot)])
	var outer: PackedVector2Array = PackedVector2Array([
		Vector2(-outline, -half_foot - outline), Vector2(reach + outline * 1.6, 0.0), Vector2(-outline, half_foot + outline)])
	draw_colored_polygon(outer, OUTLINE_COLOR)
	draw_colored_polygon(wedge, fill)
	draw_circle(Vector2(reach, 0.0), 2.5, LIGHT_TIP_COLOR)
	if ring_color.a > 0.0:
		draw_arc(Vector2.ZERO, radius * 1.5, 0.0, TAU, 32, ring_color, PASS_RING_WIDTH)


func _draw_arena() -> void:
	var half: Vector2 = _extent * 0.5
	draw_rect(Rect2(Vector2.ONE * -SURROUND_SIZE * 0.5, Vector2.ONE * SURROUND_SIZE), SURROUND_COLOR)
	draw_rect(Rect2(-half, _extent), color)
	draw_rect(Rect2(-half, _extent), LINE_COLOR, false, 4.0)
	draw_line(Vector2(0.0, -half.y), Vector2(0.0, half.y), Color(LINE_COLOR, 0.35), 2.0)
	if _throw_ring_radius > 0.0:
		_draw_dashed_ring(_throw_ring_radius, THROW_RING_COLOR, 3.0)
	if _orbit_ring_radius > 0.0:
		_draw_dashed_ring(_orbit_ring_radius, THROW_RING_COLOR, 2.0)


func _draw_dashed_ring(ring_radius: float, ring_color_value: Color, width: float) -> void:
	var angle: float = 0.0
	while angle < TAU:
		var end: float = minf(angle + GUIDE_DASH_RADIANS, TAU)
		draw_arc(Vector2.ZERO, ring_radius, angle, end, 3, ring_color_value, width)
		angle += GUIDE_DASH_RADIANS + GUIDE_GAP_RADIANS


# The source SVG imports at 512 px. Downscaling it on the GPU shimmers, so it is rasterised once here.
func _sandal_icon() -> Texture2D:
	var raster_size: Vector2i = Vector2i(
		ceili(radius * SANDAL_WIDTH_SCALE) * SANDAL_RASTER_SCALE,
		ceili(radius * SANDAL_HEIGHT_SCALE) * SANDAL_RASTER_SCALE
	)
	if _icon_cache.has(raster_size):
		return _icon_cache[raster_size]
	if not ResourceLoader.exists(SANDAL_ICON_PATH):
		return null
	var source: Texture2D = load(SANDAL_ICON_PATH) as Texture2D
	var image: Image = source.get_image()
	if image.is_compressed():
		image.decompress()
	image.fix_alpha_edges()
	image.resize(raster_size.x, raster_size.y, Image.INTERPOLATE_LANCZOS)
	var texture: ImageTexture = ImageTexture.create_from_image(image)
	_icon_cache[raster_size] = texture
	return texture


func _lean_angle() -> float:
	var holder: Node = get_parent()
	var angle: Variant = holder.get("lean_angle") if holder != null else null
	return angle if angle is float else 0.0


func _restore_alpha(delay: float) -> void:
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_interval(delay)
	_tween.tween_property(self, "modulate:a", 1.0, 0.1)


func _run_effect() -> void:
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(self, "scale", scale * 2.4, effect_time)
	tween.tween_property(self, "modulate:a", 0.0, effect_time)
	tween.chain().tween_callback(queue_free)
