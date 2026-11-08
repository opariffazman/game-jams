class_name SmokeBot
extends Node
## Scripted self-play for headless runs. Uses the real input path, prints SMOKE OK on success.

## The game under test.
var main: Main


var _failed: bool = false


func _ready() -> void:
	_run()


func _run() -> void:
	await _frames(3)
	_press(true, Vector2(270.0, 850.0))
	# Drag until a hostile bullet exists, then lift and check the freeze.
	var elapsed: float = 0.0
	while _hostile_bullets().is_empty() and elapsed < 10.0:
		_drag(Vector2(sin(elapsed * 3.0), -0.2) * 700.0)
		elapsed += await _frame()
		if main.state == Main.State.LOST:
			break
	_check(main.time_flow > 0.5, "time flow rises while dragging")
	_press(false, Vector2(270.0, 850.0))
	if main.state == Main.State.PLAYING:
		await _wait(0.4)
		_check(main.time_flow == 0.0, "time flow freezes after lift")
		var before: Array[Vector2] = _bullet_positions()
		await _wait(0.3)
		_check(before == _bullet_positions(), "bullets hang while frozen")
		# Win path.
		var wave_before: int = main.wave
		for gunman: Gunman in main.gunmen:
			if gunman.alive:
				main.kill_gunman(gunman)
		await _wait(1.2)
		_check(main.wave > wave_before, "next wave starts after a clear")
		_check(main.gunmen.size() == mini(Main.START_GUNMEN + main.wave - 1, Main.MAX_GUNMEN), "wave size grows")
	# Lose path: chase the nearest hostile bullet.
	_press(true, Vector2(270.0, 850.0))
	elapsed = 0.0
	while main.state == Main.State.PLAYING and elapsed < 25.0:
		var bullets: Array[Bullet] = _hostile_bullets()
		if bullets.is_empty():
			_drag(Vector2(300.0, 0.0) * sin(elapsed * 4.0))
		else:
			var gap: Vector2 = bullets[0].position - (main.hero.position + Main.BODY_OFFSET)
			_drag(gap.limit_length(900.0 * get_process_delta_time()) / Main.DRAG_SCALE / maxf(get_process_delta_time(), 0.001))
		elapsed += await _frame()
	_check(main.state == Main.State.LOST, "hero dies to a bullet")
	_press(false, Vector2(270.0, 850.0))
	await _wait(0.1)
	_press(true, Vector2(270.0, 850.0))
	_press(false, Vector2(270.0, 850.0))
	await _frames(3)
	_check(main.state == Main.State.PLAYING and main.wave == 1, "tap restarts to wave 1")
	if not _failed:
		print("SMOKE OK")
		get_tree().quit(0)


func _press(pressed: bool, at: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = at
	Input.parse_input_event(event)


func _drag(velocity: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.relative = velocity * get_process_delta_time()
	event.position = Vector2(270.0, 850.0)
	Input.parse_input_event(event)


func _hostile_bullets() -> Array[Bullet]:
	var found: Array[Bullet] = []
	for bullet: Bullet in main.bullets:
		if bullet.hostile:
			found.append(bullet)
	return found


func _bullet_positions() -> Array[Vector2]:
	var positions: Array[Vector2] = []
	for bullet: Bullet in main.bullets:
		positions.append(bullet.position)
	return positions


func _frame() -> float:
	await get_tree().process_frame
	return get_process_delta_time()


func _frames(count: int) -> void:
	for i: int in count:
		await get_tree().process_frame


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failed = true
	print("SMOKE FAIL: ", label)
	get_tree().quit(1)
