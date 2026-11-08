extends SceneTree
## Headless test of both throw schemes and the settings.
##
## Run: godot --headless --path game --script res://tests/scheme_test.gd

var _failures: int = 0
var _tuning: Tuning
var _settings: Node



func _initialize() -> void:
	await _run()
	print("scheme_test: %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
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


func _spawn(arena: Arena, team: int, role: Character.Role, at: Vector2) -> Character:
	var character: Character = (load("res://scenes/character.tscn") as PackedScene).instantiate() as Character
	character.configure(team, role, _tuning)
	character.arena = arena
	character.stack = arena.stack
	character.position = at
	arena.add_child(character)
	arena.register_character(character)
	return character


func _give_sandal(arena: Arena, holder: Character, pass_sandal: bool) -> Sandal:
	var sandal: Sandal = Sandal.new()
	sandal.tuning = _tuning
	sandal.position = holder.position
	sandal.is_pass_sandal = pass_sandal
	arena.add_child(sandal)
	holder.pick_up(sandal)
	return sandal


func _new_arena() -> Arena:
	for child: Node in root.get_children():
		if child is Arena:
			root.remove_child(child)
			child.free()
	var arena: Arena = (load("res://scenes/arena.tscn") as PackedScene).instantiate() as Arena
	root.add_child(arena)
	return arena


func _run() -> void:
	_tuning = Tuning.load_default()
	_tuning.match_countdown = false
	_settings = root.get_node("Settings")
	await _test_tuning()
	await _test_attacker_lock_picks_the_stack()
	await _test_defender_default_lock()
	await _test_cone_and_hysteresis()
	await _test_cancel_fires_nothing()
	await _test_scheme_a_fires_along_the_drag()
	await _test_scheme_a_has_no_snap()
	await _test_scheme_a_tap_passes_to_nearest()
	await _test_blocked_lane()
	await _test_fire_button_layout()
	await _test_switching_keeps_the_round_running()
	await _test_settings_persist()


func _test_tuning() -> void:
	_check(_tuning.lock_cone_degrees == 40.0, "lock cone is 40 degrees")
	_check(_tuning.lock_hysteresis_degrees == 8.0, "lock hysteresis is 8 degrees")
	_check(_tuning.slop_px == 16.0, "slop is 16 px")
	_check(_tuning.fire_button_css_px >= 72.0, "fire button is at least 72 CSS px")
	_check(_tuning.fire_dash_gap_css_px >= 24.0, "fire to dash gap is at least 24 CSS px (WCAG 2.5.8)")
	_check(_tuning.get("pass_cone_degrees") == null, "pass_cone_degrees is retired")
	_check(_tuning.hit_power > 0.0 and _tuning.hit_power <= 1.0, "hit power is fixed and in range")
	await _frames(1)


func _test_attacker_lock_picks_the_stack() -> void:
	var arena: Arena = _new_arena()
	await _frames(2)
	var attacker: Character = _spawn(arena, 0, Character.Role.ATTACKER, arena.centre_spot + Vector2(-260.0, 0.0))
	_give_sandal(arena, attacker, false)
	var scheme: LockFireScheme = LockFireScheme.new()
	scheme.tuning = _tuning
	root.add_child(scheme)
	scheme.attach(attacker)
	_check(scheme.kind == ThrowScheme.TargetKind.STACK, "D: an attacker locks the stack")
	_check(scheme.locked == null, "D: the stack lock has no character")
	_check(scheme.candidates().is_empty(), "D: an attacker has no other targets")
	var moved: bool = scheme.steer_lock(Vector2.UP)
	_check(not moved and scheme.kind == ThrowScheme.TargetKind.STACK, "D: a drag does nothing for an attacker")
	var threw: Array[Sandal] = []
	attacker.threw.connect(func(sandal: Sandal) -> void: threw.append(sandal))
	_check(scheme.fire(), "D: fire throws the sandal")
	_check(threw.size() == 1, "D: one sandal left the hand")
	await _frames(2)
	var heading: Vector2 = threw[0].linear_velocity.normalized()
	var toward_stack: Vector2 = (arena.centre_spot - attacker.global_position).normalized()
	_check(heading.distance_to(toward_stack) < 0.05, "D: the throw flies at the stack")
	_check(not scheme.fire(), "D: a second fire with no sandal does nothing")
	scheme.queue_free()


func _test_defender_default_lock() -> void:
	var arena: Arena = _new_arena()
	await _frames(2)
	var holder: Character = _spawn(arena, 0, Character.Role.DEFENDER, arena.centre_spot + Vector2(0.0, 100.0))
	var mate: Character = _spawn(arena, 0, Character.Role.DEFENDER, arena.centre_spot + Vector2(100.0, 0.0))
	var near_foe: Character = _spawn(arena, 1, Character.Role.ATTACKER, arena.centre_spot + Vector2(-150.0, 20.0))
	var far_foe: Character = _spawn(arena, 1, Character.Role.ATTACKER, arena.centre_spot + Vector2(-300.0, -150.0))
	_give_sandal(arena, holder, true)
	var scheme: LockFireScheme = LockFireScheme.new()
	scheme.tuning = _tuning
	root.add_child(scheme)
	scheme.attach(holder)
	_check(scheme.candidates().size() == 3, "D: a defender can lock three characters, never itself")
	_check(scheme.candidates().find(holder) == -1, "D: the holder is not a candidate")
	_check(scheme.locked == near_foe, "D: the default lock is the nearest foe")
	var carrier: Sandal = _give_sandal(arena, far_foe, false)
	scheme.reset_lock()
	_check(scheme.locked == far_foe, "D: a foe carrying a sandal is locked before a nearer foe")
	far_foe.carried = null
	carrier.queue_free()
	near_foe.die()
	far_foe.die()
	scheme.reset_lock()
	_check(scheme.locked == mate and scheme.kind == ThrowScheme.TargetKind.FRIEND, "D: with no living foe the lock falls back to a teammate")
	mate.die()
	scheme.reset_lock()
	_check(scheme.kind == ThrowScheme.TargetKind.NONE, "D: with nobody to target the lock is empty")
	_check(not scheme.fire(), "D: an empty lock fires nothing")
	scheme.queue_free()


func _test_cone_and_hysteresis() -> void:
	var arena: Arena = _new_arena()
	await _frames(2)
	var origin: Vector2 = arena.centre_spot + Vector2(0.0, 150.0)
	var holder: Character = _spawn(arena, 0, Character.Role.DEFENDER, origin)
	var east: Character = _spawn(arena, 0, Character.Role.DEFENDER, origin + Vector2(200.0, 0.0))
	var north_east: Character = _spawn(arena, 1, Character.Role.ATTACKER, origin + Vector2.from_angle(deg_to_rad(-30.0)) * 200.0)
	var west: Character = _spawn(arena, 1, Character.Role.ATTACKER, origin + Vector2(-200.0, 0.0))
	_give_sandal(arena, holder, true)
	var scheme: LockFireScheme = LockFireScheme.new()
	scheme.tuning = _tuning
	root.add_child(scheme)
	scheme.attach(holder)
	_check(scheme.steer_lock(Vector2.RIGHT), "D: a drag right moves the lock")
	_check(scheme.locked == east, "D: a drag right picks the teammate to the east")
	_check(scheme.kind == ThrowScheme.TargetKind.FRIEND, "D: a teammate lock is a pass")
	var bearing_between: Vector2 = Vector2.from_angle(deg_to_rad(-15.0))
	scheme.steer_lock(bearing_between)
	_check(scheme.locked == east, "D: hysteresis keeps the lock when the new target wins by less than 8 degrees")
	var bearing_clear: Vector2 = Vector2.from_angle(deg_to_rad(-28.0))
	_check(scheme.steer_lock(bearing_clear), "D: a clearly better target takes the lock")
	_check(scheme.locked == north_east and scheme.kind == ThrowScheme.TargetKind.FOE, "D: a foe lock is a hit")
	var empty_bearing: Vector2 = Vector2.from_angle(deg_to_rad(120.0))
	_check(not scheme.steer_lock(empty_bearing), "D: a drag toward nobody leaves the lock")
	_check(scheme.locked == north_east, "D: the lock stays when no target is inside the cone")
	_check(scheme.locked != west, "D: a target outside the 40 degree cone is never picked")
	scheme.queue_free()


func _test_cancel_fires_nothing() -> void:
	var arena: Arena = _new_arena()
	await _frames(2)
	var attacker: Character = _spawn(arena, 0, Character.Role.ATTACKER, arena.centre_spot + Vector2(-260.0, 0.0))
	var sandal: Sandal = _give_sandal(arena, attacker, false)
	var scheme: LockFireScheme = LockFireScheme.new()
	scheme.tuning = _tuning
	root.add_child(scheme)
	var layer: Control = Control.new()
	root.add_child(layer)
	scheme.build_ui(layer)
	scheme.attach(attacker)
	var cancelled: Array[bool] = [false]
	scheme.cancelled.connect(func() -> void: cancelled[0] = true)
	var fired: Array[bool] = [false]
	scheme.fired.connect(func() -> void: fired[0] = true)
	scheme.button.pressed.emit()
	_check(scheme.previewing, "D: touch down shows the preview")
	scheme.button.cancelled.emit()
	_check(cancelled[0], "D: dragging back inside the slop cancels")
	_check(not fired[0], "D: a cancel fires nothing")
	_check(attacker.carried == sandal, "D: the sandal stays in the hand after a cancel")
	_check(not scheme.previewing, "D: a cancel hides the preview")
	scheme.button.pressed.emit()
	scheme.button.released.emit()
	_check(fired[0] and attacker.carried == null, "D: a tap releases and fires")
	scheme.teardown()
	scheme.queue_free()
	layer.queue_free()


func _test_scheme_a_fires_along_the_drag() -> void:
	var arena: Arena = _new_arena()
	await _frames(2)
	var attacker: Character = _spawn(arena, 0, Character.Role.ATTACKER, arena.centre_spot + Vector2(-260.0, 0.0))
	_give_sandal(arena, attacker, false)
	var scheme: AimStickScheme = AimStickScheme.new()
	scheme.tuning = _tuning
	root.add_child(scheme)
	scheme.attach(attacker)
	var threw: Array[Sandal] = []
	attacker.threw.connect(func(sandal: Sandal) -> void: threw.append(sandal))
	var drag: Vector2 = Vector2.from_angle(deg_to_rad(20.0))
	scheme.apply_aim(drag, 0.5)
	_check(scheme.previewing, "A: a drag shows the preview")
	_check(scheme.aim_bearing().distance_to(drag) < 0.001, "A: the aim points where the thumb points, not reversed")
	_check(is_equal_approx(scheme.aim_power(), 0.5), "A: the drag length sets the power")
	var flight: Dictionary = scheme.flight_for(drag, 0.5)
	var expected_length: float = _tuning.max_throw_range * 0.5 - (_tuning.character_radius + 12.0)
	_check(absf((flight["end"] as Vector2).distance_to(flight["start"] as Vector2) - expected_length) < 1.0, "A: the preview line is as long as the throw")
	_check(scheme.fire_aim(), "A: release fires")
	await _frames(2)
	_check(threw.size() == 1, "A: one sandal left the hand")
	_check(threw[0].linear_velocity.normalized().distance_to(drag) < 0.05, "A: the throw flies along the drag direction")
	await _frames(90)
	var travelled: float = threw[0].global_position.distance_to(flight["start"] as Vector2)
	_check(absf(travelled - expected_length) < 12.0, "A: half power flies half the range (%.0f of %.0f px)" % [travelled, expected_length])
	_check(not scheme.previewing, "A: firing hides the preview")
	_check(not scheme.draws_target_preview(), "A: the shared lock preview never draws")
	scheme.apply_aim(Vector2.ZERO)
	_check(not scheme.fire_aim(), "A: no aim fires nothing")
	scheme.queue_free()


func _test_scheme_a_has_no_snap() -> void:
	var arena: Arena = _new_arena()
	await _frames(2)
	var origin: Vector2 = arena.centre_spot + Vector2(0.0, 150.0)
	var holder: Character = _spawn(arena, 0, Character.Role.DEFENDER, origin)
	var mate: Character = _spawn(arena, 0, Character.Role.DEFENDER, origin + Vector2(200.0, 0.0))
	var foe: Character = _spawn(arena, 1, Character.Role.ATTACKER, origin + Vector2(-200.0, 0.0))
	_give_sandal(arena, holder, true)
	var scheme: AimStickScheme = AimStickScheme.new()
	scheme.tuning = _tuning
	root.add_child(scheme)
	scheme.attach(holder)
	var near_mate: Vector2 = Vector2.RIGHT.rotated(deg_to_rad(10.0))
	scheme.apply_aim(near_mate, 1.0)
	_check(scheme.locked == null and scheme.kind == ThrowScheme.TargetKind.NONE, "A: aiming near a teammate locks nothing")
	var hit: Dictionary = scheme.flight_for(Vector2.LEFT, 1.0)
	_check(hit["hit"] == foe, "A: the preview line stops at the first character it touches")
	var miss: Dictionary = scheme.flight_for(Vector2.UP, 1.0)
	_check(miss["hit"] == null, "A: a line at nobody hits nobody")
	var thrown: Array[Sandal] = []
	holder.threw.connect(func(sandal: Sandal) -> void: thrown.append(sandal))
	scheme.apply_aim(near_mate, 1.0)
	_check(scheme.fire_aim(), "A: release throws by hand")
	_check(thrown.size() == 1 and thrown[0].linear_velocity.normalized().distance_to(near_mate) < 0.01, "A: the sandal flies exactly along the thumb, no snap to the teammate")
	_check(mate.carried == null, "A: a manual throw at a teammate is not caught on release")
	scheme.queue_free()


func _test_scheme_a_tap_passes_to_nearest() -> void:
	var arena: Arena = _new_arena()
	await _frames(2)
	var origin: Vector2 = arena.centre_spot + Vector2(0.0, 150.0)
	var holder: Character = _spawn(arena, 0, Character.Role.DEFENDER, origin)
	var far_mate: Character = _spawn(arena, 0, Character.Role.DEFENDER, origin + Vector2(250.0, 0.0))
	var near_mate: Character = _spawn(arena, 0, Character.Role.DEFENDER, origin + Vector2(-120.0, 0.0))
	_spawn(arena, 1, Character.Role.ATTACKER, origin + Vector2(60.0, 0.0))
	_give_sandal(arena, holder, true)
	var scheme: AimStickScheme = AimStickScheme.new()
	scheme.tuning = _tuning
	root.add_child(scheme)
	scheme.attach(holder)
	var passed_to: Array[Character] = []
	holder.passed.connect(func(receiver: Character) -> void: passed_to.append(receiver))
	_check(scheme.tap(), "A: a tap passes")
	_check(passed_to.size() == 1 and passed_to[0] == near_mate, "A: a tap passes to the nearest living teammate")
	_check(far_mate.carried == null, "A: a tap does not pick the far teammate")
	scheme.queue_free()
	var attacker: Character = _spawn(arena, 0, Character.Role.ATTACKER, arena.centre_spot + Vector2(-260.0, 0.0))
	_give_sandal(arena, attacker, false)
	var attack_scheme: AimStickScheme = AimStickScheme.new()
	attack_scheme.tuning = _tuning
	root.add_child(attack_scheme)
	attack_scheme.attach(attacker)
	var threw: Array[Sandal] = []
	attacker.threw.connect(func(sandal: Sandal) -> void: threw.append(sandal))
	_check(attack_scheme.tap(), "A: an attacker tap throws")
	_check(threw.size() == 1 and threw[0].linear_velocity.normalized().distance_to(Vector2.RIGHT) < 0.02, "A: an attacker tap throws at the stack")
	attack_scheme.queue_free()


func _test_blocked_lane() -> void:
	var arena: Arena = _new_arena()
	await _frames(2)
	var origin: Vector2 = arena.centre_spot + Vector2(0.0, 150.0)
	var holder: Character = _spawn(arena, 0, Character.Role.DEFENDER, origin)
	var mate: Character = _spawn(arena, 0, Character.Role.DEFENDER, origin + Vector2(300.0, 0.0))
	var blocker: Character = _spawn(arena, 1, Character.Role.ATTACKER, origin + Vector2(150.0, 4.0))
	_give_sandal(arena, holder, true)
	var scheme: LockFireScheme = LockFireScheme.new()
	scheme.tuning = _tuning
	root.add_child(scheme)
	scheme.attach(holder)
	# The foe sits on the line and is nearer to the bearing, so the player aims slightly above it to pick the teammate.
	scheme._set_lock(mate, ThrowScheme.TargetKind.FRIEND)
	_check(scheme.locked == mate, "preview: the pass is locked on the teammate")
	_check(scheme.is_lane_blocked(), "preview: a foe on the line marks the lane blocked")
	blocker.global_position = origin + Vector2(150.0, 120.0)
	_check(not scheme.is_lane_blocked(), "preview: a clear lane is not marked blocked")
	_check(scheme.preview_color().is_equal_approx(_tuning.friendly_color), "preview: a pass ring is friend blue")
	scheme.steer_lock(Vector2.LEFT)
	scheme.queue_free()


func _test_fire_button_layout() -> void:
	var arena: Arena = _new_arena()
	await _frames(2)
	for size: Vector2i in [Vector2i(844, 390), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = size
		await _frames(2)
		var layer: Control = Control.new()
		root.add_child(layer)
		var button: FireButton = FireButton.new()
		button.tuning = _tuning
		layer.add_child(button)
		var dash: DashButton = DashButton.new()
		layer.add_child(dash)
		button.layout()
		var per_css: float = RestartUiScale.pixels_per_css(root)
		var gap: float = button.gap_to(root.get_visible_rect().size - dash.edge_margin, dash.radius)
		_check(gap >= 24.0 * per_css - 0.5, "fire button keeps 24 CSS px from the dash button at %dx%d (gap %.1f px)" % [size.x, size.y, gap])
		_check(button.hit_radius() * 2.0 >= _tuning.fire_button_css_px * per_css - 0.5, "fire button is at least 72 CSS px at %dx%d" % [size.x, size.y])
		layer.queue_free()
		await _frames(1)
	var gear_layer: SettingsLayer = SettingsLayer.new()
	root.add_child(gear_layer)
	await _frames(2)
	var restart: RestartButton = RestartButton.new()
	root.add_child(restart)
	await _frames(2)
	var arena_rect: Rect2 = RestartUiScale.arena_rect(root)
	var gear: Dictionary = gear_layer.gear_hit()
	var gear_centre: Vector2 = gear["centre"]
	var gear_radius: float = gear["radius"]
	_check(gear_centre.x + gear_radius <= arena_rect.end.x + 0.5, "the gear sits inside the arena border")
	_check(restart.hit_centre().x + restart.hit_radius() <= arena_rect.end.x + 0.5, "the restart ring sits inside the arena border")
	_check(restart.hit_centre().distance_to(gear_centre) >= restart.hit_radius() + gear_radius, "the gear and the restart ring do not overlap")
	gear_layer.queue_free()
	restart.queue_free()
	arena.queue_free()


func _test_switching_keeps_the_round_running() -> void:
	for child: Node in root.get_children():
		if child is Arena:
			root.remove_child(child)
			child.free()
	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	await _frames(30)
	var manager: RoundManager = scene.get_node("RoundManager") as RoundManager
	var human: HumanController = manager.human
	_check(human.scheme != null, "the human has a scheme after the scene loads")
	_check(human.scheme is LockFireScheme, "scheme D is the default")
	var holder: Character = human.character
	var phase_before: int = manager.phase
	_settings.set_scheme(SettingsRef.SCHEME_AIM_STICK)
	await _frames(3)
	_check(human.scheme is AimStickScheme, "the setting swaps to scheme A at once")
	_check(human.character == holder, "the human keeps the same character after a swap")
	_check(manager.phase == phase_before or manager.phase != RoundManager.MATCH_END, "the round keeps running after a swap")
	_check(human.scheme.character == holder, "the new scheme controls the same character")
	_settings.set_scheme(SettingsRef.SCHEME_LOCK_FIRE)
	await _frames(3)
	_check(human.scheme is LockFireScheme, "the setting swaps back to scheme D")
	var schemes_in_arena: int = 0
	for node: Node in manager.arena.get_children():
		if node is ThrowScheme:
			schemes_in_arena += 1
	var schemes_under_human: int = 0
	for node: Node in human.get_children():
		if node is ThrowScheme:
			schemes_under_human += 1
	_check(schemes_in_arena + schemes_under_human == 1, "exactly one scheme node exists after two swaps")
	await _frames(150)
	_check(manager.phase != RoundManager.COIN_FLIP, "the round advances after swaps")
	scene.queue_free()
	await _frames(2)


func _test_settings_persist() -> void:
	var scratch: String = "user://scheme_test_settings.cfg"
	var first: Node = load("res://autoload/settings.gd").new()
	first.path = scratch
	first.scheme = SettingsRef.SCHEME_AIM_STICK
	first.haptics_enabled = false
	_check(first.save_settings() == OK, "settings save to disk")
	var second: Node = load("res://autoload/settings.gd").new()
	second.path = scratch
	second.load_settings()
	_check(second.scheme == SettingsRef.SCHEME_AIM_STICK, "the scheme survives a reload")
	_check(not second.haptics_enabled, "the haptics choice survives a reload")
	var broken: Node = load("res://autoload/settings.gd").new()
	broken.path = "user://does_not_exist.cfg"
	broken.load_settings()
	_check(broken.scheme == SettingsRef.SCHEME_LOCK_FIRE, "a missing file keeps scheme D")
	var junk: ConfigFile = ConfigFile.new()
	junk.set_value("controls", "scheme", 99)
	junk.save("user://scheme_test_junk.cfg")
	var bad: Node = load("res://autoload/settings.gd").new()
	bad.path = "user://scheme_test_junk.cfg"
	bad.load_settings()
	_check(bad.scheme == SettingsRef.SCHEME_LOCK_FIRE, "an unknown scheme value falls back to scheme D")
	DirAccess.remove_absolute(scratch)
	DirAccess.remove_absolute("user://scheme_test_junk.cfg")
	first.free()
	second.free()
	broken.free()
	bad.free()
