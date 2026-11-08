class_name AimStickScheme
extends ThrowScheme
## Scheme A, manual throw.
##
## The right thumb drags from the stick centre. The sandal flies where the thumb points, and the drag
## length sets the power: [member Tuning.max_throw_range] at the stick edge, nothing at the slop radius.
## Nothing snaps to a target. A line shows the exact flight, a ring shows where it ends, and the line
## stops at the first character it touches. Release fires. A drag back inside the slop cancels.
## A tap is the one assisted action: a defender passes to the nearest living teammate and an
## attacker throws at the stack at full power. On desktop the mouse drags from the stick centre
## and a right click or Escape cancels. A plain click is a tap.

## Length of the tick that marks the stack on the preview line.
const STACK_TICK: float = 16.0

## The aim stick. Created by [method build_ui].
var stick: AimStick

var _aim: Vector2 = Vector2.ZERO
var _power: float = 0.0
var _mouse_down: bool = false
var _mouse_left_slop: bool = false


func _process(delta: float) -> void:
	super._process(delta)
	if stick != null and character != null and is_instance_valid(character):
		stick.visible = character.alive and character.carried != null


func _unhandled_input(event: InputEvent) -> void:
	if character == null or not character.alive or character.carried == null:
		return
	if event is InputEventKey:
		var key: InputEventKey = event
		if key.pressed and not key.echo and key.physical_keycode == KEY_ESCAPE and previewing:
			_cancel_aim()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and not DisplayServer.is_touchscreen_available():
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion and _mouse_down:
		_aim_from(event.position - _desktop_origin())


## The manual preview replaces the shared line and ring, because no lock exists in this scheme.
func draws_target_preview() -> bool:
	return false


func _draw() -> void:
	begin_ground_draw()
	if not previewing or _aim == Vector2.ZERO or character == null or not is_instance_valid(character):
		return
	if character.carried == null:
		return
	var flight: Dictionary = flight_for(_aim, _power)
	var origin: Vector2 = to_local(character.global_position)
	var start: Vector2 = to_local(flight["start"])
	var end: Vector2 = to_local(flight["end"])
	var tint: Color = _flight_color(flight["hit"] as Character)
	draw_dashed_line(origin, end, tint, LINE_WIDTH, 14.0)
	draw_arc(end, RING_RADIUS * 0.6, 0.0, TAU, 24, tint, 3.0)
	_draw_stack_tick(start, end, tint)


## Creates the aim stick under [param parent]. Call once.
func build_ui(parent: Node) -> void:
	stick = AimStick.new()
	stick.tuning = tuning
	parent.add_child(stick)
	stick.aimed.connect(_on_aimed)
	stick.released.connect(_on_released)
	stick.cancelled.connect(_cancel_aim)
	stick.tapped.connect(tap)


## Removes the controls this scheme made.
func teardown() -> void:
	if stick != null and is_instance_valid(stick):
		stick.get_parent().remove_child(stick)
		stick.queue_free()
	stick = null
	previewing = false


## Points the scheme at a character.
func attach(target: Character) -> void:
	character = target
	previewing = false
	_aim = Vector2.ZERO
	_power = 0.0
	if stick != null:
		stick.release()


## The current aim bearing. Zero while the finger rests inside the slop.
func aim_bearing() -> Vector2:
	return _aim


## The current drag power from 0.0 to 1.0.
func aim_power() -> float:
	return _power


## Applies an aim as if the thumb moved there. [param power] is the drag power from 0.0 to 1.0.
func apply_aim(bearing: Vector2, power: float = 1.0) -> void:
	_aim = bearing
	_power = clampf(power, 0.0, 1.0) if bearing != Vector2.ZERO else 0.0
	previewing = bearing != Vector2.ZERO


## Fires along the current aim at the current power. Returns true when a sandal left the hand.
func fire_aim() -> bool:
	if _aim == Vector2.ZERO or character == null or not is_instance_valid(character):
		return false
	var thrown: bool = character.throw_manual(_aim, _power)
	if thrown:
		SettingsRef.vibrate(tuning.haptic_fire_ms)
		fired.emit()
	previewing = false
	_aim = Vector2.ZERO
	_power = 0.0
	return thrown


