class_name BuildOverlay
extends Control
## Icon-only build feedback of the human attacker. No prompt and no precision input.
##
## Standing in the build zone with empty hands and all sandals there fills a hold ring. When it
## fills, the build starts and each step places a sandal on a timer, like a bot build. Leaving the
## zone ends the build and keeps the placed sandals. Enter or E starts at once. The overlay never draws words. Shapes are light on a dark disc, above 4.5:1.

## Smallest touch target in CSS pixels. WCAG 2.5.8 asks for 24 and 44 is the comfortable size.
const MIN_TARGET_CSS_PX: float = 44.0
## Diameter of the progress disc in CSS pixels.
const PROMPT_CSS_PX: float = 64.0
const DISC_COLOR: Color = Color(0.04, 0.06, 0.11, 0.92)
const LIGHT_COLOR: Color = Color(1.0, 1.0, 1.0, 1.0)
const TARGET_COLOR: Color = Color(1.0, 0.9, 0.55, 1.0)
const DONE_COLOR: Color = Color(0.55, 1.0, 0.7, 1.0)

var round_manager: RoundManager
var tuning: Tuning
var stack: Stack
## Icon of the build button and the sandal pips.
var icon: Texture2D = preload("res://assets/icons/hud_stack.svg")
var pip_icon: Texture2D = preload("res://assets/icons/hud_sandal.svg")

var _builder: Character
var _hold_time: float = 0.0
var _step_time: float = 0.0
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
	if _builder != null:
		_run_build(delta)
	else:
		_run_hold(delta)
	queue_redraw()


func _input(event: InputEvent) -> void:
	if _builder != null or not _human_can_see_build():
		return
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and not key.echo and key.physical_keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_E]:
		_begin()
		get_viewport().set_input_as_handled()
		return


func _draw() -> void:
	if not _human_can_see_build():
		return
	if _builder == null:
		_draw_hold()
		return
	_draw_pips()
	_draw_progress()


## True while a human attacker is alive in a down-stack round.
func _human_can_see_build() -> bool:
	var human: Character = _human()
	if human == null or stack == null or round_manager == null:
		return false
	return round_manager.phase == RoundManager.SCATTER and (_builder != null or _button_visible(human))


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
	_hold_time = 0.0
	_step_time = 0.0


## Starts the build once the human has stood in the zone with empty hands for the hold time. Moving
## does not reset it, so a dodging attacker keeps building.
func _run_hold(delta: float) -> void:
	var human: Character = _human()
	var ready: bool = human != null and round_manager != null \
		and round_manager.phase == RoundManager.SCATTER and _button_visible(human)
	if not ready:
		_hold_time = 0.0
		return
	_hold_time += delta
	if _hold_time >= tuning.build_hold_seconds:
		_begin()


func _run_build(delta: float) -> void:
	if not is_instance_valid(_builder) or not _builder.is_building():
		_stop()
		return
	_step_time += delta
	if _step_time >= tuning.build_step_seconds:
		_step_time = 0.0
		AudioRef.play(&"ui_tap")
		_builder.complete_build_step()


func _stop() -> void:
	_builder = null
	_hold_time = 0.0
	_step_time = 0.0


func _on_build_ended(builder: Character, _completed: bool) -> void:
	if builder == _builder:
		_stop()


func _scale() -> float:
	return RestartUiScale.pixels_per_css(get_viewport())




func _prompt_centre() -> Vector2:
	var size_on_screen: Vector2 = get_viewport_rect().size
	# The disc sits at the bottom edge, so the pips and the disc stay clear of the pyramid the camera frames at the middle.
	return Vector2(size_on_screen.x * 0.5, size_on_screen.y - PROMPT_CSS_PX * _scale() * 0.5 - 10.0 * _scale())


func _draw_hold() -> void:
	var held: float = clampf(_hold_time / tuning.build_hold_seconds, 0.0, 1.0)
	if held <= 0.0:
		return
	var centre: Vector2 = _prompt_centre()
	var radius: float = PROMPT_CSS_PX * _scale() * 0.5
	draw_circle(centre, radius, DISC_COLOR)
	draw_arc(centre, radius, -PI * 0.5, -PI * 0.5 + TAU * held, 48, DONE_COLOR, 6.0)
	var size: float = radius * 0.9
	draw_texture_rect(icon, Rect2(centre - Vector2.ONE * size * 0.5, Vector2.ONE * size), false, LIGHT_COLOR)


func _draw_pips() -> void:
	var centre: Vector2 = _prompt_centre()
	var radius: float = PROMPT_CSS_PX * _scale() * 0.5
	var pip: float = MIN_TARGET_CSS_PX * _scale()
	for index: int in tuning.stack_size:
		var at: Vector2 = centre + Vector2(radius + pip + float(index) * (pip + 8.0 * _scale()), 0.0)
		draw_circle(at, pip * 0.5, DISC_COLOR)
		var tint: Color = DONE_COLOR if index < stack.placed_count else (TARGET_COLOR if index == stack.placed_count else LIGHT_COLOR * Color(1, 1, 1, 0.45))
		draw_texture_rect(pip_icon, Rect2(at - Vector2.ONE * pip * 0.35, Vector2.ONE * pip * 0.7), false, tint)


## Disc with a ring that fills toward the next sandal, or toward the build start while holding.
func _draw_progress() -> void:
	var centre: Vector2 = _prompt_centre()
	var radius: float = PROMPT_CSS_PX * _scale() * 0.5
	draw_circle(centre, radius, DISC_COLOR)
	var ratio: float = clampf(_step_time / tuning.build_step_seconds, 0.0, 1.0)
	draw_arc(centre, radius, -PI * 0.5, -PI * 0.5 + TAU * ratio, 48, DONE_COLOR, 6.0)
	var size: float = radius * 0.9
	draw_texture_rect(icon, Rect2(centre - Vector2.ONE * size * 0.5, Vector2.ONE * size), false, LIGHT_COLOR)
