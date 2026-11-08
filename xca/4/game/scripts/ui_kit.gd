class_name UiKit
extends RefCounted
## Shared look of every screen: colours, panel and button styles, icon loading and the layout scale.
##
## Style: chunky white silhouette icons on hand-painted, semi-transparent brush panels (BrushPanel) with orange accent strokes and no outlines.
## Contrast (WCAG), measured with a white scene behind the panel, which is the worst case: white on PANEL 13:1, on SECONDARY 9:1, on PRIMARY 8:1. See the brush panel text wash.

const PANEL: Color = Color(0.09, 0.05, 0.17, 0.7)
const PANEL_SOLID: Color = Color(0.09, 0.05, 0.17)
const SECONDARY: Color = Color(0.29, 0.15, 0.5)
const PRIMARY: Color = Color(0.06, 0.4, 0.2)
const ORANGE: Color = Color(1.0, 0.6, 0.18)
const TEXT: Color = Color.WHITE
const TEXT_DIM: Color = Color(0.85, 0.82, 0.95)
const HEART_FULL: Color = Color(1.0, 0.35, 0.45)
const GOLD: Color = Color(1.0, 0.9, 0.4)
const DIRT: Color = Color(0.85, 0.58, 0.3)
## Touch targets never go under this many CSS pixels.
const MIN_TARGET: float = 48.0
## Layout pixels between the screen edge and the first widget.
const MARGIN: float = 12.0
const RADIUS: int = 14
const ICON: float = 40.0
const FONT: int = 26
const MIN_SCALE: float = 0.75
const MAX_SCALE: float = 2.5
const REFERENCE_SIDE: float = 720.0
const FONT_PATH: String = "res://assets/fonts/AtkinsonNext-Variable.woff2"
const WEIGHT_AXIS: int = 0x77676874
## Bold enough to match the title logo while the counters stay legible at small sizes.
const WEIGHT: int = 700

## Names shown by the credits list. The game has no credits screen yet.
const CREDIT_LINES: PackedStringArray = [
	"Icons: Kenney (CC0)",
	"Icons: Lorc, Delapouite, John Colburn, Sbed (CC BY 3.0)",
]

static var _icons: Dictionary[String, Texture2D] = {}
static var _theme: Theme
static var _font: FontVariation
static var _brushes: Dictionary[String, BrushPanel] = {}


## The shared UI font, loaded once. It is Atkinson Hyperlegible Next, chosen for legibility.
static func font() -> FontVariation:
	if _font == null:
		_font = FontVariation.new()
		_font.base_font = load(FONT_PATH) as FontFile
		_font.variation_opentype = {WEIGHT_AXIS: WEIGHT}
	return _font


## A cached brush panel. Callers that draw every frame reuse one instance per look, so the shape is built once per size.
static func brush(fill: Color = PANEL, accent: Color = ORANGE, margin: float = 10.0, seed_number: int = 1, heavy: bool = true) -> BrushPanel:
	var key: String = "%s|%s|%s|%d|%s" % [fill.to_html(true), accent.to_html(true), margin, seed_number, heavy]
	if not _brushes.has(key):
		_brushes[key] = BrushPanel.create(fill, accent, margin, seed_number, heavy)
	return _brushes[key]


## Loads an icon once. The names match the PNG files in assets/ui.
static func icon(icon_name: String) -> Texture2D:
	if not _icons.has(icon_name):
		_icons[icon_name] = load("res://assets/ui/%s.png" % icon_name) as Texture2D
	return _icons[icon_name]


## Scale from CSS pixels to layout pixels: the shorter side over 720, so 1440p and 4K grow the UI.
static func scale_for(css_size: Vector2) -> float:
	return clampf(minf(css_size.x, css_size.y) / REFERENCE_SIDE, MIN_SCALE, MAX_SCALE)


static func box(fill: Color, border: Color = ORANGE, border_width: int = 3, radius: int = RADIUS, margin: float = 10.0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(margin)
	style.anti_aliasing = true
	return style


## Style for a panel drawn by hand with draw_style_box.
static func panel_box() -> StyleBox:
	return brush()


static func theme() -> Theme:
	if _theme != null:
		return _theme
	_theme = Theme.new()
	_theme.default_font = font()
	_theme.default_font_size = FONT
	_theme.set_color("font_color", "Label", TEXT)
	_theme.set_color("font_shadow_color", "Label", Color(0.0, 0.0, 0.0, 0.7))
	_theme.set_constant("shadow_offset_x", "Label", 1)
	_theme.set_constant("shadow_offset_y", "Label", 2)
	_theme.set_constant("shadow_outline_size", "Label", 3)
	_theme.set_stylebox("panel", "PanelContainer", panel_box())
	var states: Dictionary[String, Color] = {
		"normal": SECONDARY, "hover": SECONDARY.lightened(0.15), "pressed": SECONDARY.darkened(0.3),
		"disabled": Color(0.2, 0.17, 0.27), "focus": Color(0, 0, 0, 0),
	}
	var seed_number: int = 3
	for state: String in states:
		var style: StyleBox = brush(states[state], Color.WHITE if state != "normal" else ORANGE, 8.0, seed_number, state != "pressed")
		if state == "focus":
			# A thick white ring over the normal border keeps keyboard focus visible without colour.
			var ring: StyleBoxFlat = box(Color(0, 0, 0, 0), Color.WHITE, 5)
			ring.draw_center = false
			ring.expand_margin_left = 3.0
			ring.expand_margin_right = 3.0
			ring.expand_margin_top = 3.0
			ring.expand_margin_bottom = 3.0
			style = ring
		_theme.set_stylebox(state, "Button", style)
	for colour_name: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
		_theme.set_color(colour_name, "Button", TEXT)
	_theme.set_color("font_disabled_color", "Button", TEXT_DIM)
	_theme.set_color("icon_disabled_color", "Button", TEXT_DIM)
	_theme.set_constant("icon_max_width", "Button", int(ICON))
	_theme.set_constant("h_separation", "Button", 10)
	_theme.set_font_size("font_size", "Button", FONT)
	_theme.set_stylebox("background", "ProgressBar", box(Color(0.03, 0.02, 0.07, 0.6), Color(0, 0, 0, 0), 0, 8, 0.0))
	_theme.set_stylebox("fill", "ProgressBar", box(DIRT, DIRT, 0, 6, 0.0))
	return _theme


## Makes a button that shows an icon and at most one short word. The name is the tooltip, and the word is the only text.
static func icon_button(icon_name: String, action: Callable, word: String = "", tooltip: String = "", min_size: Vector2 = Vector2(MIN_TARGET, MIN_TARGET)) -> Button:
	var button := Button.new()
	button.theme = theme()
	if not icon_name.is_empty():
		button.icon = icon(icon_name)
	button.expand_icon = true
	button.text = word
	button.tooltip_text = tooltip if not tooltip.is_empty() else word
	button.custom_minimum_size = min_size.max(Vector2(MIN_TARGET, MIN_TARGET))
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER if word.is_empty() else HORIZONTAL_ALIGNMENT_LEFT
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.pressed.connect(action)
	return button


static func primary(button: Button) -> void:
	for state: String in ["normal", "hover", "pressed"]:
		button.add_theme_stylebox_override(state, brush(PRIMARY if state != "pressed" else PRIMARY.darkened(0.3), Color.WHITE if state == "hover" else GOLD, 8.0, 4, state != "pressed"))
