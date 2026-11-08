class_name HumanController
extends Controller
## Drives one [Character] from touch or keyboard and mouse.
##
## The left thumb moves through [VirtualJoystick]. The right thumb throws through the active
## [ThrowScheme]: [LockFireScheme] or [AimStickScheme]. The scheme follows [method SettingsRef.scheme]
## and swaps at once when it changes, with no restart. [DashButton] and the Space key dash.
## When the controlled defender passes, control moves to the receiver, so the human always
## acts on the sandal. Listen to [signal Controller.character_changed] to hand the old body back to a bot.

## Joystick node. [method build_touch_ui] creates it when null.
var joystick: VirtualJoystick
## Dash button node. [method build_touch_ui] creates it when null.
var dash_button: DashButton
## The throw scheme in use, or null before [method build_touch_ui].
var scheme: ThrowScheme

var _ui_parent: Node
var _world_parent: Node


func _ready() -> void:
	SettingsRef.on_scheme_changed(_on_scheme_setting_changed)


func _process(_delta: float) -> void:
	if character == null or not is_instance_valid(character):
		return
	if not character.alive:
		character.move_intent = Vector2.ZERO
		return
	character.move_intent = _read_move_intent()
	if dash_button != null:
		dash_button.cooldown_ratio = character.dash_cooldown_ratio()


func _unhandled_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if character != null and key != null and key.pressed and not key.echo and key.physical_keycode == KEY_SPACE:
		character.dash()


## Creates the touch controls under [param parent]. Order matters: the dash button is added
## last so it sees touches before the throw controls do. The scheme draws in the world, so it
## goes under [param world_parent], or under this node when that is null.
func build_touch_ui(parent: Node, world_parent: Node = null) -> void:
	_ui_parent = parent
	_world_parent = world_parent if world_parent != null else self
	joystick = VirtualJoystick.new()
	parent.add_child(joystick)
	_build_scheme(SettingsRef.scheme())
	dash_button = DashButton.new()
	parent.add_child(dash_button)
	bind_touch_ui(joystick, dash_button)


## Connects existing controls. Call once.
func bind_touch_ui(new_joystick: VirtualJoystick, new_dash_button: DashButton) -> void:
	joystick = new_joystick
	dash_button = new_dash_button
	if not DisplayServer.is_touchscreen_available():
		joystick.zone_width_ratio = 0.0
	if not dash_button.pressed.is_connected(_on_dash_pressed):
		dash_button.pressed.connect(_on_dash_pressed)


## Switches to [param new_scheme] now. The round keeps running and the character keeps its sandal.
func use_scheme(new_scheme: int) -> void:
	if scheme != null and _scheme_id(scheme) == new_scheme:
		return
	_build_scheme(new_scheme)


## The scheme value in use: 0 for scheme D, 1 for scheme A.
func scheme_id() -> int:
	return _scheme_id(scheme) if scheme != null else SettingsRef.scheme()


func _on_attached(target: Character) -> void:
	target.passed.connect(_on_character_passed)
	if joystick != null:
		joystick.release()
	if scheme != null:
		_attach_scheme(target)


func _on_detached(target: Character) -> void:
	if target.passed.is_connected(_on_character_passed):
		target.passed.disconnect(_on_character_passed)
	if scheme != null:
		scheme.cancel()


func _build_scheme(new_scheme: int) -> void:
	if scheme != null:
		scheme.call(&"teardown")
		_world_parent.remove_child(scheme)
		scheme.queue_free()
		scheme = null
	if new_scheme == SettingsRef.SCHEME_AIM_STICK:
		scheme = AimStickScheme.new()
	else:
		scheme = LockFireScheme.new()
	scheme.tuning = Tuning.load_default()
	scheme.name = "ThrowScheme"
	_world_parent.add_child(scheme)
	scheme.call(&"build_ui", _ui_parent)
	_keep_dash_on_top()
	if character != null and is_instance_valid(character):
		_attach_scheme(character)


func _attach_scheme(target: Character) -> void:
	scheme.call(&"attach", target)


func _keep_dash_on_top() -> void:
	if dash_button != null and dash_button.get_parent() == _ui_parent:
		_ui_parent.move_child(dash_button, _ui_parent.get_child_count() - 1)


func _scheme_id(value: ThrowScheme) -> int:
	return SettingsRef.SCHEME_AIM_STICK if value is AimStickScheme else SettingsRef.SCHEME_LOCK_FIRE


func _read_move_intent() -> Vector2:
	# The thumb and the keys speak in screen directions. The tilted view squashes the field depth, so map them to the ground.
	var keys: Vector2 = Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	if keys != Vector2.ZERO:
		return ViewProjection.screen_dir_to_world(keys)
	if joystick != null:
		return ViewProjection.screen_dir_to_world(joystick.vector)
	return Vector2.ZERO


func _on_scheme_setting_changed(new_scheme: int) -> void:
	use_scheme(new_scheme)


func _on_dash_pressed() -> void:
	if character != null:
		character.dash()


func _on_character_passed(receiver: Character) -> void:
	attach(receiver)
