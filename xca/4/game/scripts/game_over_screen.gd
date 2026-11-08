class_name GameOverScreen
extends Control
## The end of a run. The street dims, the headline fades in, then a run statistics panel and the local top 5 board.
##
## The run is endless, so there is no win screen. The buttons wait for a beat so a panicked tap during the last hit never skips the screen.

signal retry_requested
signal camp_requested

## Seconds before a button accepts input.
const INPUT_DELAY: float = 1.2
const FADE_SECONDS: float = 0.9
## Dark enough that orange and cream text keep 4.5:1 over the brightest street light.
const SCRIM: Color = Color(0.03, 0.01, 0.07, 0.78)
const CREAM: Color = Color(1.0, 0.95, 0.85)
const ORANGE: Color = Color(1.0, 0.64, 0.24)
const EXTRUSION: Color = Color(0.72, 0.3, 0.05)
const MUTED: Color = Color(0.82, 0.78, 0.88)
const BUTTON_SIZE: Vector2 = Vector2(260.0, 72.0)
const BODY_SIZE: int = 24
const TITLE_SIZE: int = 28
const DEPTH_STEPS: int = 8
const PULSE_SECONDS: float = 1.6
const PLACEHOLDER: String = "---"
const NEW_TAG: String = "New"
const STAT_LABELS: Array[String] = ["Distance", "Zombies downed", "Shots fired", "Pickups", "Best combo", "Time survived"]

## Zero-based board row of this run, or -1 when it missed the board.
var rank: int = -1
var metres: int = 0

var _age: float = 0.0
var _fitted_for: Vector2 = Vector2.ZERO
var _scrim: ColorRect
var _content: Control
var _headline: _Headline
var _panels: BoxContainer
var _caption: Label
var _board_cells: Array[Array] = []
var _stat_values: Array[Label] = []
var _body_labels: Array[Label] = []
var _title_labels: Array[Label] = []
var _retry_button: Button
var _camp_button: Button
var _flourish: Label


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_scrim = ColorRect.new()
	_scrim.color = Color(SCRIM, 0.0)
	_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_scrim)
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 14)
	_content.modulate.a = 0.0
	centre.add_child(_content)
	_headline = _Headline.new()
	_content.add_child(_headline)
	_caption = _label("", MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_content.add_child(_caption)
	_panels = BoxContainer.new()
	_panels.alignment = BoxContainer.ALIGNMENT_CENTER
	_panels.add_theme_constant_override("separation", 18)
	_content.add_child(_panels)
	_panels.add_child(_build_board())
	_panels.add_child(_build_stats())
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 20)
	_retry_button = _button("Try again", true, _on_retry)
	_camp_button = _button("Camp", false, _on_camp)
	buttons.add_child(_retry_button)
	buttons.add_child(_camp_button)
	_content.add_child(buttons)


func _process(delta: float) -> void:
	if not visible:
		return
	_age += delta
	var fade: float = clampf(_age / FADE_SECONDS, 0.0, 1.0)
	_scrim.color = Color(SCRIM, SCRIM.a * fade)
	_content.modulate.a = clampf((_age - 0.25) / FADE_SECONDS, 0.0, 1.0)
	if _flourish != null and _flourish.visible:
		_flourish.modulate.a = 0.65 + 0.35 * sin(_age * TAU / PULSE_SECONDS)
	var screen: Vector2 = get_viewport_rect().size
	if screen != _fitted_for:
		_fit(screen)


## Shows the run. stats holds hero, weapon, metres, zombies, shots, hits, pickups, combo and seconds.
## The run is saved to the board first, so the board already lists it.
func show_result(stats: Dictionary) -> void:
	metres = int(stats.get("metres", 0))
	var hero: String = String(stats.get("hero", ""))
	rank = HighScores.insert(hero, metres) if metres > 0 else -1
	_caption.text = "%s with the %s" % [hero, String(stats.get("weapon", "pistol")).to_lower()]
	_fill_board()
	_fill_stats(stats)
	_age = 0.0
	_scrim.color = Color(SCRIM, 0.0)
	_content.modulate.a = 0.0
	visible = true
	get_parent().move_child(self, -1)
	_fit(get_viewport_rect().size)


