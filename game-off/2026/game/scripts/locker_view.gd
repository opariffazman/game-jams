class_name LockerView
extends Control
## The Locker screen: tips balance, one card per upgrade, and a big CLOCK IN button. Draws and hit-tests only, the purchase rules live in [Upgrades].

## Card rectangles, top to bottom. Each is at least 72 px tall.
const CARD_RECTS: Array[Rect2] = [Rect2(25, 150, 490, 76), Rect2(25, 234, 490, 76), Rect2(25, 318, 490, 76), Rect2(25, 402, 490, 76), Rect2(25, 486, 490, 76), Rect2(25, 570, 490, 76)]
## The CLOCK IN button, the largest control on the screen.
const CLOCK_RECT: Rect2 = Rect2(25, 704, 490, 200)

var _save: Dictionary = {}
var _tips: Label
var _note: Label
var _keys: Array[Label] = []
var _names: Array[Label] = []
var _effects: Array[Label] = []
var _states: Array[Label] = []
var _seed_label: Label
var _clock_word: Label
var _clock_key: Label


func _init() -> void:
	size = Vector2(540, 960)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_label(Rect2(0, 18, 540, 64), 52, HORIZONTAL_ALIGNMENT_CENTER).text = "LOCKER"
	_tips = _label(Rect2(0, 86, 540, 52), 40, HORIZONTAL_ALIGNMENT_CENTER)
	_tips.add_theme_color_override("font_color", Palette.AMBER)
	_note = _label(Rect2(0, 652, 540, 40), 24, HORIZONTAL_ALIGNMENT_CENTER)
	for i: int in Upgrades.COUNT:
		var rect: Rect2 = CARD_RECTS[i]
		_keys.append(_label(Rect2(rect.position.x + 12, rect.position.y + 20, 36, 40), 28, HORIZONTAL_ALIGNMENT_CENTER))
		_names.append(_label(Rect2(rect.position.x + 62, rect.position.y + 4, 290, 40), 30, HORIZONTAL_ALIGNMENT_LEFT))
		_effects.append(_label(Rect2(rect.position.x + 62, rect.position.y + 42, 290, 30), 22, HORIZONTAL_ALIGNMENT_LEFT))
		_states.append(_label(Rect2(rect.position.x + 330, rect.position.y + 20, 150, 40), 26, HORIZONTAL_ALIGNMENT_RIGHT))
		_keys[i].text = str(i + 1)
		_names[i].text = Upgrades.NAMES[i]
		_effects[i].text = Upgrades.EFFECTS[i]
	_seed_label = _label(Rect2(0, 912, 540, 40), 26, HORIZONTAL_ALIGNMENT_CENTER)
	_seed_label.add_theme_color_override("font_color", Palette.CYAN)
	_clock_word = _label(Rect2(CLOCK_RECT.position.x, CLOCK_RECT.position.y + 40, CLOCK_RECT.size.x, 90), 76, HORIZONTAL_ALIGNMENT_CENTER)
	_clock_word.text = "CLOCK IN"
	_clock_word.add_theme_color_override("font_color", Palette.PANEL)
	_clock_word.add_theme_constant_override("outline_size", 0)
	_clock_key = _label(Rect2(CLOCK_RECT.position.x, CLOCK_RECT.position.y + 138, CLOCK_RECT.size.x, 40), 26, HORIZONTAL_ALIGNMENT_CENTER)
	_clock_key.text = "TAP OR PRESS ENTER"
	_clock_key.add_theme_color_override("font_color", Palette.PANEL)
	_clock_key.add_theme_constant_override("outline_size", 0)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("08080c"))
	for i: int in Upgrades.COUNT:
		var rect: Rect2 = CARD_RECTS[i]
		var card: Upgrades.CardState = Upgrades.card_state(_save, i)
		var accent: Color = Color(Palette.INK, 0.3)
		match card:
			Upgrades.CardState.BUYABLE:
				accent = Palette.AMBER
			Upgrades.CardState.OWNED, Upgrades.CardState.EQUIPPED:
				accent = Palette.CYAN
		draw_rect(rect, Palette.PANEL)
		draw_rect(rect, accent, false, 6.0 if card == Upgrades.CardState.EQUIPPED else 3.0)
	draw_rect(CLOCK_RECT, Palette.CYAN)
	draw_rect(CLOCK_RECT.grow(-8.0), Palette.PANEL, false, 3.0)


## Shows the Locker for [param save]. [param note] fills the line above the button, and [param code] is the last tower's share code.
func open(save: Dictionary, note: String, code: String = "") -> void:
	visible = true
	_seed_label.text = "LAST TOWER  %s" % code if code != "" else ""
	refresh(save, note)


## Redraws the cards and the balance for [param save].
func refresh(save: Dictionary, note: String) -> void:
	_save = save
	_tips.text = "MONEY  %d" % int(save["tips"])
	_note.text = note if note != "" else ("Earn money to buy upgrades." if save["owned"].is_empty() and int(save["tips"]) == 0 else "Tap a card to buy or equip.")
	for i: int in Upgrades.COUNT:
		var card: Upgrades.CardState = Upgrades.card_state(save, i)
		var dim: float = 0.65 if card == Upgrades.CardState.POOR or card == Upgrades.CardState.LOCKED else 1.0
		var word: String = ""
		match card:
			Upgrades.CardState.BUYABLE, Upgrades.CardState.POOR:
				word = "%d MONEY" % Upgrades.COSTS[i]
			Upgrades.CardState.OWNED:
				word = "OWNED"
			Upgrades.CardState.EQUIPPED:
				word = "EQUIPPED"
			_:
				word = "NEEDS %s" % Upgrades.NAMES[Upgrades.REQUIRES[i]].get_slice(" ", 2)
		_states[i].text = word
		_states[i].add_theme_color_override("font_color", Palette.AMBER if card == Upgrades.CardState.BUYABLE else (Palette.CYAN if card >= Upgrades.CardState.OWNED and card != Upgrades.CardState.LOCKED else Palette.INK))
		for label: Label in [_keys[i], _names[i], _effects[i], _states[i]]:
			label.modulate.a = dim
	queue_redraw()


## Returns the seed footer text, for the smoke test.
func seed_text() -> String:
	return _seed_label.text


## Hides the Locker.
func close() -> void:
	visible = false


## Returns the card under [param screen_pos], or -1.
func card_at(screen_pos: Vector2) -> int:
	for i: int in Upgrades.COUNT:
		if visible and CARD_RECTS[i].has_point(screen_pos):
			return i
	return -1


## Returns true when [param screen_pos] hits the CLOCK IN button.
func clock_in_at(screen_pos: Vector2) -> bool:
	return visible and CLOCK_RECT.has_point(screen_pos)


func _label(rect: Rect2, font_size: int, align: HorizontalAlignment) -> Label:
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
