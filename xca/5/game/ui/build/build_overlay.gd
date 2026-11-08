class_name BuildOverlay
extends Control
## Icon-only build controls of the human attacker: a build button and the timed prompts.
##
## The button appears while the human stands in the build zone and all sandals are there. A tap on
## it, or the Enter or E key, starts the build. Each step is a [BuildQte] prompt. Every prompt has a
## pointer tap alternative and a key alternative: Space taps, an arrow key swipes. The overlay never
## draws words. Shapes are light on a dark disc, which reads above 4.5:1.

## Smallest touch target in CSS pixels. WCAG 2.5.8 asks for 24 and 44 is the comfortable size.
const MIN_TARGET_CSS_PX: float = 44.0
## Diameter of the build button in CSS pixels.
const BUTTON_CSS_PX: float = 96.0
## Drag length in CSS pixels that gives full push on the balance lean.
const BALANCE_DRAG_CSS_PX: float = 60.0
## Diameter of the prompt disc in CSS pixels.
const PROMPT_CSS_PX: float = 120.0
const DISC_COLOR: Color = Color(0.04, 0.06, 0.11, 0.92)
const LIGHT_COLOR: Color = Color(1.0, 1.0, 1.0, 1.0)
const TARGET_COLOR: Color = Color(1.0, 0.9, 0.55, 1.0)
const MISS_COLOR: Color = Color(1.0, 0.55, 0.45, 1.0)
const DONE_COLOR: Color = Color(0.55, 1.0, 0.7, 1.0)

var round_manager: RoundManager
var tuning: Tuning
var stack: Stack
## Prompt logic while a build runs, otherwise null.
var qte: BuildQte
## Icon of the build button and the sandal pips.
var icon: Texture2D = preload("res://assets/icons/hud_stack.svg")
var pip_icon: Texture2D = preload("res://assets/icons/hud_sandal.svg")
var swipe_icon: Texture2D = preload("res://assets/icons/hint_hand.svg")

var _builder: Character
var _swipe_start: Vector2 = Vector2.ZERO
var _swipe_finger: int = -1
var _seed: int = 1
var _still_time: float = 0.0
var _drag_input: float = 0.0
var _pulse: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	if tuning == null:
		tuning = Tuning.load_default()
	if round_manager == null:
		round_manager = get_tree().get_first_node_in_group(RoundManager.GROUP) as RoundManager
	if round_manager != null and stack == null:
		stack = round_manager.arena.stack
	if stack != null:
		stack.build_ended.connect(_on_build_ended)
	set_process(true)


func _process(delta: float) -> void:
	_pulse += delta
	_auto_start(delta)
	if qte != null:
		var balance: BalanceQte = qte as BalanceQte
		if balance != null:
			var human: Character = _human()
			var stick: float = human.move_intent.x if human != null else 0.0
			var keys: float = float(Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_LEFT))
			balance.input = clampf(stick + _drag_input + keys, -1.0, 1.0)
		qte.update(delta)
		if qte.step < tuning.stack_size and _builder != null and not is_instance_valid(_builder):
			_stop()
	queue_redraw()


func _input(event: InputEvent) -> void:
	if not _human_can_see_build():
		return
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and not key.echo:
		if qte == null:
			if key.physical_keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_E]:
				_begin()
				get_viewport().set_input_as_handled()
			return
		var handled: bool = true
		if qte is BalanceQte:
			handled = key.physical_keycode in [KEY_SPACE, KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]
			if key.physical_keycode == KEY_SPACE:
				qte.tap()
			if handled:
				get_viewport().set_input_as_handled()
			return
		match key.physical_keycode:
			KEY_SPACE:
				qte.tap()
			KEY_UP:
				qte.swipe(Vector2.UP)
			KEY_DOWN:
				qte.swipe(Vector2.DOWN)
			KEY_LEFT:
				qte.swipe(Vector2.LEFT)
			KEY_RIGHT:
				qte.swipe(Vector2.RIGHT)
			_:
				handled = false
		if handled:
			get_viewport().set_input_as_handled()
		return
	_handle_pointer(event)


func _draw() -> void:
	if not _human_can_see_build():
		return
	if qte == null:
		_draw_button()
		return
	_draw_pips()
	if qte is BalanceQte:
		_draw_balance(qte as BalanceQte)
	else:
		_draw_prompt()


## True while a human attacker is alive in a down-stack round.
func _human_can_see_build() -> bool:
	var human: Character = _human()
	if human == null or stack == null or round_manager == null:
		return false
	return round_manager.phase == RoundManager.SCATTER and (qte != null or _button_visible(human))


func _button_visible(human: Character) -> bool:
	return human.carried == null and stack.can_build() and stack.is_in_zone(human.global_position)


