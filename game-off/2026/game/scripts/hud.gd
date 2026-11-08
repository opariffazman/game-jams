class_name Hud
extends CanvasLayer
## Top HUD (floor, hearts, swaps, tips, boss bar), the fail text, the door screen, the run end screen, the boss cards, and the Locker. Draws shapes so no state hangs on color alone.

## Door buttons, left then right, in the bottom 40 percent of the screen.
const DOOR_RECTS: Array[Rect2] = [Rect2(25, 600, 235, 280), Rect2(280, 600, 235, 280)]
## Slots shown in the heart row. More appear when the hero holds extra hearts.
const MIN_HEART_SLOTS: int = 3
## Width of one heart slot in pixels.
const HEART_SLOT: float = 38.0
## Heart half-size in pixels.
const HEART_SIZE: float = 18.0
## Door words, indexed by [enum RunState.Door].
const DOOR_WORDS: Array[String] = ["HEART", "MONEY", "ELITE", "BOON"]
## Door detail lines, indexed by [enum RunState.Door].
const DOOR_DETAILS: Array[String] = ["+1 heart", "+10 money", "Harder room\n+25 money", "Pick 1 of 3\nperks"]
## Boon cards, top to bottom, in the bottom 40 percent of the screen.
const CARD_RECTS: Array[Rect2] = [Rect2(25, 590, 490, 104), Rect2(25, 704, 490, 104), Rect2(25, 818, 490, 104)]
## Size of one boon icon in the top row.
const ICON_SIZE: float = 42.0
## End screen buttons, in the bottom 40 percent of the screen. Each is at least 72 px tall.
const END_RECTS: Array[Rect2] = [Rect2(40, 596, 460, 72), Rect2(40, 680, 460, 72)]
## Seconds the COPIED label stays.
const COPIED_S: float = 1.0
## Buttons of the end screen. The index in [constant END_RECTS] is the value minus one.
enum EndButton { NONE, WATCH, COPY }

## The Locker screen. It sits above every other HUD element.
var locker: LockerView

var _shapes: Control
var _floor_label: Label
var _tips_label: Label
var _swaps_label: Label
var _status: Label
var _hint: Label
var _title: Label
var _body: Label
var _prompt: Label
var _hearts: int = RunState.START_HEARTS
var _offers: Array[int] = []
var _door_words: Array[Label] = []
var _door_details: Array[Label] = []
var _door_keys: Array[Label] = []
var _end_showing: bool = false
var _banner: Label
var _owned: Array[int] = []
var _coat_spent: bool = false
var _card_boons: Array[int] = []
var _card_names: Array[Label] = []
var _card_effects: Array[Label] = []
var _card_keys: Array[Label] = []
var _icon_labels: Array[Label] = []
var _boss_phase: int = 0
var _boss_label: Label
var _card_title: Label
var _card_sub: Label
var _card_on: bool = false
var _end_buttons: Array[Label] = []
var _can_watch: bool = false
var _copy_token: int = 0
var _link_box: LineEdit


