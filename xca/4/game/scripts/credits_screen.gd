class_name CreditsScreen
extends Control
## A full-screen list of who made what. It sits above every other screen and closes with one button.
##
## Names only, no links, because GamePix does not allow URLs in a game.

const LINES: Array[Array] = [
	["3D models", "Quaternius, Zombie Apocalypse Kit and Survival Pack (CC0)"],
	["Characters", "Quaternius, Zombie Apocalypse Kit (CC0)"],
	["Music", "Suno"],
	["Hand tracking", "MediaPipe, Google"],
	["Font", "Atkinson Hyperlegible Next, Braille Institute (SIL Open Font License 1.1)"],
	["Icons", "Kenney (CC0)"],
	["Icons", "Lorc, Delapouite, John Colburn, Sbed, game-icons.net (CC BY 3.0)"],
]
const TITLE_SIZE: int = 44
const HEADING_SIZE: int = 22
const BODY_SIZE: int = 22
const CLOSE_SIZE: Vector2 = Vector2(180.0, 64.0)
const CREAM: Color = Color(1.0, 0.95, 0.85)
const SCRIM: Color = Color(0.03, 0.01, 0.07, 0.94)


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var scrim := ColorRect.new()
	scrim.color = SCRIM
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 24.0
	column.offset_right = -24.0
	column.offset_top = 20.0
	column.offset_bottom = -20.0
	column.add_theme_constant_override("separation", 14)
	add_child(column)
	column.add_child(_label("Credits", TITLE_SIZE, UiKit.ORANGE, HORIZONTAL_ALIGNMENT_CENTER))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)
	for line: Array in LINES:
		list.add_child(_entry(String(line[0]), String(line[1])))
	var close := Button.new()
	close.theme = UiKit.theme()
	close.text = "Back"
	close.custom_minimum_size = CLOSE_SIZE
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(close_screen)
	UiKit.primary(close)
	column.add_child(close)


func open_screen() -> void:
	visible = true
	get_parent().move_child(self, -1)


func close_screen() -> void:
	visible = false


## One panel with a small heading over the names, so a reader finds a role first.
func _entry(heading: String, body: String) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiKit.brush(UiKit.PANEL, UiKit.ORANGE, 14.0, 7, false))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	panel.add_child(box)
	box.add_child(_label(heading, HEADING_SIZE, UiKit.GOLD, HORIZONTAL_ALIGNMENT_LEFT))
	var text: Label = _label(body, BODY_SIZE, CREAM, HORIZONTAL_ALIGNMENT_LEFT)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(text)
	return panel


func _label(text: String, font_size: int, colour: Color, align: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = align
	label.add_theme_font_override("font", UiKit.font())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colour)
	return label
