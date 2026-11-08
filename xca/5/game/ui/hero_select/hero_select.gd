class_name HeroSelect
extends CanvasLayer
## Hero pick between the title Play tap and the coin flip. Icons only, no words.
##
## The tree stays paused until a hero is confirmed. One tap selects a card, a second tap on the same card
## or a tap on the confirm button confirms. The caller skips this screen when [method TitleScreen.should_skip]
## was true. The manager needs [code]heroes[/code], [code]tuning.human_team[/code] and [code]set_heroes()[/code].

signal confirmed(hero: HeroDef)

const GROUP: StringName = &"hero_select"
const BACKDROP_TOP: Color = Color("1f160e")
const BACKDROP_BOTTOM: Color = Color("3b2d1e")
const FACE: Color = Color("2a1f14")
const RING: Color = Color("ffc857")
const CREAM: Color = Color("fff3da")
const DIM_PIP: Color = Color("6b5a44")
const CARD_SIZE: Vector2 = Vector2(88.0, 88.0)
const CARD_GAP: float = 12.0
const CARD_LIFT: float = 6.0
const CONFIRM_SIZE: float = 64.0
const ENEMY_CARD: float = 52.0
const PIPS: int = 5

var cards: Array[Control] = []
var heroes: Array[HeroDef] = []
var selected: int = 0
var confirm_button: TitleIconButton

var _manager: Node
var _canvas: Control
var _open: bool = false
var _finished: bool = false
var _enemy_hero: HeroDef
var _last_tap_msec: int = -1000
var _last_tap_index: int = -1
var _dice: Texture2D = preload("res://assets/icons/dice.svg")


func _ready() -> void:
	layer = 21
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(GROUP)


func is_open() -> bool:
	return _open


## Shows the cards and pauses the match. Opens on the hero saved in settings.
func open(manager: Node) -> void:
	if _open:
		return
	_manager = manager
	heroes = HeroRoster.all()
	if heroes.is_empty():
		queue_free()
		return
	_enemy_hero = _find_enemy_hero()
	selected = maxi(_index_of(SettingsRef.hero_id()), 0)
	_build()
	_open = true
	get_tree().paused = true


## Confirms the hero with [param hero_id]. An unknown id does nothing.
func confirm(hero_id: StringName) -> void:
	var index: int = _index_of(hero_id)
	if index < 0 or _finished:
		return
	_finished = true
	selected = index
	var hero: HeroDef = heroes[index]
	SettingsRef.set_hero_id(hero.id)
	if _manager != null:
		_manager.call("set_heroes", hero, _enemy_hero)
	confirmed.emit(hero)
	get_tree().paused = false
	queue_free()


## Moves the selection by [param step] cards, wrapping at the ends.
func move_selection(step: int) -> void:
	select(posmod(selected + step, heroes.size()))


func select(index: int) -> void:
	selected = clampi(index, 0, heroes.size() - 1)
	_layout()
	_canvas.queue_redraw()


func _unhandled_key_input(event: InputEvent) -> void:
	if not _open or not (event is InputEventKey) or not (event as InputEventKey).pressed or (event as InputEventKey).echo:
		return
	match (event as InputEventKey).physical_keycode:
		KEY_LEFT, KEY_A:
			move_selection(-1)
		KEY_RIGHT, KEY_D:
			move_selection(1)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			confirm(heroes[selected].id)
		_:
			return
	get_viewport().set_input_as_handled()


func _find_enemy_hero() -> HeroDef:
	var held: Variant = _manager.get("heroes") if _manager != null else null
	var tuning: Variant = _manager.get("tuning") if _manager != null else null
	if held is Array and tuning != null:
		var enemy_team: int = 1 - int(tuning.get("human_team"))
		if enemy_team < (held as Array).size():
			return (held as Array)[enemy_team] as HeroDef
	return null


func _index_of(hero_id: StringName) -> int:
	for index: int in heroes.size():
		if heroes[index].id == hero_id:
			return index
	return -1


func _build() -> void:
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.draw.connect(_draw_canvas)
	_canvas.resized.connect(_layout)
	add_child(_canvas)
	for index: int in heroes.size():
		var card: Control = Control.new()
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.gui_input.connect(_on_card_input.bind(index))
		card.draw.connect(_draw_card.bind(card, index))
		_canvas.add_child(card)
		cards.append(card)
	confirm_button = TitleIconButton.new(TitleIconButton.Kind.PLAY)
	confirm_button.pulse = true
	confirm_button.pressed.connect(func() -> void: confirm(heroes[selected].id))
	_canvas.add_child(confirm_button)
	_layout()


func _layout() -> void:
	if _canvas == null or cards.is_empty():
		return
	var screen: Vector2 = _canvas.size
	var scale: float = clampf(minf(screen.x / 844.0, screen.y / 390.0), 0.8, 1.6)
	var card_size: Vector2 = CARD_SIZE * scale
	var gap: float = CARD_GAP * scale
	var total: float = card_size.x * cards.size() + gap * (cards.size() - 1)
	var left: float = (screen.x - total) * 0.5
	var top: float = screen.y - card_size.y - 28.0 * scale
	for index: int in cards.size():
		var lift: float = CARD_LIFT * scale if index == selected else 0.0
		cards[index].position = Vector2(left + (card_size.x + gap) * index, top - lift)
		cards[index].size = card_size
		cards[index].queue_redraw()
	var confirm_size: float = maxf(CONFIRM_SIZE * scale, 44.0)
	confirm_button.size = Vector2.ONE * confirm_size
	confirm_button.position = Vector2(left + total - confirm_size, top - confirm_size - 12.0 * scale)


