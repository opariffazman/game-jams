class_name TitleScreen
extends CanvasLayer
## Title screen between the web start tap and the coin flip.
##
## The tree stays paused until Play, so the match countdown does not run behind the title.
## Skips for the URL flag [code]?e2e=1[/code], the setting [code]skip_title[/code], a headless run
## and a scene reload (restart). A test can call [method open] by hand.

signal played

const GROUP: StringName = &"title_screen"
const URL_SKIP_FLAG: String = "e2e=1"
const FONT_PATH: String = "res://assets/fonts/AtkinsonNext-Variable.woff2"
const WEIGHT_AXIS: int = 0x77676874
const WEIGHT: int = 800
const TITLE_TEXT: String = "Baling Selipar"
const BACKDROP_TOP: Color = Color("1f160e")
const BACKDROP_BOTTOM: Color = Color("3b2d1e")
const LANTERN: Color = Color("ffc857")
const SAND: Color = Color("e0c48a")
const CREAM: Color = Color("fff3da")
const FRIEND: Color = Color("3d9bff")
const ENEMY: Color = Color("ff5a45")
const PULSE_SECONDS: float = 3.2
const DRIFT_SANDALS: int = 9

## True after the first Play or skip in this process. A scene reload keeps it, so restart never shows the title again.
static var done: bool = false
## A test sets this to show the title in a headless run.
static var show_when_headless: bool = false

var how_to: HowToPlay
var play_button: TitleIconButton
var help_button: TitleIconButton

var _canvas: Control
var _font: FontVariation
var _time: float = 0.0
var _sandal: Texture2D = preload("res://assets/icons/sandal.svg")


## True when the title must not show in this run.
static func should_skip() -> bool:
	if done:
		return true
	if DisplayServer.get_name() == "headless" and not show_when_headless:
		return true
	var settings: Node = Engine.get_main_loop().root.get_node_or_null("Settings")
	if settings != null and settings.get("skip_title"):
		return true
	if OS.has_feature("web"):
		var search: Variant = JavaScriptBridge.eval("window.location.search")
		if search is String and (search as String).trim_prefix("?").split("&").has(URL_SKIP_FLAG):
			return true
	return false


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(GROUP)
	if should_skip():
		done = true
		queue_free()
		return
	open()


## Shows the title and pauses the match.
func open() -> void:
	if _canvas != null:
		return
	_build()
	get_tree().paused = true
	_play_music()


func is_open() -> bool:
	return _canvas != null and _canvas.visible


## Starts the match.
func play() -> void:
	if not is_open():
		return
	done = true
	_canvas.visible = false
	get_tree().paused = false
	played.emit()
	queue_free()


func show_how_to() -> void:
	how_to.open()
	var settings: Node = get_node_or_null("/root/Settings")
	if settings != null:
		settings.call("mark_how_to_seen")


func _build() -> void:
	_font = FontVariation.new()
	_font.base_font = load(FONT_PATH) as Font
	_font.variation_opentype = {WEIGHT_AXIS: WEIGHT}
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.draw.connect(_draw_canvas)
	_canvas.resized.connect(_layout)
	add_child(_canvas)
	play_button = TitleIconButton.new(TitleIconButton.Kind.PLAY)
	play_button.pulse = true
	play_button.pressed.connect(play)
	help_button = TitleIconButton.new(TitleIconButton.Kind.HELP)
	help_button.pressed.connect(show_how_to)
	_canvas.add_child(play_button)
	_canvas.add_child(help_button)
	how_to = HowToPlay.new()
	how_to.visible = false
	_canvas.add_child(how_to)
	how_to.closed.connect(play_button.grab_focus)
	_layout()
	play_button.grab_focus()
	var settings: Node = get_node_or_null("/root/Settings")
	if settings != null and not settings.get("how_to_seen"):
		show_how_to.call_deferred()


func _play_music() -> void:
	AudioRef.play_music(AudioSet.MUSIC_TOPPLE)


func _process(delta: float) -> void:
	_time += delta
	if _canvas != null and _canvas.visible:
		_canvas.queue_redraw()


