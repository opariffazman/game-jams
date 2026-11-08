class_name LockFireScheme
extends ThrowScheme
## Scheme D, Lock and fire.
##
## One fixed fire button. A tap fires at the visible lock. A drag moves the lock to the character
## nearest the drag bearing. A drag back inside the slop circle cancels. Attackers always lock
## the stack. On desktop a left click fires, a held click moves the lock, Q and E cycle it,
## F fires, and a right click or Escape cancels.

## Seconds the ghost hand animation runs once.
const HINT_LENGTH: float = 2.2
## Icon of the ghost hand.
const HAND_ICON: Texture2D = preload("res://assets/icons/hint_hand.svg")

## The fire button. Created by [method build_ui].
var button: FireButton

var _hint_clock: float = -1.0
var _idle_time: float = 0.0
var _hint_plays: int = 0
var _hint_done: bool = false
var _mouse_down: bool = false
var _mouse_origin: Vector2 = Vector2.ZERO


func _process(delta: float) -> void:
	super._process(delta)
	if character == null or not is_instance_valid(character):
		return
	if button != null:
		button.visible = character.alive and character.carried != null
		button.kind = int(kind)
		button.lock_color = preview_color()
	_update_hint(delta)


func _unhandled_input(event: InputEvent) -> void:
	if character == null or not character.alive or character.carried == null:
		return
	if event is InputEventKey:
		_handle_key(event)
	elif event is InputEventMouseButton and not DisplayServer.is_touchscreen_available():
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion and _mouse_down:
		_handle_mouse_motion(event)


func _draw() -> void:
	super._draw()
	if _hint_clock < 0.0 or character == null or not is_instance_valid(character):
		return
	_draw_ghost_hand()


## Creates the fire button under [param parent]. Call once.
func build_ui(parent: Node) -> void:
	button = FireButton.new()
	button.tuning = tuning
	button.kind_icons = ThrowIcons.kind_icons()
	parent.add_child(button)
	button.pressed.connect(_on_pressed)
	button.dragged.connect(_on_dragged)
	button.released.connect(_on_released)
	button.cancelled.connect(_on_cancelled)


## Removes the controls this scheme made.
func teardown() -> void:
	if button != null and is_instance_valid(button):
		button.get_parent().remove_child(button)
		button.queue_free()
	button = null
	previewing = false


## Points the scheme at a character. Resets the lock and the hint.
func attach(target: Character) -> void:
	character = target
	previewing = false
	if button != null:
		button.release()
	reset_lock()


## Starts the ghost hand now. It plays once and counts toward the replay limit.
func play_hint() -> void:
	_hint_clock = 0.0
	_hint_plays += 1
	_idle_time = 0.0


## True after a throw fired. The hint then stops for good.
func hint_finished() -> bool:
	return _hint_done


func _on_pressed() -> void:
	_hint_clock = -1.0
	_idle_time = 0.0
	reset_lock()
	previewing = true


func _on_dragged(bearing: Vector2) -> void:
	steer_lock(ViewProjection.screen_dir_to_world(bearing))


func _on_released() -> void:
	if fire():
		_hint_done = true
		_hint_clock = -1.0
	previewing = false


func _on_cancelled() -> void:
	cancel()


func _handle_key(key: InputEventKey) -> void:
	if not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_F:
			reset_lock_if_unset()
			if fire():
				_hint_done = true
			previewing = false
		KEY_Q:
			_cycle(-1)
		KEY_E:
			_cycle(1)
		KEY_ESCAPE:
			if previewing:
				cancel()
				get_viewport().set_input_as_handled()


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_mouse_down = false
		cancel()
	elif event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_mouse_down = true
			_mouse_origin = event.position
			reset_lock()
			previewing = true
		elif _mouse_down:
			_mouse_down = false
			if fire():
				_hint_done = true
			previewing = false


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	var offset: Vector2 = event.position - _mouse_origin
	if offset.length() > tuning.slop_px:
		steer_lock(ViewProjection.screen_dir_to_world(offset.normalized()))


func reset_lock_if_unset() -> void:
	if kind == TargetKind.NONE:
		reset_lock()


func _cycle(step: int) -> void:
	var list: Array[Character] = candidates()
	if list.is_empty():
		return
	list.sort_custom(func(a: Character, b: Character) -> bool:
		return character.global_position.angle_to_point(a.global_position) < character.global_position.angle_to_point(b.global_position)
	)
	var index: int = list.find(locked)
	index = (index + step + list.size()) % list.size() if index >= 0 else 0
	var target: Character = list[index]
	_set_lock(target, _kind_of(target))
	previewing = true


func _update_hint(delta: float) -> void:
	if _hint_done or not DisplayServer.is_touchscreen_available():
		return
	if _hint_clock >= 0.0:
		_hint_clock += delta
		if _hint_clock >= HINT_LENGTH:
			_hint_clock = -1.0
		queue_redraw()
		return
	if character.carried == null or not character.alive:
		_idle_time = 0.0
		return
	_idle_time += delta
	var wait: float = tuning.hint_replay_seconds if _hint_plays > 0 else 1.5
	if _idle_time >= wait and _hint_plays <= tuning.hint_replay_limit:
		play_hint()


func _draw_ghost_hand() -> void:
	var progress: float = clampf(_hint_clock / HINT_LENGTH, 0.0, 1.0)
	var tap: float = clampf((progress - 0.15) / 0.2, 0.0, 1.0)
	var origin: Vector2 = to_local(character.global_position)
	var tint: Color = Color(1.0, 1.0, 1.0, 0.9 * (1.0 - clampf((progress - 0.8) / 0.2, 0.0, 1.0)))
	var ring_centre: Vector2 = to_local(_ring_centre())
	if progress > 0.3:
		draw_arc(ring_centre, RING_RADIUS + 4.0 * sin(progress * TAU * 2.0), 0.0, TAU, 40, Color(preview_color(), tint.a), LINE_WIDTH)
	var hand_size: float = 56.0
	# The hand is a flat icon, so it is placed through the projection and drawn without the ground skew.
	var hand_pos: Vector2 = screen_to_canvas_point(character.global_position) + Vector2(0.0, 70.0) - Vector2(0.0, 10.0 * tap)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	draw_texture_rect(HAND_ICON, Rect2(hand_pos - Vector2.ONE * hand_size * 0.5, Vector2.ONE * hand_size), false, tint)
	begin_ground_draw()
	if progress > 0.4:
		var flight: float = clampf((progress - 0.4) / 0.4, 0.0, 1.0)
		var from: Vector2 = origin
		var to: Vector2 = to_local(_aim_point())
		draw_circle(from.lerp(to, flight), 9.0, Color(preview_color(), tint.a))