func _on_card_input(event: InputEvent, index: int) -> void:
	var down: bool = false
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		down = (event as InputEventMouseButton).pressed
	elif event is InputEventScreenTouch:
		down = (event as InputEventScreenTouch).pressed
	if not down:
		return
	# A desktop click arrives as a mouse event and an emulated touch, so a repeat inside a few ms is one click.
	var now: int = Time.get_ticks_msec()
	if now - _last_tap_msec < 60 and index == _last_tap_index:
		return
	_last_tap_msec = now
	_last_tap_index = index
	if index == selected:
		confirm(heroes[index].id)
	else:
		select(index)


func _draw_canvas() -> void:
	var screen: Vector2 = _canvas.size
	_canvas.draw_rect(Rect2(Vector2.ZERO, screen), BACKDROP_TOP)
	_canvas.draw_rect(Rect2(0.0, screen.y * 0.5, screen.x, screen.y * 0.5), BACKDROP_BOTTOM)
	var scale: float = clampf(minf(screen.x / 844.0, screen.y / 390.0), 0.8, 1.6)
	var hero: HeroDef = heroes[selected]
	var preview: float = 120.0 * scale
	var centre: Vector2 = Vector2(screen.x * 0.5 - 150.0 * scale, 28.0 * scale + preview * 0.5 + 8.0 * scale)
	_canvas.draw_circle(centre, preview * 0.6, FACE)
	_canvas.draw_arc(centre, preview * 0.6, 0.0, TAU, 64, RING, 4.0 * scale, true)
	_canvas.draw_texture_rect(hero.icon, Rect2(centre - Vector2.ONE * preview * 0.4, Vector2.ONE * preview * 0.8), false, CREAM)
	var power_centre: Vector2 = centre + Vector2(preview * 0.95, 0.0)
	var power_radius: float = 30.0 * scale
	_canvas.draw_circle(power_centre, power_radius, FACE)
	_canvas.draw_texture_rect(hero.power_icon, Rect2(power_centre - Vector2.ONE * power_radius * 0.62, Vector2.ONE * power_radius * 1.24), false, CREAM)
	_draw_cooldown_ring(power_centre, power_radius, hero)
	_draw_pips(Vector2(power_centre.x + power_radius + 28.0 * scale, centre.y - 36.0 * scale), scale, hero)
	_draw_enemy_card(screen, scale)


func _draw_cooldown_ring(centre: Vector2, radius: float, hero: HeroDef) -> void:
	var fill: float = clampf(1.0 - hero.cooldown_seconds / 20.0, 0.08, 1.0)
	_canvas.draw_arc(centre, radius + 6.0, 0.0, TAU, 48, DIM_PIP, 4.0, true)
	_canvas.draw_arc(centre, radius + 6.0, -PI * 0.5, -PI * 0.5 + TAU * fill, 48, RING, 4.0, true)


func _draw_pips(origin: Vector2, scale: float, hero: HeroDef) -> void:
	var stats: Array[int] = [hero.stat_speed, hero.stat_build, hero.stat_guard, hero.stat_throw]
	var radius: float = 5.0 * scale
	for row: int in stats.size():
		for pip: int in PIPS:
			var at: Vector2 = origin + Vector2((radius * 2.6) * pip, (radius * 3.2) * row)
			_canvas.draw_circle(at, radius, RING if pip < stats[row] else DIM_PIP)


func _draw_enemy_card(screen: Vector2, scale: float) -> void:
	var side: float = ENEMY_CARD * scale
	var at: Vector2 = Vector2(screen.x - side - 20.0 * scale, 20.0 * scale)
	_canvas.draw_rect(Rect2(at, Vector2.ONE * side), FACE)
	_canvas.draw_rect(Rect2(at, Vector2.ONE * side), RING, false, 2.0 * scale)
	var icon: Texture2D = _enemy_hero.icon if _enemy_hero != null else _dice
	_canvas.draw_texture_rect(icon, Rect2(at + Vector2.ONE * side * 0.15, Vector2.ONE * side * 0.7), false, CREAM)
	if _enemy_hero != null:
		var badge: float = side * 0.34
		_canvas.draw_texture_rect(_dice, Rect2(at + Vector2(side - badge * 0.8, side - badge * 0.8), Vector2.ONE * badge), false, RING)


func _draw_card(card: Control, index: int) -> void:
	var is_selected: bool = index == selected
	var rect: Rect2 = Rect2(Vector2.ZERO, card.size)
	card.draw_rect(rect, FACE)
	card.draw_rect(rect, RING if is_selected else DIM_PIP, false, 5.0 if is_selected else 2.0)
	var inset: float = card.size.x * 0.16
	card.draw_texture_rect(heroes[index].icon, Rect2(Vector2.ONE * inset, card.size - Vector2.ONE * inset * 2.0), false, CREAM if is_selected else CREAM.darkened(0.25))
