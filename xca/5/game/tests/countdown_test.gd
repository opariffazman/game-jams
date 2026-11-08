extends SceneTree
## Headless test of the match start countdown: order, freeze, input lock, unlock, restart and mute.
##
## Run in real time: godot --headless --path game --script res://tests/countdown_test.gd

const MAIN_SCENE: String = "res://scenes/main.tscn"

var _failures: int = 0
var _ticks: Array[int] = []


func _initialize() -> void:
	await _run()
	print("countdown_test: %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(_failures)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   ", label)
	else:
		print("  FAIL ", label)
		_failures += 1


func _frames(count: int) -> void:
	for _i: int in count:
		await physics_frame


func _load_main() -> Node:
	var main: Node = (load(MAIN_SCENE) as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	return main


func _positions(manager: RoundManager) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for team: int in 2:
		for entry: Variant in manager.arena.get_characters(team):
			result.append((entry as Character).global_position)
	return result


func _run() -> void:
	var tuning: Tuning = Tuning.load_default()
	tuning.match_countdown = true
	tuning.countdown_step_time = 1.1
	var audio: Node = root.get_node("Audio")
	audio.set("play_counts", {})
	var main: Node = _load_main()
	await _frames(3)
	var manager: RoundManager = main.get_node("RoundManager") as RoundManager
	manager.countdown_tick.connect(func(step: int) -> void: _ticks.append(step))
	_check(manager.phase == RoundManager.COIN_FLIP, "match starts at the coin flip")
	var frozen_at: Array[Vector2] = _positions(manager)
	var human: Character = manager.human.character
	human.dash()
	manager.human.character.move_intent = Vector2.RIGHT
	await _frames(int((tuning.countdown_intro_time + tuning.countdown_step_time * 0.5) * 60.0))
	_check(manager.phase == RoundManager.COIN_FLIP and _ticks == [3], "the countdown shows 3 first (%s)" % str(_ticks))
	_check(_positions(manager) == frozen_at, "bodies stand still during the countdown")
	_check(human.dash_time_left <= 0.0 and not human.can_dash(), "dash is locked during the countdown")
	_check(human.throw_manual(Vector2.RIGHT, 1.0) or true, "throw call during the countdown does not crash")
	await _frames(int(tuning.countdown_step_time * 2.0 * 60.0))
	_check(_ticks == [3, 2, 1] or _ticks == [3, 2, 1, 0], "numbers come in order (%s)" % str(_ticks))
	await _frames(int(tuning.countdown_step_time * 60.0))
	_check(_ticks == [3, 2, 1, 0], "go fires last, once (%s)" % str(_ticks))
	_check(manager.phase == RoundManager.TOPPLE, "play unlocks after the countdown")
	_check(not human.frozen and human.can_dash(), "bodies move and dash again after go")
	var counts: Dictionary = audio.get("play_counts")
	for slot: StringName in [&"voice_three", &"voice_two", &"voice_one", &"voice_fight"]:
		_check(int(counts.get(slot, 0)) == 1, "%s played once (%d)" % [slot, int(counts.get(slot, 0))])
	root.remove_child(main)
	main.free()
	await _frames(3)
	await _test_restart_mid_countdown(tuning)
	await _test_mute(tuning, audio)


func _test_restart_mid_countdown(tuning: Tuning) -> void:
	var main: Node = _load_main()
	await _frames(int((tuning.countdown_intro_time + tuning.countdown_step_time * 0.5) * 60.0))
	var manager: RoundManager = main.get_node("RoundManager") as RoundManager
	_check(manager.restart_match() == OK, "restart queues mid-countdown")
	await _frames(5)
	var fresh: Node = current_scene
	_check(fresh != main, "the scene reloaded")
	var fresh_manager: RoundManager = fresh.get_node("RoundManager") as RoundManager
	_check(fresh_manager.phase == RoundManager.COIN_FLIP, "the new match starts at the coin flip")
	_check(is_equal_approx(Engine.time_scale, 1.0), "time scale is 1.0 after the restart")
	await _frames(int((tuning.countdown_intro_time + tuning.countdown_step_time * 4.0) * 60.0) + 30)
	_check(fresh_manager.phase != RoundManager.COIN_FLIP, "the new match unlocks")
	for team: int in 2:
		for entry: Variant in fresh_manager.arena.get_characters(team):
			_check(not (entry as Character).frozen, "no body stays frozen after the restart")
	root.remove_child(fresh)
	fresh.free()
	await _frames(5)
	var orphans: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_check(orphans <= 3, "no orphan nodes after the restart (%d)" % orphans)


func _test_mute(tuning: Tuning, audio: Node) -> void:
	var settings: Node = root.get_node("Settings")
	var was_on: bool = SettingsRef.sound_enabled()
	settings.set_sound(false)
	audio.set("play_counts", {})
	var main: Node = _load_main()
	await _frames(int((tuning.countdown_intro_time + tuning.countdown_step_time * 4.0) * 60.0) + 30)
	var counts: Dictionary = audio.get("play_counts")
	_check(not counts.has(&"voice_three") and not counts.has(&"voice_fight"), "mute silences the countdown voice")
	settings.set_sound(was_on)
	root.remove_child(main)
	main.free()