func _human() -> Character:
	var node: Node = get_tree().get_first_node_in_group(RoundManager.HUMAN_GROUP)
	var human: Character = node as Character
	if human == null or not human.alive or human.role != Character.Role.ATTACKER:
		return null
	return human


func _begin() -> void:
	var human: Character = _human()
	if human == null or not human.start_building():
		return
	_builder = human
	_seed += 1
	qte = BalanceQte.new(tuning, _seed) if tuning.build_balance_enabled else BuildQte.new(tuning, _seed)
	_drag_input = 0.0
	qte.step_passed.connect(_on_step_passed)
	qte.missed.connect(_on_missed)
	qte.start(stack.placed_count)


## Starts the build after the human stands still in the zone with empty hands, so nobody has to hit the button.
func _auto_start(delta: float) -> void:
	var human: Character = _human()
	var ready: bool = qte == null and human != null and round_manager != null \
		and round_manager.phase == RoundManager.SCATTER and _button_visible(human) \
		and human.move_intent.length() < 0.2
	if not ready:
		_still_time = 0.0
		return
	_still_time += delta
	if _still_time >= tuning.balance_auto_start_seconds:
		_still_time = 0.0
		_begin()


func _stop() -> void:
	qte = null
	_builder = null
	_swipe_finger = -1


func _on_step_passed(_step: int) -> void:
	AudioRef.play(&"ui_tap")
	if _builder != null:
		_builder.complete_build_step()


func _on_missed() -> void:
	AudioRef.play(&"ui_press")


func _on_build_ended(builder: Character, _completed: bool) -> void:
	if builder == _builder:
		_stop()


func _handle_pointer(event: InputEvent) -> void:
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	var drag: InputEventScreenDrag = event as InputEventScreenDrag
	var balance: BalanceQte = qte as BalanceQte
	if touch != null:
		if touch.pressed:
			if qte == null:
				if _button_centre().distance_to(touch.position) <= _button_radius():
					_begin()
					get_viewport().set_input_as_handled()
			elif balance != null:
				_press_balance(touch, balance)
			elif _swipe_finger == -1:
				_swipe_finger = touch.index
				_swipe_start = touch.position
				get_viewport().set_input_as_handled()
		elif touch.index == _swipe_finger:
			_swipe_finger = -1
			_drag_input = 0.0
			if qte != null:
				var travel: Vector2 = touch.position - _swipe_start
				var minimum: float = tuning.qte_swipe_min_css_px * RestartUiScale.pixels_per_css(get_viewport())
				if travel.length() >= minimum and balance == null:
					qte.swipe(travel)
				elif travel.length() < minimum:
					qte.tap()
				get_viewport().set_input_as_handled()
	elif drag != null and drag.index == _swipe_finger and qte != null:
		if balance != null:
			var full: float = BALANCE_DRAG_CSS_PX * _scale()
			_drag_input = clampf((drag.position.x - _swipe_start.x) / full, -1.0, 1.0)
		get_viewport().set_input_as_handled()


## A press on the right half starts a horizontal drag that pushes the lean. A press on the left half
## is left to the joystick, and a short press there still nudges the lean toward the centre.
func _press_balance(touch: InputEventScreenTouch, balance: BalanceQte) -> void:
	if touch.position.x < get_viewport_rect().size.x * 0.5:
		balance.tap()
		return
	if _swipe_finger == -1:
		_swipe_finger = touch.index
		_swipe_start = touch.position
		get_viewport().set_input_as_handled()


func _scale() -> float:
	return RestartUiScale.pixels_per_css(get_viewport())


func _button_radius() -> float:
	return maxf(BUTTON_CSS_PX, MIN_TARGET_CSS_PX) * _scale() * 0.5


func _button_centre() -> Vector2:
	var size_on_screen: Vector2 = get_viewport_rect().size
	return Vector2(size_on_screen.x * 0.5, size_on_screen.y - _button_radius() - 24.0 * _scale())


func _prompt_centre() -> Vector2:
	var size_on_screen: Vector2 = get_viewport_rect().size
	# The disc sits at the bottom edge, so the pips and the disc stay clear of the pyramid the camera frames at the middle.
	return Vector2(size_on_screen.x * 0.5, size_on_screen.y - PROMPT_CSS_PX * _scale() * 0.5 - 10.0 * _scale())


