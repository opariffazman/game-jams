class_name TitleLogo
extends Control
## The game title as a logo: "Home by" small and cream, "Light" large and orange, each with a stacked extrusion, an outline and a glow.
##
## It is drawn by hand because a Label has one outline and no extrusion, and the poster look needs both.

const FONT_PATH: String = "res://assets/fonts/AtkinsonNext-Variable.woff2"
const WEIGHT_AXIS: int = 0x77676874
const WEIGHT: int = 800
const CREAM: Color = Color(1.0, 0.95, 0.85)
const ORANGE: Color = Color(1.0, 0.64, 0.24)
const EXTRUSION: Color = Color(0.72, 0.3, 0.05)
const OUTLINE: Color = Color(0.1, 0.03, 0.18)
const GLOW: Color = Color(1.0, 0.55, 0.15, 0.1)
const SMALL_RATIO: float = 0.42
const DEPTH_STEPS: int = 9
const GLOW_RINGS: int = 5
## Seconds for one slow glow pulse, so the title feels alive without distracting.
const PULSE_SECONDS: float = 3.2

## Height in pixels of the large word. The small word and the box follow it.
var big_size: int = 150:
	set(value):
		big_size = value
		custom_minimum_size = Vector2(big_size * 4.4, big_size * (1.0 + SMALL_RATIO) * 1.1)
		queue_redraw()

var _font: FontVariation


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var base: FontFile = load(FONT_PATH)
	_font = FontVariation.new()
	_font.base_font = base
	_font.variation_opentype = {WEIGHT_AXIS: WEIGHT}
	big_size = big_size


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if _font == null:
		return
	var small_size: int = int(big_size * SMALL_RATIO)
	var pulse: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * TAU / PULSE_SECONDS)
	var centre_x: float = size.x * 0.5
	var small_y: float = small_size * 0.95
	var big_y: float = small_y + big_size * 0.92
	_word("Home by", small_size, centre_x, small_y, CREAM, pulse, false)
	_word("Light", big_size, centre_x, big_y, ORANGE, pulse, true)


func _word(text: String, font_size: int, centre_x: float, baseline: float, face: Color, pulse: float, glow: bool) -> void:
	var width: float = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var origin := Vector2(centre_x - width * 0.5, baseline)
	if glow:
		for ring: int in GLOW_RINGS:
			var spread: float = (ring + 1) * font_size * 0.045 * (0.85 + 0.3 * pulse)
			draw_string_outline(_font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, int(spread * 2.0), Color(GLOW, GLOW.a * (1.0 + pulse * 0.6)))
	var step: float = font_size * 0.012
	for depth: int in range(DEPTH_STEPS, 0, -1):
		var shade: float = 1.0 - float(depth) / (DEPTH_STEPS + 3)
		var offset := Vector2(depth * step * 0.5, depth * step)
		var layer: Color = EXTRUSION.lerp(OUTLINE, 1.0 - shade)
		draw_string_outline(_font, origin + offset, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, int(font_size * 0.09), OUTLINE)
		draw_string(_font, origin + offset, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, layer)
	draw_string_outline(_font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, int(font_size * 0.09), OUTLINE)
	draw_string(_font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, face)