func _init() -> void:
	_shapes = Control.new()
	_shapes.size = Vector2(540, 960)
	_shapes.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shapes.draw.connect(_draw_shapes)
	add_child(_shapes)
	_floor_label = _make_label(Rect2(16, 8, 250, 46), 34, HORIZONTAL_ALIGNMENT_LEFT)
	_tips_label = _make_label(Rect2(274, 8, 250, 46), 34, HORIZONTAL_ALIGNMENT_RIGHT)
	_swaps_label = _make_label(Rect2(274, 58, 250, 46), 34, HORIZONTAL_ALIGNMENT_RIGHT)
	_banner = _make_label(Rect2(0, 160, 540, 44), 30, HORIZONTAL_ALIGNMENT_CENTER)
	_status = _make_label(Rect2(0, 200, 540, 110), 40, HORIZONTAL_ALIGNMENT_CENTER)
	_hint = _make_label(Rect2(0, 250, 540, 70), 22, HORIZONTAL_ALIGNMENT_CENTER)
	_hint.text = "Tap a gunman to shift places with him.\nHis friends shoot where you stood."
	_title = _make_label(Rect2(0, 180, 540, 90), 56, HORIZONTAL_ALIGNMENT_CENTER)
	_body = _make_label(Rect2(0, 300, 540, 280), 34, HORIZONTAL_ALIGNMENT_CENTER)
	_prompt = _make_label(Rect2(0, 830, 540, 60), 32, HORIZONTAL_ALIGNMENT_CENTER)
	for i: int in END_RECTS.size():
		var button: Label = _make_label(Rect2(END_RECTS[i].position.x, END_RECTS[i].position.y + 16, END_RECTS[i].size.x, 44), 32, HORIZONTAL_ALIGNMENT_CENTER)
		button.text = ["WATCH BEST CHAIN", "COPY LINK"][i]
		_end_buttons.append(button)
	for i: int in DOOR_RECTS.size():
		var rect: Rect2 = DOOR_RECTS[i]
		_door_keys.append(_make_label(Rect2(rect.position.x + 12, rect.position.y + 6, 60, 40), 30, HORIZONTAL_ALIGNMENT_LEFT))
		_door_words.append(_make_label(Rect2(rect.position.x, rect.position.y + 140, rect.size.x, 50), 42, HORIZONTAL_ALIGNMENT_CENTER))
		_door_details.append(_make_label(Rect2(rect.position.x, rect.position.y + 192, rect.size.x, 70), 24, HORIZONTAL_ALIGNMENT_CENTER))
	for i: int in BoonSet.COUNT:
		var rect: Rect2 = CARD_RECTS[i]
		_card_keys.append(_make_label(Rect2(rect.position.x + 10, rect.position.y + 4, 40, 34), 24, HORIZONTAL_ALIGNMENT_LEFT))
		_card_names.append(_make_label(Rect2(rect.position.x + 120, rect.position.y + 10, 360, 44), 32, HORIZONTAL_ALIGNMENT_LEFT))
		_card_effects.append(_make_label(Rect2(rect.position.x + 120, rect.position.y + 56, 360, 36), 24, HORIZONTAL_ALIGNMENT_LEFT))
		var icon: Label = _make_label(Rect2(16 + i * (ICON_SIZE + 8), 108, ICON_SIZE, ICON_SIZE), 26, HORIZONTAL_ALIGNMENT_CENTER)
		icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_icon_labels.append(icon)
	_boss_label = _make_label(Rect2(186, 108, 210, 42), 26, HORIZONTAL_ALIGNMENT_LEFT)
	_boss_label.text = "THE MANAGER"
	_boss_label.add_theme_color_override("font_color", Palette.MAGENTA)
	_boss_label.visible = false
	_card_title = _make_label(Rect2(0, 356, 540, 84), 66, HORIZONTAL_ALIGNMENT_CENTER)
	_card_sub = _make_label(Rect2(0, 448, 540, 44), 28, HORIZONTAL_ALIGNMENT_CENTER)
	hide_card()
	hide_doors()
	hide_boons()
	hide_end()
	locker = LockerView.new()
	add_child(locker)


## Shows the boss bar with [param phase] 1 to 3 fought now: one filled pip per phase left. Phase 0 hides the bar.
func set_boss(phase: int) -> void:
	_boss_phase = phase
	_boss_label.visible = phase > 0
	_shapes.queue_redraw()


## Returns the pips still filled in the boss bar, or -1 when the bar is hidden.
func boss_pips() -> int:
	return RunState.BOSS_PHASES - _boss_phase + 1 if _boss_phase > 0 else -1


## Returns the title of the centered card, or an empty string when it is hidden.
func card_title() -> String:
	return _card_title.text if _card_on else ""


## Shows a centered card with [param title] in [param color] and a smaller [param sub] line.
func show_card(title: String, sub: String, color: Color) -> void:
	_hint.visible = false
	_card_on = true
	_card_title.text = title
	_card_title.add_theme_color_override("font_color", color)
	_card_sub.text = sub
	_card_title.visible = true
	_card_sub.visible = true
	_shapes.queue_redraw()


## Hides the centered card.
func hide_card() -> void:
	_card_on = false
	_card_title.visible = false
	_card_sub.visible = false
	_shapes.queue_redraw()


## Updates the top rows.
func update_run(level: int, room_in_floor: int, hearts: int, swaps: int, budget: int, tips: int) -> void:
	_floor_label.text = "F%d  %d/%d" % [level, room_in_floor, RunState.ROOMS_PER_FLOOR]
	_swaps_label.text = "SHIFTS %d / %d" % [swaps, budget]
	_tips_label.text = "MONEY %d" % tips
	_hearts = hearts
	_shapes.queue_redraw()


