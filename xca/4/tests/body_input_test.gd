extends SceneTree
## Headless check of the aim path at a fixed 60 fps. Run: godot --headless --path godot -s ../tests/body_input_test.gd
## It feeds scripted tracker frames at 12 per second and reads the aim every frame.

const FRAME: float = 1.0 / 60.0
const UPDATE_EVERY: int = 5
var _frame_id: int = 0
var _failed: bool = false


func _init() -> void:
	var input: BodyInput = BodyInput.new()
	root.add_child(input)
	input.magic = true
	_check_smooth_motion(input)
	_check_dropout_slide(input)
	_check_pose_triggers(input)
	_expect(input.get_slot_count() == 1, "single player exposes one slot")
	print("RESULT " + ("FAIL" if _failed else "PASS"))
	quit(1 if _failed else 0)


func _packet(x: float, y: float, pose: int, hands: int = 1) -> String:
	_frame_id += 1
	return JSON.stringify({"m": 1, "n": hands, "ok": hands > 0, "f": _frame_id, "ps": 0.2, "gs": 0.0, "fr": 1.5, "pg": 0.0, "pr": 1.5,
		"s": [[x, y, pose], [0.5, 0.5, 0], [0.5, 0.5, 0], [0.5, 0.5, 0]]})


## Runs frames, sending an update every few frames, and returns the largest aim step per frame.
func _run(input: BodyInput, frames: int, start_x: float, step_x: float, y: float, pose: int, hands: int = 1) -> float:
	var largest: float = 0.0
	var last: Vector2 = input.get_aim_point(0)
	for frame: int in frames:
		if frame % UPDATE_EVERY == 0:
			input.feed(_packet(start_x + step_x * (frame / UPDATE_EVERY), y, pose, hands))
		input.advance(FRAME)
		var aim: Vector2 = input.get_aim_point(0)
		largest = maxf(largest, aim.distance_to(last))
		last = aim
	return largest


func _check_smooth_motion(input: BodyInput) -> void:
	_run(input, 20, 0.4, 0.0, 0.5, 0)
	var largest: float = _run(input, 120, 0.4, 0.01, 0.5, 0)
	var per_update: float = 0.01 * input.gain_x
	var expected_per_frame: float = per_update / UPDATE_EVERY
	print("smooth motion: largest step %.4f per frame, even-motion share %.4f" % [largest, expected_per_frame])
	_expect(largest < expected_per_frame * 2.5, "aim steps stay near the even rate between updates")


func _check_dropout_slide(input: BodyInput) -> void:
	_run(input, 60, 0.7, 0.0, 0.6, 0)
	var held: Vector2 = input.get_aim_point(0)
	var lost_largest: float = 0.0
	for _frame: int in 20:
		input.advance(FRAME)
		lost_largest = maxf(lost_largest, input.get_aim_point(0).distance_to(held))
	print("hold: aim moved %.4f in 0.33 s with no hand, still aiming %s" % [lost_largest, input.is_aiming(0)])
	_expect(lost_largest < 0.0001 and input.is_aiming(0), "last aim holds for the first half second")
	for _frame: int in 60:
		input.advance(FRAME)
	_expect(not input.is_aiming(0), "aim is dropped after the hold")
	var before: Vector2 = input.get_aim_point(0)
	var largest: float = _run(input, 90, 0.3, 0.0, 0.4, 0)
	var distance: float = before.distance_to(input.get_aim_point(0))
	var even_rate: float = distance / (BodyInput.SLIDE_SECONDS / FRAME)
	print("return: travelled %.3f, largest step %.4f per frame, even rate %.4f" % [distance, largest, even_rate])
	_expect(largest < even_rate * 1.6, "a returning hand slides near the even rate instead of snapping")


func _check_pose_triggers(input: BodyInput) -> void:
	var palms: Array[int] = [0]
	var fists: Array[int] = [0]
	input.palm_triggered.connect(func(_slot: int) -> void: palms[0] += 1)
	input.fist_triggered.connect(func(_slot: int) -> void: fists[0] += 1)
	_run(input, 20, 0.5, 0.0, 0.5, 0)
	_run(input, UPDATE_EVERY * 2, 0.5, 0.0, 0.5, 1)
	_expect(palms[0] == 0, "two palm updates do not trigger")
	_run(input, UPDATE_EVERY * 8, 0.5, 0.0, 0.5, 1)
	_expect(palms[0] == 1, "a held palm triggers once, got %d" % palms[0])
	_run(input, UPDATE_EVERY * 6, 0.5, 0.0, 0.5, 0)
	_run(input, UPDATE_EVERY * 5, 0.5, 0.0, 0.5, 1)
	_expect(palms[0] == 2, "the palm rearms after it opens, got %d" % palms[0])
	_run(input, UPDATE_EVERY * 5, 0.5, 0.0, 0.5, 2)
	_expect(fists[0] == 1 and palms[0] == 2, "a held fist triggers the fist once, got %d" % fists[0])
	var flicker: int = fists[0]
	for _i: int in 4:
		_run(input, UPDATE_EVERY * 1, 0.5, 0.0, 0.5, 2)
		_run(input, UPDATE_EVERY * 1, 0.5, 0.0, 0.5, 0)
	_expect(fists[0] == flicker, "single-update flicker never triggers")
	_expect(not input.is_firing(0), "no pose fires the weapon")


func _expect(condition: bool, label: String) -> void:
	print(("PASS " if condition else "FAIL ") + label)
	if not condition:
		_failed = true
