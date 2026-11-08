class_name Smoke
extends Node
## Headless self-play: three takes, the Director Cut, then a restart. Runs only with the --smoke user arg.

## Game under test.
var game: Main
var _failed: bool = false
var _finger: Vector2 = Vector2(270.0, 800.0)


func _ready() -> void:
	Input.use_accumulated_input = false
	Engine.physics_ticks_per_second = 480
	get_tree().create_timer(90.0, true, false, true).timeout.connect(_fail.bind("timeout"))
	_run()


func _run() -> void:
	await _until(func() -> bool: return game.phase == Main.Phase.INTRO)
	for take: int in Main.TAKE_COUNT:
		await _until(func() -> bool: return game.phase == Main.Phase.INTRO and game.take_index == take)
		_press(Vector2(270.0, 800.0))
		await _play_take(take, 2 * (take + 1))
	await _until(func() -> bool: return game.phase == Main.Phase.RESULT)
	var fell: int = game._arena.fallen_count()
	if fell != 6 - game.take3_left or fell < 1:
		return _fail("cut fell %d but take 3 left %d" % [fell, game.take3_left])
	for k: int in Main.TAKE_COUNT:
		if game.figures[k].pos != game.track_pos[k][Main.TAKE_TICKS - 1]:
			return _fail("replay drift on track %d" % k)
	var started: int = Time.get_ticks_msec()
	_press(Vector2(270.0, 300.0))
	await get_tree().process_frame
	var elapsed: int = Time.get_ticks_msec() - started
	if game.phase != Main.Phase.INTRO or game.take_index != 0 or elapsed >= 200:
		return _fail("restart phase %d take %d after %d ms" % [game.phase, game.take_index, elapsed])
	if not _failed:
		print("SMOKE OK fell=%d restart_ms=%d" % [fell, elapsed])
		get_tree().quit()


func _play_take(take: int, kill_goal: int) -> void:
	while game.take_index == take and game.phase in [Main.Phase.INTRO, Main.Phase.TAKE]:
		await get_tree().physics_frame
		var target: Vector2 = game._arena.nearest_alive(game.hero.pos)
		if target == Vector2.INF or game._arena.alive_count() <= 6 - kill_goal:
			continue
		var offset: Vector2 = target - game.hero.pos
		if offset.length() > 40.0:
			_motion(offset.limit_length(14.0) / Main.DRAG_SCALE)
		else:
			_release()
			_press(Vector2(270.0, 800.0))
			_release()
			_press(Vector2(270.0, 800.0))


func _until(condition: Callable) -> void:
	while not condition.call():
		await get_tree().process_frame


func _press(at: Vector2) -> void:
	_button(at, true)


func _release() -> void:
	_button(Vector2(270.0, 800.0), false)


func _button(at: Vector2, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = get_viewport().get_final_transform() * at
	event.pressed = pressed
	Input.parse_input_event(event)


func _motion(relative: Vector2) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	_finger += relative
	var to_screen: Transform2D = get_viewport().get_final_transform()
	event.position = to_screen * _finger
	event.relative = to_screen.basis_xform(relative)
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(event)


func _fail(reason: String) -> void:
	if _failed:
		return
	_failed = true
	print("SMOKE FAIL: ", reason)
	get_tree().quit(1)