## Shows the owned boons as icons in the top row. [param coat_spent] crosses out the coat for this room.
func set_boons(owned: Array[int], coat_spent: bool) -> void:
	_owned = owned
	_coat_spent = coat_spent
	for i: int in _icon_labels.size():
		_icon_labels[i].visible = i < owned.size()
		if i < owned.size():
			_icon_labels[i].text = BoonSet.INITIALS[owned[i]]
			_icon_labels[i].modulate.a = 0.45 if coat_spent and owned[i] == BoonSet.Boon.COAT else 1.0
	_shapes.queue_redraw()


## Shows the one-line event banner of the planned turn. An empty string hides it.
func show_banner(text: String) -> void:
	_banner.text = text


## Shows the boon screen with a card for each of [param offers], each a [enum BoonSet.Boon] value.
func show_boons(offers: Array[int]) -> void:
	_card_boons = offers
	_hint.visible = false
	_title.text = "CHOOSE A BOON"
	_title.visible = true
	_body.text = "Boons last until the night is over."
	_body.visible = true
	for i: int in BoonSet.COUNT:
		var shown: bool = i < offers.size()
		for label: Label in [_card_keys[i], _card_names[i], _card_effects[i]]:
			label.visible = shown
		if shown:
			_card_keys[i].text = str(i + 1)
			_card_names[i].text = BoonSet.NAMES[offers[i]]
			_card_effects[i].text = BoonSet.EFFECTS[offers[i]]
	_shapes.queue_redraw()


## Hides the boon screen.
func hide_boons() -> void:
	_card_boons = []
	for i: int in BoonSet.COUNT:
		for label: Label in [_card_keys[i], _card_names[i], _card_effects[i]]:
			label.visible = false
	if not _end_showing:
		_body.visible = false
		_title.visible = false
	_shapes.queue_redraw()


## Returns the card index under [param screen_pos], or -1.
func boon_at(screen_pos: Vector2) -> int:
	for i: int in _card_boons.size():
		if CARD_RECTS[i].has_point(screen_pos):
			return i
	return -1


## Shows [param text] in the status area. An empty string hides it.
func show_status(text: String) -> void:
	_status.text = text


## Hides the first-input hint.
func hide_hint() -> void:
	_hint.visible = false


## Shows the door screen with the two [param offers], each a [enum RunState.Door] value.
func show_doors(offers: Array[int]) -> void:
	_offers = offers
	_hint.visible = false
	_title.text = "ROOM CLEAR"
	_title.visible = true
	_prompt.text = ""
	for i: int in DOOR_RECTS.size():
		_door_words[i].text = DOOR_WORDS[offers[i]]
		_door_details[i].text = DOOR_DETAILS[offers[i]]
		_door_keys[i].text = str(i + 1)
		for label: Label in [_door_words[i], _door_details[i], _door_keys[i]]:
			label.visible = true
	_shapes.queue_redraw()


## Hides the door screen.
func hide_doors() -> void:
	_offers = []
	_title.visible = false
	for i: int in DOOR_RECTS.size():
		for label: Label in [_door_words[i], _door_details[i], _door_keys[i]]:
			label.visible = false
	_shapes.queue_redraw()


## Returns the door under [param screen_pos], or -1.
func door_at(screen_pos: Vector2) -> int:
	if _offers.is_empty():
		return -1
	for i: int in DOOR_RECTS.size():
		if DOOR_RECTS[i].has_point(screen_pos):
			return i
	return -1


## Shows the end screen with [param title], the run numbers, the tower [param code], and the buttons. WATCH BEST CHAIN shows when [param can_watch].
func show_end(title: String, level: int, cleared: int, tips: int, tips_total: int, code: String, can_watch: bool) -> void:
	_end_showing = true
	_can_watch = can_watch
	_hint.visible = false
	hide_boons()
	hide_doors()
	_status.text = ""
	_title.text = title
	_title.visible = true
	_body.text = "Floor reached  F%d\nRooms cleared  %d / %d\nMoney earned  %d\nMoney total  %d\nTower  %s" % [level, cleared, RunState.ROOM_COUNT, tips, tips_total, code]
	_body.visible = true
	_end_buttons[0].visible = can_watch
	_end_buttons[1].visible = true
	_end_buttons[1].text = "COPY LINK"
	set_end_ready(false)
	_shapes.queue_redraw()