func _draw_button() -> void:
	var centre: Vector2 = _button_centre()
	var radius: float = _button_radius()
	var pulse: float = 1.0 + 0.12 * sin(_pulse * 5.0)
	draw_arc(centre, radius * (1.15 + 0.1 * pulse), 0.0, TAU, 48, TARGET_COLOR * Color(1, 1, 1, 0.6), 3.0)
	draw_circle(centre, radius, DISC_COLOR)
	draw_arc(centre, radius, 0.0, TAU, 48, TARGET_COLOR, 4.0)
	var box: Rect2 = Rect2(centre - Vector2.ONE * radius * 0.55, Vector2.ONE * radius * 1.1)
	draw_texture_rect(icon, box, false, LIGHT_COLOR)


func _draw_pips() -> void:
	var centre: Vector2 = _prompt_centre()
	var radius: float = PROMPT_CSS_PX * _scale() * 0.5
	var pip: float = MIN_TARGET_CSS_PX * _scale()
	for index: int in tuning.stack_size:
		var at: Vector2 = centre + Vector2(radius + pip + float(index) * (pip + 8.0 * _scale()), 0.0)
		draw_circle(at, pip * 0.5, DISC_COLOR)
		var tint: Color = DONE_COLOR if index < stack.placed_count else (TARGET_COLOR if index == qte.step else LIGHT_COLOR * Color(1, 1, 1, 0.45))
		draw_texture_rect(pip_icon, Rect2(at - Vector2.ONE * pip * 0.35, Vector2.ONE * pip * 0.7), false, tint)


func _draw_prompt() -> void:
	var centre: Vector2 = _prompt_centre()
	var radius: float = PROMPT_CSS_PX * _scale() * 0.5
	draw_circle(centre, radius, DISC_COLOR)
	var penalty: bool = qte.penalty_left > 0.0
	if penalty:
		draw_arc(centre, radius, 0.0, TAU, 48, MISS_COLOR, 6.0)
		return
	if qte.kind == BuildQte.Kind.TAP:
		var target_radius: float = radius * 0.4
		var ring_radius: float = target_radius + (radius - target_radius) * qte.ring_ratio()
		draw_arc(centre, target_radius, 0.0, TAU, 48, TARGET_COLOR if qte.in_window() else LIGHT_COLOR, 5.0)
		draw_arc(centre, ring_radius, 0.0, TAU, 48, LIGHT_COLOR, 4.0)
	else:
		_draw_arrow(centre, radius * 0.7, qte.direction)
		var left: float = clampf(qte.time_left() / tuning.qte_swipe_seconds, 0.0, 1.0)
		draw_arc(centre, radius, -PI * 0.5, -PI * 0.5 + TAU * left, 48, LIGHT_COLOR, 4.0)


func _draw_arrow(centre: Vector2, length: float, direction: Vector2) -> void:
	var tip: Vector2 = centre + direction * length * 0.5
	var tail: Vector2 = centre - direction * length * 0.5
	var side: Vector2 = direction.orthogonal()
	draw_line(tail, tip - direction * length * 0.2, LIGHT_COLOR, 8.0)
	draw_colored_polygon(PackedVector2Array([tip, tip - direction * length * 0.4 + side * length * 0.25, tip - direction * length * 0.4 - side * length * 0.25]), LIGHT_COLOR)


## Gauge arc with a green steady band, a marker for the lean and the sandal icon tilting with it.
func _draw_balance(balance: BalanceQte) -> void:
	var centre: Vector2 = _prompt_centre()
	var radius: float = PROMPT_CSS_PX * _scale() * 0.5
	draw_circle(centre, radius, DISC_COLOR)
	var arc_radius: float = radius * 0.86
	var span: float = PI * 0.5
	var up: float = -PI * 0.5
	var band: float = span * tuning.balance_safe_band
	draw_arc(centre, arc_radius, up - span, up + span, 48, LIGHT_COLOR * Color(1, 1, 1, 0.45), 5.0)
	draw_arc(centre, arc_radius, up - band, up + band, 24, DONE_COLOR, 8.0)
	var marker_angle: float = up + balance.lean * span
	var marker: Vector2 = centre + Vector2.from_angle(marker_angle) * arc_radius
	var marker_color: Color = MISS_COLOR if balance.penalty_left > 0.0 else (DONE_COLOR if balance.is_steady() else TARGET_COLOR)
	draw_circle(marker, 7.0 * _scale(), marker_color)
	var tilt: float = balance.lean * 0.6
	draw_set_transform(centre + Vector2(0.0, radius * 0.05), tilt, Vector2.ONE)
	var size: float = radius * 0.8
	draw_texture_rect(pip_icon, Rect2(Vector2(-size * 0.5, -size * 0.6), Vector2(size, size)), false, marker_color if balance.penalty_left > 0.0 else LIGHT_COLOR)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_arc(centre, radius, up, up + TAU * balance.hold_ratio(), 48, DONE_COLOR, 5.0)