func hide_screen() -> void:
	visible = false


## True once the beat has passed and a press counts.
func accepts_input() -> bool:
	return visible and _age >= INPUT_DELAY


## Presses Try again. The hand palm and the Enter key use it, like the button.
func confirm() -> void:
	_on_retry()


## What the screen shows, so the browser test reads text and the highlighted row without pixel scraping.
func report() -> Dictionary:
	var rows: Array[String] = []
	for cells: Array in _board_cells:
		var parts: Array[String] = []
		for cell: Label in cells:
			parts.append(cell.text)
		rows.append(" ".join(parts).strip_edges())
	var stats: Array[String] = []
	for index: int in _stat_values.size():
		stats.append("%s: %s" % [STAT_LABELS[index], _stat_values[index].text])
	return {"visible": visible, "ready": accepts_input(), "metres": metres, "rank": rank, "board": rows, "stats": stats, "caption": _caption.text}


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey or not event.pressed or event.echo:
		return
	var key: Key = (event as InputEventKey).physical_keycode
	if key == KEY_ENTER or key == KEY_KP_ENTER:
		get_viewport().set_input_as_handled()
		_on_retry()


func _on_retry() -> void:
	if accepts_input():
		retry_requested.emit()


func _on_camp() -> void:
	if accepts_input():
		camp_requested.emit()


func _build_board() -> Control:
	var panel := _panel()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var title := _label("Best runs", ORANGE, HORIZONTAL_ALIGNMENT_LEFT)
	_title_labels.append(title)
	box.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 6)
	box.add_child(grid)
	for row: int in HighScores.CAPACITY:
		var cells: Array[Label] = []
		for column: int in 5:
			var cell := _label("", CREAM, HORIZONTAL_ALIGNMENT_RIGHT if column == 2 else HORIZONTAL_ALIGNMENT_LEFT)
			grid.add_child(cell)
			cells.append(cell)
		_board_cells.append(cells)
	_flourish = _board_cells[0][4]
	return panel


func _build_stats() -> Control:
	var panel := _panel()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var title := _label("This run", ORANGE, HORIZONTAL_ALIGNMENT_LEFT)
	_title_labels.append(title)
	box.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 6)
	box.add_child(grid)
	for word: String in STAT_LABELS:
		grid.add_child(_label(word, MUTED, HORIZONTAL_ALIGNMENT_LEFT))
		var value := _label("", CREAM, HORIZONTAL_ALIGNMENT_RIGHT)
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(value)
		_stat_values.append(value)
	return panel


func _fill_board() -> void:
	var rows: Array[Dictionary] = HighScores.load_rows()
	for index: int in HighScores.CAPACITY:
		var cells: Array = _board_cells[index]
		var highlighted: bool = index == rank
		if index < rows.size():
			var row: Dictionary = rows[index]
			cells[0].text = "%d" % (index + 1)
			cells[1].text = String(row["hero"])
			cells[2].text = "%d m" % int(row["metres"])
			cells[3].text = HighScores.day_label(int(row["day"]))
		else:
			cells[0].text = "%d" % (index + 1)
			cells[1].text = PLACEHOLDER
			cells[2].text = PLACEHOLDER
			cells[3].text = PLACEHOLDER
		cells[4].text = NEW_TAG if highlighted else ""
		var colour: Color = ORANGE if highlighted else (CREAM if index < rows.size() else MUTED)
		for cell: Label in cells:
			cell.add_theme_color_override("font_color", colour)