## Returns the end screen button under [param screen_pos], or [constant EndButton.NONE].
func end_button_at(screen_pos: Vector2) -> EndButton:
	if not _end_showing:
		return EndButton.NONE
	if _can_watch and END_RECTS[0].has_point(screen_pos):
		return EndButton.WATCH
	if END_RECTS[1].has_point(screen_pos):
		return EndButton.COPY
	return EndButton.NONE


## Shows COPIED on the copy button for a second. When [param copied] is false, shows [param link] as selectable text instead.
func show_copy_result(copied: bool, link: String) -> void:
	_copy_token += 1
	if copied:
		_end_buttons[1].text = "COPIED"
		var token: int = _copy_token
		await get_tree().create_timer(COPIED_S, true, false, true).timeout
		if token == _copy_token and _end_showing:
			_end_buttons[1].text = "COPY LINK"
		return
	_end_buttons[1].text = "COPY LINK"
	if _link_box == null:
		_link_box = LineEdit.new()
		_link_box.editable = false
		_link_box.selecting_enabled = true
		_link_box.alignment = HORIZONTAL_ALIGNMENT_CENTER
		_link_box.position = Vector2(40, 764)
		_link_box.size = Vector2(460, 56)
		_link_box.add_theme_font_size_override("font_size", 24)
		add_child(_link_box)
	_link_box.text = link
	_link_box.visible = true
	_link_box.grab_focus()
	_link_box.select_all()


## Returns the text of the selectable link box, or an empty string while it is hidden.
func link_text() -> String:
	return _link_box.text if _link_box != null and _link_box.visible else ""


## Returns the text on the copy button.
func copy_button_text() -> String:
	return _end_buttons[1].text


## Hides the end screen.
func hide_end() -> void:
	_end_showing = false
	_copy_token += 1
	for button: Label in _end_buttons:
		button.visible = false
	if _link_box != null:
		_link_box.release_focus()
		_link_box.visible = false
	_body.visible = false
	_prompt.text = ""
	_title.visible = false


## Returns the end screen title, or an empty string when it is hidden.
func end_title() -> String:
	return _title.text if _end_showing else ""


## Shows or hides the new-tower prompt. It shows once taps can start a new tower.
func set_end_ready(ready: bool) -> void:
	_prompt.text = "TAP FOR THE LOCKER" if ready else ""


## Returns the heart outline for a heart of half-size [param size] centered on [param center].
static func heart_points(center: Vector2, size: float) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	for i: int in 28:
		var t: float = TAU * i / 28.0
		var x: float = 16.0 * pow(sin(t), 3.0)
		var y: float = 13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t)
		points.append(center + Vector2(x, -y) * size / 16.0)
	return points


func _draw_shapes() -> void:
	var slots: int = maxi(MIN_HEART_SLOTS, _hearts)
	for i: int in slots:
		var points: PackedVector2Array = heart_points(Vector2(34 + i * HEART_SLOT, 82), HEART_SIZE)
		if i < _hearts:
			_shapes.draw_colored_polygon(points, Palette.MAGENTA)
		else:
			points.append(points[0])
			_shapes.draw_polyline(points, Palette.MAGENTA, 2.5, true)
	if _end_showing:
		_shapes.draw_rect(Rect2(40, 170, 460, 400), Color(Palette.PANEL, 0.9))
		_shapes.draw_rect(Rect2(40, 170, 460, 400), Color(Palette.INK, 0.5), false, 2.0)
		for i: int in END_RECTS.size():
			if i == 1 or _can_watch:
				_shapes.draw_rect(END_RECTS[i], Palette.PANEL)
				_shapes.draw_rect(END_RECTS[i], Palette.AMBER if i == 0 else Palette.CYAN, false, 4.0)
	if _card_on:
		_shapes.draw_rect(Rect2(30, 340, 480, 170), Color(Palette.PANEL, 0.88))
		_shapes.draw_rect(Rect2(30, 340, 480, 170), Palette.MAGENTA, false, 4.0)
	for pip: int in (RunState.BOSS_PHASES if _boss_phase > 0 else 0):
		var center: Vector2 = Vector2(420 + pip * 38, 129)
		if pip < RunState.BOSS_PHASES - _boss_phase + 1:
			_shapes.draw_circle(center, 13.0, Palette.MAGENTA)
		else:
			_shapes.draw_arc(center, 11.0, 0.0, TAU, 24, Palette.MAGENTA, 3.0, true)
	for i: int in _offers.size():
		_draw_door(i, _offers[i])
	for i: int in _owned.size():
		_draw_icon_frame(i)
	for i: int in _card_boons.size():
		_draw_card(i, _card_boons[i])


