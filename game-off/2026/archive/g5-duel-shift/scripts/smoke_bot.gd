class_name SmokeBot
extends Node
## Headless self-play. Injects mouse events, wins one run, loses one, restarts, prints SMOKE OK.

## Game under test.
var main: Main

var _stage: int = 0
var _acted_round: int = -1
var _expect_stance: int = -1
var _expect_restart: bool = false
var _start_ms: int = 0


func _ready() -> void:
	Engine.time_scale = 4.0
	_start_ms = Time.get_ticks_msec()
	var rules: DuelRules = DuelRules.new(99)
	var run: int = 0
	var last: int = -1
	for i: int in 400:
		var t: int = rules.next_tell()
		run = run + 1 if t == last else 1
		last = t
		_check(run <= 2, "tell sequence has 3 identical in a row")


func _process(_delta: float) -> void:
	_check(Time.get_ticks_msec() - _start_ms < 90000, "timeout")
	if _expect_stance >= 0:
		_check(main.stance == _expect_stance, "shift not applied by next frame")
		_expect_stance = -1
	if _expect_restart:
		_expect_restart = false
		_check(main.phase == Main.Phase.TELL and main.hearts == 3 and main.boss_hp == 3, "restart not applied by next frame")
	match main.phase:
		Main.Phase.TELL:
			_play_tell()
		Main.Phase.WIN:
			_check(_stage == 0 and main.hearts == 3 and main.boss_hp == 0, "bad win state")
			_stage = 1
			_restart_by_tap()
		Main.Phase.LOSE:
			_check(_stage == 1 and main.hearts == 0, "bad lose state")
			_stage = 2
			_restart_by_tap()
	if _stage == 2 and not _expect_restart and main.phase == Main.Phase.TELL:
		print("SMOKE OK")
		get_tree().quit(0)


func _play_tell() -> void:
	if _acted_round == main.round_index or _stage > 1:
		return
	_acted_round = main.round_index
	var wanted: int = DuelRules.safe_stance(main.tell) if _stage == 0 else DuelRules.hit_stance(main.tell)
	if wanted != main.stance:
		_expect_stance = wanted
		_tap(Hud.PAD_STANCES.find(wanted))


func _restart_by_tap() -> void:
	_expect_restart = true
	_acted_round = -1
	_tap(0)


func _tap(pad: int) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	# Injected events are in window pixels. The headless window is not 540 x 960.
	event.position = get_window().get_final_transform() * Hud.PAD_RECTS[pad].get_center()
	event.pressed = true
	Input.parse_input_event(event)
	var release: InputEventMouseButton = event.duplicate()
	release.pressed = false
	Input.parse_input_event(release)


func _check(ok: bool, message: String) -> void:
	if not ok:
		print("SMOKE FAIL: ", message)
		get_tree().quit(1)
