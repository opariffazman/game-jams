class_name BalanceQte
extends BuildQte
## Logic of the human balance build. It has no drawing and no input code, so a test runs it alone.
##
## Each step stands one sandal on its edge. The lean in [-1, 1] grows by itself and by a seeded
## sideways push. The player pushes it back with [member input]. A lean under
## [member Tuning.balance_safe_band] is steady, and a lock needs [member Tuning.balance_hold_seconds]
## of steady time. A lean of 1 drops the sandal: the miss penalty runs and the lean goes half way back.
## No step before the current one is ever lost. The signals are the ones of [BuildQte].

## Lean of the sandal from -1 (left) to 1 (right).
var lean: float = 0.0
## Player push from -1 to 1, set every frame by the overlay. Positive pushes the lean right.
var input: float = 0.0
## Seconds the lean has stayed steady.
var steady_time: float = 0.0
## Seconds of calm left at the start of a step. The wobble waits for it.
var grace_left: float = 0.0

var _drift_dir: float = 1.0
var _drift_left: float = 0.0
var _wobble_time: float = 0.0


## Share of the hold time reached, 0 to 1.
func hold_ratio() -> float:
	return clampf(steady_time / _tuning.balance_hold_seconds, 0.0, 1.0)


func is_steady() -> bool:
	return absf(lean) < _tuning.balance_safe_band


func update(delta: float) -> void:
	if not active:
		return
	if penalty_left > 0.0:
		penalty_left = maxf(penalty_left - delta, 0.0)
		if penalty_left <= 0.0:
			grace_left = _tuning.balance_grace_seconds * 0.5
		return
	elapsed += delta
	var push: float = 0.0
	if grace_left > 0.0:
		grace_left -= delta
	else:
		_wobble_time += delta
		_drift_left -= delta
		if _drift_left <= 0.0:
			_drift_dir = 1.0 if _rng.randf() < 0.5 else -1.0
			_drift_left = 0.8 + _rng.randf() * 0.6
		var strength: float = _tuning.balance_wobble * (1.0 + 0.15 * float(step)) * minf(1.0 + 0.25 * _wobble_time, 1.5)
		push = _drift_dir * strength
	var rate: float = _tuning.balance_instability * lean + push + clampf(input, -1.0, 1.0) * _tuning.balance_control
	lean = clampf(lean + rate * delta, -1.0, 1.0)
	if absf(lean) >= 1.0:
		_fall()
		return
	if grace_left > 0.0:
		return
	if is_steady():
		steady_time += delta
		if steady_time >= _tuning.balance_hold_seconds:
			_pass()
	else:
		steady_time = maxf(steady_time - delta * 2.0, 0.0)


## A tap, a click or the Space key moves the lean toward the centre by [member Tuning.balance_tap_nudge].
func tap() -> void:
	if not active or penalty_left > 0.0:
		return
	var nudge: float = _tuning.balance_tap_nudge
	lean -= clampf(lean, -nudge, nudge)


## A horizontal swipe nudges the lean the way it points. A vertical swipe does nothing.
func swipe(swipe_direction: Vector2) -> void:
	if not active or penalty_left > 0.0 or absf(swipe_direction.x) <= absf(swipe_direction.y):
		return
	lean = clampf(lean + signf(swipe_direction.x) * _tuning.balance_tap_nudge, -0.99, 0.99)


func _new_prompt() -> void:
	elapsed = 0.0
	lean = 0.0
	steady_time = 0.0
	grace_left = _tuning.balance_grace_seconds
	_wobble_time = 0.0
	_drift_left = 0.0


func _fall() -> void:
	lean *= 0.5
	steady_time = 0.0
	penalty_left = _tuning.miss_penalty_seconds
	missed.emit()
	if penalty_left <= 0.0:
		grace_left = _tuning.balance_grace_seconds * 0.5