func _fill_stats(stats: Dictionary) -> void:
	var shots: int = int(stats.get("shots", 0))
	var hits: int = int(stats.get("hits", 0))
	var shots_text: String = "%d (%d%% hit)" % [shots, roundi(100.0 * hits / shots)] if shots > 0 else "0"
	var seconds: int = int(stats.get("seconds", 0))
	var values: Array[String] = [
		"%d m" % metres,
		"%d" % int(stats.get("zombies", 0)),
		shots_text,
		"%d" % int(stats.get("pickups", 0)),
		"%d" % int(stats.get("combo", 0)),
		"%d:%02d" % [seconds / 60, seconds % 60],
	]
	for index: int in values.size():
		_stat_values[index].text = values[index]


## Stacks the panels on a portrait screen and sizes text and buttons from the screen, so a phone keeps everything on screen.
func _fit(screen: Vector2) -> void:
	_fitted_for = screen
	var portrait: bool = screen.y > screen.x
	var scale: float = UiKit.scale_for(screen)
	_panels.vertical = portrait
	_headline.big_size = int(clampf(screen.x * (0.17 if portrait else 0.08), 48.0, 110.0) * scale)
	var body: int = int((23.0 if portrait else BODY_SIZE) * scale)
	var title: int = int((26.0 if portrait else TITLE_SIZE) * scale)
	for label: Label in _body_labels:
		label.add_theme_font_size_override("font_size", body)
	for label: Label in _title_labels:
		label.add_theme_font_size_override("font_size", title)
	_caption.add_theme_font_size_override("font_size", body)
	var button_size: Vector2 = BUTTON_SIZE * scale
	if portrait:
		button_size.x = minf(button_size.x, (screen.x - 60.0) * 0.5)
	for button: Button in [_retry_button, _camp_button]:
		button.custom_minimum_size = button_size.max(Vector2(UiKit.MIN_TARGET, UiKit.MIN_TARGET))


func _panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiKit.brush(UiKit.PANEL, UiKit.ORANGE, 18.0, 11, true))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return panel


func _label(text: String, colour: Color, align: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = align
	label.add_theme_font_override("font", UiKit.font())
	label.add_theme_font_size_override("font_size", BODY_SIZE)
	label.add_theme_color_override("font_color", colour)
	_body_labels.append(label)
	return label


func _button(word: String, primary: bool, action: Callable) -> Button:
	var button := Button.new()
	button.theme = UiKit.theme()
	button.text = word
	button.custom_minimum_size = BUTTON_SIZE
	button.pressed.connect(action)
	if primary:
		UiKit.primary(button)
	return button


## "You didn't" small and cream over "get home" large and orange, with the stacked extrusion of the title logo and no outline.
class _Headline extends Control:
	const SMALL_RATIO: float = 0.46

	var big_size: int = 100:
		set(value):
			if value == big_size and custom_minimum_size.x > 0.0:
				return
			big_size = value
			custom_minimum_size = Vector2(big_size * 4.6, big_size * (1.0 + SMALL_RATIO) * 1.12)
			queue_redraw()


	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		big_size = big_size


	func _draw() -> void:
		var small_size: int = int(big_size * SMALL_RATIO)
		var small_y: float = small_size * 0.95
		_word("You didn't", small_size, small_y, CREAM)
		_word("get home", big_size, small_y + big_size * 0.95, ORANGE)


	func _word(text: String, font_size: int, baseline: float, face: Color) -> void:
		var font: FontVariation = UiKit.font()
		var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var origin := Vector2(size.x * 0.5 - width * 0.5, baseline)
		var step: float = font_size * 0.014
		for depth: int in range(DEPTH_STEPS, 0, -1):
			var shade: float = float(depth) / DEPTH_STEPS
			var layer: Color = EXTRUSION.lerp(Color(0.12, 0.04, 0.16), shade * 0.7)
			draw_string(font, origin + Vector2(depth * step * 0.5, depth * step), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, layer)
		draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, face)
