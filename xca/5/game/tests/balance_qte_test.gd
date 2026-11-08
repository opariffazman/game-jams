extends SceneTree
## Fast headless test of the balance build logic.
##
## Run: godot --headless --path game --script res://tests/balance_qte_test.gd

const DT: float = 1.0 / 60.0

var _failures: int = 0


func _initialize() -> void:
	_run()
	print("balance_qte_test: %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(_failures)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   ", label)
	else:
		print("  FAIL ", label)
		_failures += 1


## Corrects the lean toward zero like a thumb. Returns the seconds it took to lock all steps, or -1.
func _play(qte: BalanceQte, skill: float, limit: float) -> float:
	var time: float = 0.0
	while qte.active and time < limit:
		qte.input = clampf(-qte.lean * skill, -1.0, 1.0)
		qte.update(DT)
		time += DT
	return time if not qte.active else -1.0


func _run() -> void:
	var tuning: Tuning = Tuning.new()
	var qte: BalanceQte = BalanceQte.new(tuning, 3)
	var passed: Array[int] = []
	qte.step_passed.connect(func(step: int) -> void: passed.append(step))
	qte.start(0)
	var time: float = _play(qte, 4.0, 15.0)
	_check(time > 0.0 and time < 15.0, "a scripted corrector locks all 3 steps in under 15 s (%.1f s)" % time)
	_check(passed == [0, 1, 2], "the steps pass in order")
	_check(time >= 3.0 * tuning.balance_hold_seconds, "each step needs the hold time")

	var idle: BalanceQte = BalanceQte.new(tuning, 3)
	var misses: Array[int] = [0]
	idle.missed.connect(func() -> void: misses[0] += 1)
	idle.start(0)
	var elapsed: float = 0.0
	while elapsed < 30.0 and idle.active:
		idle.update(DT)
		elapsed += DT
	_check(idle.active and idle.step < tuning.stack_size, "an idle player never finishes the build in 30 s")
	_check(misses[0] > 0, "an idle player drops the sandal")

	var fall: BalanceQte = BalanceQte.new(tuning, 5)
	fall.start(1)
	fall.grace_left = 0.0
	fall.lean = 0.99
	fall.input = 1.0
	fall.update(DT * 2.0)
	_check(fall.penalty_left > 0.0, "a lean of 1 starts the miss penalty")
	_check(fall.step == 1, "a fall never loses a step")
	_check(absf(fall.lean) <= 0.5, "the lean goes half way back after a fall")

	var tap: BalanceQte = BalanceQte.new(tuning, 5)
	tap.start(0)
	tap.lean = 0.6
	tap.tap()
	_check(is_equal_approx(tap.lean, 0.6 - tuning.balance_tap_nudge), "a tap nudges the lean toward the centre")
	tap.lean = -0.1
	tap.tap()
	_check(is_zero_approx(tap.lean), "a tap never crosses the centre")

	var first: BalanceQte = BalanceQte.new(tuning, 11)
	var second: BalanceQte = BalanceQte.new(tuning, 11)
	first.start(0)
	second.start(0)
	var same: bool = true
	for _i: int in 600:
		first.update(DT)
		second.update(DT)
		if first.lean != second.lean:
			same = false
	_check(same, "the same seed gives the same wobble")

	var late: BalanceQte = BalanceQte.new(tuning, 4)
	late.start(2)
	_check(late.step == 2 and late.active, "a builder who continues starts at a later step")