## Places the buttons. The play button is the largest. Both stay over 44 CSS pixels.
func _layout() -> void:
	if play_button == null or help_button == null:
		return
	var size: Vector2 = _canvas.size
	var short: float = minf(size.x, size.y)
	var floor_px: float = 44.0 * RestartUiScale.pixels_per_css(get_viewport())
	var play_size: float = maxf(short * 0.2, floor_px * 1.6)
	var help_size: float = maxf(short * 0.12, floor_px)
	var portrait: bool = size.y > size.x
	var margin: float = short * 0.04
	play_size = minf(play_size, minf(size.y * 0.3, size.x * 0.5))
	help_size = minf(help_size, play_size)
	var row_y: float = minf(size.y * (0.72 if portrait else 0.62), size.y - play_size - margin)
	var gap: float = play_size * 0.5
	var total: float = play_size + gap + help_size
	var left: float = (size.x - total) * 0.5
	play_button.size = Vector2.ONE * play_size
	play_button.position = Vector2(left, row_y)
	help_button.size = Vector2.ONE * help_size
	help_button.position = Vector2(left + play_size + gap, row_y + (play_size - help_size) * 0.5)


func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if not is_open() or key == null or not key.pressed or key.echo or how_to.visible:
		return
	match key.keycode:
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			play()
		KEY_ESCAPE:
			show_how_to()
		_:
			return
	get_viewport().set_input_as_handled()


func _draw_canvas() -> void:
	var size: Vector2 = _canvas.size
	var short: float = minf(size.x, size.y)
	var bands: int = 24
	for band: int in bands:
		var fraction: float = float(band) / float(bands - 1)
		_canvas.draw_rect(Rect2(0.0, size.y * band / bands, size.x, size.y / bands + 1.0), BACKDROP_TOP.lerp(BACKDROP_BOTTOM, fraction))
	_draw_lantern(size, short)
	_draw_drift(size, short)
	_draw_logo(size, short)


func _draw_lantern(size: Vector2, short: float) -> void:
	var flicker: float = 0.85 + 0.15 * sin(_time * 7.3) * sin(_time * 3.1 + 1.0)
	var centre: Vector2 = Vector2(size.x * 0.5, size.y * 0.3)
	for ring: int in 5:
		var radius: float = short * (0.9 - ring * 0.15)
		_canvas.draw_circle(centre, radius, Color(LANTERN, 0.035 * flicker))


func _draw_drift(size: Vector2, short: float) -> void:
	var unit: float = short * 0.09
	for index: int in DRIFT_SANDALS:
		var lane: float = fposmod(index * 0.6180339 + _time * (0.015 + 0.004 * (index % 3)), 1.0)
		var spot: Vector2 = Vector2(size.x * fposmod(index * 0.3819 + 0.1, 1.0), size.y * (1.1 - lane * 1.3))
		var tint: Color = [SAND, FRIEND, ENEMY][index % 3]
		_canvas.draw_set_transform(spot, _time * 0.3 * (1.0 if index % 2 == 0 else -1.0) + index, Vector2.ONE)
		_canvas.draw_texture_rect(_sandal, Rect2(-Vector2.ONE * unit * 0.5, Vector2.ONE * unit), false, Color(tint, 0.16))
	_canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_logo(size: Vector2, short: float) -> void:
	var words: PackedStringArray = TITLE_TEXT.split(" ")
	var portrait: bool = size.y > size.x
	var font_size: int = int(clampf(minf(size.x * (0.16 if portrait else 0.075), short * 0.2), 18.0, 400.0))
	var pulse: float = 0.5 + 0.5 * sin(_time * TAU / PULSE_SECONDS)
	var lines: PackedStringArray = words if portrait else PackedStringArray([TITLE_TEXT])
	var line_height: float = font_size * 1.05
	var top: float = size.y * (0.22 if portrait else 0.28) - line_height * (lines.size() - 1) * 0.5
	for index: int in lines.size():
		var width: float = _font.get_string_size(lines[index], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var origin: Vector2 = Vector2((size.x - width) * 0.5, top + index * line_height)
		var depth: float = maxf(2.0, font_size * 0.07)
		for ring: int in 3:
			_canvas.draw_string_outline(_font, origin, lines[index], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, int(font_size * (0.1 + ring * 0.05)), Color(LANTERN, (0.06 + 0.05 * pulse) / (ring + 1)))
		for step: int in range(4, 0, -1):
			_canvas.draw_string(_font, origin + Vector2(0.0, depth * step * 0.5), lines[index], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("5a2b14"))
		_canvas.draw_string_outline(_font, origin, lines[index], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, maxi(2, int(font_size * 0.08)), Color("2a1308"))
		_canvas.draw_string(_font, origin, lines[index], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, CREAM.lerp(LANTERN, 0.25 * pulse))
