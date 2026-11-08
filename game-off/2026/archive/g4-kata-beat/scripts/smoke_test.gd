class_name SmokeTest
extends Node
## Scripted self-play for headless runs. Active only with the [code]--smoke[/code] user argument.
##
## Taps through the real input path: start, play with some skipped notes, finish, restart.

enum Phase { START, PLAY, RESTART }

## The main script under test. Set before this node enters the tree.
var main: Main

var _phase: Phase = Phase.START
var _next_note: int = 0
var _restart_msec: int = 0
var _begin_msec: int = Time.get_ticks_msec()


func _process(_delta: float) -> void:
	if Time.get_ticks_msec() - _begin_msec > 60000:
		_fail("timeout in phase %d state %d t=%.2f note %d" % [_phase, main.state, main.song_time, _next_note])
		return
	match _phase:
		Phase.START:
			_tap(0)
			_phase = Phase.PLAY
		Phase.PLAY:
			_play()
		Phase.RESTART:
			_restart()


func _play() -> void:
	if main.state == Main.State.DONE:
		if main.max_combo < 8 or main.score <= 0 or main.combo < 0:
			_fail("bad stats combo=%d score=%d" % [main.max_combo, main.score])
			return
		print("run done: score=%d max_combo=%d" % [main.score, main.max_combo])
		_phase = Phase.RESTART
		return
	while _next_note < main.times.size() and main.times[_next_note] <= main.song_time:
		if _next_note % 9 != 4:
			_tap(main.lanes[_next_note])
		_next_note += 1


func _restart() -> void:
	if main.state == Main.State.PLAYING:
		var elapsed: int = Time.get_ticks_msec() - _restart_msec
		if elapsed >= 200:
			_fail("restart took %d ms" % elapsed)
			return
		print("SMOKE OK")
		get_tree().quit()
	elif main.can_restart():
		_restart_msec = Time.get_ticks_msec()
		_tap(1)


func _tap(lane: int) -> void:
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	var pad_center: Vector2 = Vector2(lane * Playfield.LANE_W + 90.0, 760.0)
	# Input positions are window pixels, so undo the stretch transform.
	click.position = main.get_window().get_final_transform() * pad_center
	Input.parse_input_event(click)


func _fail(reason: String) -> void:
	print("SMOKE FAIL: ", reason)
	get_tree().quit(1)