## The assisted action of a tap. A defender passes to the nearest living teammate. An attacker
## throws at the stack at full power. Returns true when a sandal left the hand.
func tap() -> bool:
	if character == null or not is_instance_valid(character) or not character.alive or character.carried == null:
		return false
	var thrown: bool = false
	if character.role == Character.Role.ATTACKER:
		thrown = character.throw_manual(_stack_direction(), 1.0)
	else:
		var mate: Character = _nearest_teammate()
		thrown = mate != null and character.pass_to(mate)
	if thrown:
		SettingsRef.vibrate(tuning.haptic_fire_ms)
		fired.emit()
	return thrown


## The exact flight of a throw along [param bearing] at [param power]. [code]start[/code] is where the
## sandal leaves the hand, [code]end[/code] is where it stops or meets its first character, and
## [code]hit[/code] is that character or null.
func flight_for(bearing: Vector2, power: float) -> Dictionary:
	var direction: Vector2 = bearing.normalized()
	var hand_offset: float = tuning.character_radius + 12.0
	var start: Vector2 = character.global_position + direction * hand_offset
	var length: float = maxf(tuning.max_throw_range * clampf(power, 0.0, 1.0) - hand_offset, 0.0)
	var reach: float = tuning.character_radius + tuning.sandal_radius
	var best_along: float = length
	var hit: Character = null
	if character.arena != null:
		for team: int in 2:
			for entry: Variant in character.arena.get_characters(team):
				var other: Character = entry as Character
				if other == null or other == character or not other.alive:
					continue
				var offset: Vector2 = other.global_position - start
				var along: float = offset.dot(direction)
				var gap: float = absf(offset.cross(direction))
				if along < 0.0 or gap >= reach:
					continue
				along -= sqrt(reach * reach - gap * gap)
				if along < best_along:
					best_along = maxf(along, 0.0)
					hit = other
	return {"start": start, "end": start + direction * best_along, "hit": hit}


func _on_aimed(bearing: Vector2, power: float) -> void:
	apply_aim(ViewProjection.screen_dir_to_world(bearing), power)


func _on_released(_bearing: Vector2) -> void:
	fire_aim()


func _cancel_aim() -> void:
	_aim = Vector2.ZERO
	_power = 0.0
	_mouse_down = false
	cancel()


func _nearest_teammate() -> Character:
	var best: Character = null
	var best_distance: float = INF
	if character.arena == null:
		return null
	for entry: Variant in character.arena.get_characters(character.team):
		var other: Character = entry as Character
		if other == null or other == character or not other.alive:
			continue
		var distance: float = other.global_position.distance_to(character.global_position)
		if distance < best_distance:
			best_distance = distance
			best = other
	return best


func _flight_color(hit: Character) -> Color:
	if hit == null:
		return tuning.preview_stack_color
	return tuning.friendly_color if hit.team == character.team else tuning.enemy_color


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_cancel_aim()
	elif event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_mouse_down = true
			_mouse_left_slop = false
		elif _mouse_down:
			_mouse_down = false
			if not _mouse_left_slop:
				tap()
			elif not fire_aim():
				_cancel_aim()


func _aim_from(offset: Vector2) -> void:
	if offset.length() <= tuning.slop_px:
		apply_aim(Vector2.ZERO)
		return
	_mouse_left_slop = true
	var reach: float = tuning.aim_stick_css_px * 0.5
	apply_aim(ViewProjection.screen_dir_to_world(offset.normalized()), (offset.length() - tuning.slop_px) / maxf(reach - tuning.slop_px, 1.0))


func _desktop_origin() -> Vector2:
	if character == null:
		return Vector2.ZERO
	return ViewProjection.to_screen(get_viewport(), character.global_position)


func _draw_stack_tick(start: Vector2, end: Vector2, tint: Color) -> void:
	if character.arena == null:
		return
	var line: Vector2 = end - start
	var length: float = line.length()
	if length < 1.0:
		return
	var direction: Vector2 = line / length
	var offset: Vector2 = to_local(character.arena.centre_spot) - start
	var along: float = offset.dot(direction)
	if along < 0.0 or along > length or absf(offset.cross(direction)) > tuning.sandal_radius * 2.0:
		return
	var point: Vector2 = start + direction * along
	var side: Vector2 = direction.orthogonal() * STACK_TICK
	draw_line(point - side, point + side, tint, 4.0)