func _draw_door(index: int, door: int) -> void:
	var rect: Rect2 = DOOR_RECTS[index]
	var accent: Color = [Palette.MAGENTA, Palette.AMBER, Palette.CYAN, Palette.INK][door]
	_shapes.draw_rect(rect, Palette.PANEL)
	_shapes.draw_rect(rect, accent, false, 4.0)
	var center: Vector2 = Vector2(rect.get_center().x, rect.position.y + 85)
	match door:
		RunState.Door.HEART:
			_shapes.draw_colored_polygon(heart_points(center, 44.0), accent)
		RunState.Door.TIPS:
			_shapes.draw_circle(center, 40.0, accent)
			_shapes.draw_circle(center, 26.0, Palette.PANEL)
			_shapes.draw_circle(center, 12.0, accent)
		RunState.Door.BOON:
			var diamond: PackedVector2Array = PackedVector2Array([center + Vector2(0, -46), center + Vector2(40, 0), center + Vector2(0, 46), center + Vector2(-40, 0)])
			_shapes.draw_colored_polygon(diamond, accent)
			_shapes.draw_rect(Rect2(center - Vector2(5, 20), Vector2(10, 40)), Palette.PANEL)
			_shapes.draw_rect(Rect2(center - Vector2(20, 5), Vector2(40, 10)), Palette.PANEL)
		_:
			var star: PackedVector2Array = PackedVector2Array()
			for i: int in 10:
				var radius: float = 46.0 if i % 2 == 0 else 20.0
				star.append(center + Vector2.from_angle(TAU * i / 10.0 - PI / 2.0) * radius)
			_shapes.draw_colored_polygon(star, accent)


func _draw_icon_frame(slot: int) -> void:
	var rect: Rect2 = Rect2(16 + slot * (ICON_SIZE + 8), 108, ICON_SIZE, ICON_SIZE)
	_shapes.draw_rect(rect, Palette.PANEL)
	_shapes.draw_rect(rect, Palette.AMBER, false, 3.0)
	if _coat_spent and _owned[slot] == BoonSet.Boon.COAT:
		_shapes.draw_line(rect.position, rect.end, Palette.MAGENTA, 4.0)


func _draw_card(slot: int, boon: int) -> void:
	var rect: Rect2 = CARD_RECTS[slot]
	_shapes.draw_rect(rect, Palette.PANEL)
	_shapes.draw_rect(rect, Palette.AMBER, false, 4.0)
	var center: Vector2 = Vector2(rect.position.x + 72, rect.get_center().y + 4)
	match boon:
		BoonSet.Boon.QUICK_DRAW:
			for offset: float in [-14.0, 10.0]:
				_shapes.draw_polyline(PackedVector2Array([center + Vector2(offset - 8, -26), center + Vector2(offset + 12, 0), center + Vector2(offset - 8, 26)]), Palette.AMBER, 9.0, true)
		BoonSet.Boon.SPARE_CLIP:
			_shapes.draw_rect(Rect2(center - Vector2(18, 30), Vector2(36, 60)), Palette.AMBER, false, 6.0)
			for row: int in 3:
				_shapes.draw_rect(Rect2(center + Vector2(-9, -20 + row * 16), Vector2(18, 8)), Palette.AMBER)
		_:
			_shapes.draw_colored_polygon(PackedVector2Array([center + Vector2(-12, -30), center + Vector2(12, -30), center + Vector2(36, -12), center + Vector2(36, 8), center + Vector2(20, 8), center + Vector2(20, 30), center + Vector2(-20, 30), center + Vector2(-20, 8), center + Vector2(-36, 8), center + Vector2(-36, -12)]), Palette.AMBER)
			_shapes.draw_line(center + Vector2(0, -24), center + Vector2(0, 28), Palette.PANEL, 4.0)


func _make_label(rect: Rect2, font_size: int, align: HorizontalAlignment) -> Label:
	var label: Label = Label.new()
	label.position = rect.position
	label.size = rect.size
	label.horizontal_alignment = align
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Palette.INK)
	label.add_theme_color_override("font_outline_color", Palette.PANEL)
	label.add_theme_constant_override("outline_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label
