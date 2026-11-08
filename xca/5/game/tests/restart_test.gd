extends SceneTree
## Headless test of the match restart: hold, tap, key, match-end overlay, and state after a reload.
##
## It loads the real main scene, drives the restart controls with real input events, and runs the
## whole cycle twice in one process so a leak from the first restart shows in the second.
## Run: godot --headless --path game --script res://tests/restart_test.gd

const MAIN_SCENE: String = "res://scenes/main.tscn"
const CYCLES: int = 2
const SETTLE_FRAMES: int = 6
const ROUND_END_FRAMES: int = 240
const MATCH_END_LIMIT_FRAMES: int = 3000
const HOLD_SECONDS: float = 1.1
const PARTIAL_HOLD_SECONDS: float = 0.3
const KEY_R_CODE: Key = KEY_R

var _failures: int = 0
var _checks: int = 0
var _orphans_after: Array[int] = []


func _initialize() -> void:
	_run()


func _run() -> void:
	for cycle: int in CYCLES:
		print("cycle %d" % [cycle + 1])
		await _run_cycle()
	_check(_orphans_after.size() == CYCLES, "orphan counts recorded for every cycle")
	if _orphans_after.size() == CYCLES:
		_check(_orphans_after[1] <= _orphans_after[0], "orphan nodes do not grow between cycles (%s)" % str(_orphans_after))
	print("restart_test: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("  ok   ", label)
	else:
		_failures += 1
		printerr("FAIL: " + label)


func _frames(count: int) -> void:
	for _i: int in count:
		await physics_frame


func _real_seconds(seconds: float) -> void:
	await create_timer(seconds, true, false, true).timeout


func _scene() -> Node:
	return current_scene


func _manager() -> RoundManager:
	return current_scene.get_node("RoundManager") as RoundManager


func _button() -> RestartButton:
	return current_scene.get_node("Restart/RestartButton") as RestartButton


func _overlay() -> MatchEndOverlay:
	return current_scene.get_node("Restart/MatchEndOverlay") as MatchEndOverlay


func _load_match() -> void:
	if current_scene != null:
		current_scene.queue_free()
		await _frames(2)
	var packed: PackedScene = load(MAIN_SCENE) as PackedScene
	var main: Node = packed.instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(SETTLE_FRAMES)


func _touch(index: int, position: Vector2, pressed: bool) -> void:
	var event: InputEventScreenTouch = InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = pressed
	root.push_input(event, true)
	await physics_frame


func _tap(position: Vector2) -> void:
	await _touch(0, position, true)
	await _touch(0, position, false)


func _key(code: Key, pressed: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	root.push_input(event, true)
	await physics_frame


func _assert_clean_match(label: String, previous: Variant) -> void:
	var manager: RoundManager = _manager()
	_check(previous == null or not is_instance_valid(previous), "%s: the old match scene is freed" % label)
	_check(manager.phase == RoundManager.COIN_FLIP, "%s: phase is COIN_FLIP (got %d)" % [label, manager.phase])
	_check(manager.scores == [0, 0], "%s: scores are zero (got %s)" % [label, str(manager.scores)])
	var arena: Arena = manager.arena
	var characters: int = arena.get_characters(0).size() + arena.get_characters(1).size()
	_check(characters == 6, "%s: 6 characters exist (got %d)" % [label, characters])
	_check(arena.stack.standing_sandals.size() == 3, "%s: the stack stands with 3 sandals" % label)
	_check(not arena.stack.is_down, "%s: the stack is not down" % label)
	_check(get_nodes_in_group(Sandal.GROUP).size() == 3, "%s: only the 3 stack sandals exist (got %d)" % [label, get_nodes_in_group(Sandal.GROUP).size()])
	_check(is_equal_approx(Engine.time_scale, 1.0), "%s: time scale is 1.0 (got %f)" % [label, Engine.time_scale])
	_check(get_nodes_in_group(RoundManager.HUMAN_GROUP).size() == 1, "%s: exactly one human character (got %d)" % [label, get_nodes_in_group(RoundManager.HUMAN_GROUP).size()])
	_check(get_nodes_in_group(Hud.GROUP_HUD).size() == 1, "%s: exactly one HUD (got %d)" % [label, get_nodes_in_group(Hud.GROUP_HUD).size()])
	_check(_button().visible and not _overlay().visible, "%s: the restart button shows and the overlay is hidden" % label)


func _run_cycle() -> void:
	await _load_match()
	_assert_clean_match("fresh load", null)

	# A quick tap must not restart.
	var first_scene: Node = _scene()
	var button: RestartButton = _button()
	var centre: Vector2 = button.hit_centre()
	_check(button.hit_radius() >= 22.0, "button radius is at least 22 viewport pixels (got %.1f)" % button.hit_radius())
	_check(centre.x > get_root().get_visible_rect().size.x * 0.5 and centre.y < get_root().get_visible_rect().size.y * 0.5, "button sits in the top right quarter")
	await _tap(centre)
	await _frames(SETTLE_FRAMES)
	_check(_scene() == first_scene and is_instance_valid(first_scene), "a quick tap does not restart")

	# A partial hold fills the ring and a release resets it.
	_manager().scores = [2, 1]
	await _touch(0, centre, true)
	await _real_seconds(PARTIAL_HOLD_SECONDS)
	await _frames(2)
	_check(_button().progress > 0.1 and _button().progress < 0.9, "the ring fills while held (progress %.2f)" % _button().progress)
	await _touch(0, centre, false)
	await _frames(2)
	_check(is_equal_approx(_button().progress, 0.0), "the ring resets on release")
	_check(_scene() == first_scene, "a partial hold does not restart")

	# A full hold restarts and the new match is clean even after score, slow-motion and a thrown sandal.
	_manager().end_round(0)
	Engine.time_scale = 0.3
	await _frames(2)
	_check(_manager().scores[0] >= 1, "the score changed before the restart")
	await _touch(0, centre, true)
	await _real_seconds(HOLD_SECONDS)
	await _frames(SETTLE_FRAMES)
	await _touch(0, centre, false)
	await _frames(SETTLE_FRAMES)
	_assert_clean_match("after a hold", first_scene)

	# The R key restarts after a hold.
	var second_scene: Node = _scene()
	_manager().end_round(1)
	await _key(KEY_R_CODE, true)
	await _real_seconds(HOLD_SECONDS)
	await _frames(SETTLE_FRAMES)
	await _key(KEY_R_CODE, false)
	await _frames(SETTLE_FRAMES)
	_assert_clean_match("after holding R", second_scene)

	# Play to the match end, check the overlay, and restart with a single tap.
	var third_scene: Node = _scene()
	var manager: RoundManager = _manager()
	var guard: int = 0
	while manager.phase != RoundManager.MATCH_END and guard < MATCH_END_LIMIT_FRAMES:
		if manager.phase != RoundManager.ROUND_END and manager.scores[0] < manager.tuning.rounds_to_win:
			manager.end_round(0)
		await _frames(1)
		guard += 1
	_check(manager.phase == RoundManager.MATCH_END, "the match reaches MATCH_END (frames %d)" % guard)
	await _frames(SETTLE_FRAMES)
	var overlay: MatchEndOverlay = _overlay()
	_check(overlay.visible, "the match-end overlay shows")
	_check(not _button().visible, "the hold button hides while the overlay shows")
	_check(overlay.button_radius() >= 32.0, "the overlay button radius is at least 32 viewport pixels (got %.1f)" % overlay.button_radius())
	var overlay_centre: Vector2 = overlay.button_centre()
	await _tap(overlay_centre)
	await _frames(SETTLE_FRAMES)
	_assert_clean_match("after the overlay tap", third_scene)

	# A touch outside the overlay button must not restart.
	var fourth_scene: Node = _scene()
	_manager().scores = [3, 0]
	_manager().phase_changed.emit(RoundManager.MATCH_END)
	_manager().match_ended.emit(0)
	await _frames(SETTLE_FRAMES)
	_check(_overlay().visible, "the overlay shows again on a forced match end")
	await _tap(Vector2(40.0, 300.0))
	await _frames(SETTLE_FRAMES)
	_check(_scene() == fourth_scene, "a tap outside the overlay button does not restart")

	await _frames(SETTLE_FRAMES)
	current_scene.queue_free()
	await _frames(SETTLE_FRAMES)
	current_scene = null
	Engine.time_scale = 1.0
	_orphans_after.append(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)))
