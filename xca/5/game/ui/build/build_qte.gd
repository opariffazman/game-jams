class_name BuildQte
extends RefCounted
## Logic of the human build prompts. It has no drawing and no input code, so a test runs it alone.
##
## A build has [member Tuning.stack_size] steps. The prompt kinds alternate: tap, swipe, tap. A miss
## costs [member Tuning.miss_penalty_seconds] and the same step prompts again. A step never resets
## the steps before it.

## Emitted when the current step succeeds. [param step] is the index of the step that passed.
signal step_passed(step: int)
## Emitted on a miss. The penalty starts.
signal missed
## Emitted after the last step passed.
signal finished

enum Kind { TAP, SWIPE }

## Swipe directions in the order of the random draw.
const DIRECTIONS: Array[Vector2] = [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]

## Index of the step on screen, 0 to stack_size - 1.
var step: int = 0
## Kind of the prompt on screen.
var kind: Kind = Kind.TAP
## Direction of the swipe prompt.
var direction: Vector2 = Vector2.UP
## Seconds since the prompt appeared.
var elapsed: float = 0.0
## Seconds of penalty left. Input is ignored while it runs.
var penalty_left: float = 0.0
## True from [method start] until the last step passes or [method stop].
var active: bool = false

var _tuning: Tuning
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _init(tuning: Tuning, seed_value: int = 0) -> void:
	_tuning = tuning
	_rng.seed = seed_value


## Starts at step [param first_step]. A builder who continues a half-built pyramid starts later.
func start(first_step: int = 0) -> void:
	step = first_step
	active = true
	penalty_left = 0.0
	_new_prompt()


func stop() -> void:
	active = false


## Share of the tap ring that is still outside the target, 1.0 at the start and 0.0 at the target.
func ring_ratio() -> float:
	return clampf(1.0 - elapsed / _tuning.qte_tap_seconds, 0.0, 1.0)


## Seconds until the prompt times out.
func time_left() -> float:
	if kind == Kind.TAP:
		return _tuning.qte_tap_seconds + _tuning.qte_window_seconds - elapsed
	return _tuning.qte_swipe_seconds - elapsed


## True while a tap now counts as a hit on a tap prompt.
func in_window() -> bool:
	return kind == Kind.TAP and absf(elapsed - _tuning.qte_tap_seconds) <= _tuning.qte_window_seconds


func update(delta: float) -> void:
	if not active:
		return
	if penalty_left > 0.0:
		penalty_left = maxf(penalty_left - delta, 0.0)
		if penalty_left <= 0.0:
			_new_prompt()
		return
	elapsed += delta
	if time_left() <= 0.0:
		_miss()


## A tap, a click or the Space key. It also answers a swipe prompt, so no prompt needs a gesture.
func tap() -> void:
	if not active or penalty_left > 0.0:
		return
	if kind == Kind.SWIPE or in_window():
		_pass()
	else:
		_miss()


## A swipe or an arrow key along [param swipe_direction]. A tap prompt takes it as a miss.
func swipe(swipe_direction: Vector2) -> void:
	if not active or penalty_left > 0.0:
		return
	if kind == Kind.SWIPE and _nearest_direction(swipe_direction) == direction:
		_pass()
	else:
		_miss()


func _new_prompt() -> void:
	elapsed = 0.0
	kind = Kind.TAP if step % 2 == 0 else Kind.SWIPE
	direction = DIRECTIONS[_rng.randi() % DIRECTIONS.size()]


func _pass() -> void:
	var passed: int = step
	step += 1
	if step >= _tuning.stack_size:
		active = false
		step_passed.emit(passed)
		finished.emit()
		return
	_new_prompt()
	step_passed.emit(passed)


func _miss() -> void:
	penalty_left = _tuning.miss_penalty_seconds
	elapsed = 0.0
	missed.emit()
	if penalty_left <= 0.0:
		_new_prompt()


func _nearest_direction(vector: Vector2) -> Vector2:
	if vector == Vector2.ZERO:
		return Vector2.ZERO
	if absf(vector.x) > absf(vector.y):
		return Vector2.RIGHT if vector.x > 0.0 else Vector2.LEFT
	return Vector2.DOWN if vector.y > 0.0 else Vector2.UP
