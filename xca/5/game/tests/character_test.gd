extends SceneTree
## Headless test for [Character]. Run through [code]tests/run_character_test.sh[/code].

const STEP: float = 1.0 / 60.0

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	_run_all()


func _run_all() -> void:
	await _test_movement()
	await _test_dash_cooldown()
	await _test_die()
	await _test_carry_and_throw()
	await _test_pass()
	await _test_lead_direction()
	await _test_hit()
	await _test_ring_movement()
	await _test_hero_power()
	_test_joystick()
	_test_hidden_button_ignores_touch()
	_test_stale_finger_recovers()
	print("character_test: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: " + label)


func _clear() -> void:
	for node: Node in root.get_children():
		root.remove_child(node)
		node.free()


func _spawn(team: int, role: Character.Role, at: Vector2) -> Character:
	var scene: PackedScene = load("res://scenes/character.tscn")
	var body: Character = scene.instantiate() as Character
	body.configure(team, role, Tuning.new())
	body.position = at
	root.add_child(body)
	return body


func _spawn_sandal(at: Vector2) -> Sandal:
	var sandal: Sandal = Sandal.new()
	sandal.gravity_scale = 0.0
	sandal.collision_layer = 4
	sandal.collision_mask = 1
	var shape: CollisionShape2D = CollisionShape2D.new()
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = 8.0
	shape.shape = circle
	sandal.add_child(shape)
	sandal.position = at
	root.add_child(sandal)
	return sandal


func _step(frames: int) -> void:
	for _i: int in frames:
		await physics_frame


func _test_movement() -> void:
	_clear()
	var body: Character = _spawn(0, Character.Role.ATTACKER, Vector2(100.0, 100.0))
	await _step(2)
	var start: Vector2 = body.global_position
	body.move_intent = Vector2.RIGHT
	await _step(30)
	_check(body.global_position.x > start.x + 50.0, "moves right with intent")
	_check(absf(body.global_position.y - start.y) < 1.0, "does not drift on y")
	_check(body.visual != null, "attacker has a visual child")
	body.move_intent = Vector2.ZERO
	await _step(2)
	var rest: Vector2 = body.global_position
	await _step(10)
	_check(body.global_position.distance_to(rest) < 0.5, "stops without intent")
	var attacker_visual: EntityVisual = body.visual
	body.role = Character.Role.DEFENDER
	await _step(2)
	_check(body.visual != attacker_visual and body.visual != null, "role change rebuilds the visual")


func _test_dash_cooldown() -> void:
	_clear()
	var body: Character = _spawn(0, Character.Role.ATTACKER, Vector2(100.0, 100.0))
	await _step(2)
	body.move_intent = Vector2.RIGHT
	_check(body.can_dash(), "can dash at start")
	_check(body.dash(), "first dash starts")
	_check(body.is_invulnerable(), "invulnerable while dashing")
	_check(not body.dash(), "second dash refused during window")
	await _step(30)
	_check(not body.is_invulnerable(), "window closes")
	_check(not body.can_dash(), "cooldown still running after window")
	_check(not body.dash(), "dash refused on cooldown")
	_check(body.dash_cooldown_ratio() > 0.0, "cooldown ratio above zero")
	await _step(120)
	_check(body.can_dash(), "dash ready after cooldown")
	_check(is_equal_approx(body.dash_cooldown_ratio(), 0.0), "cooldown ratio zero when ready")


func _test_die() -> void:
	_clear()
	var body: Character = _spawn(0, Character.Role.ATTACKER, Vector2(100.0, 100.0))
	await _step(2)
	var deaths: Array[int] = [0]
	body.died.connect(func() -> void: deaths[0] += 1)
	body.move_intent = Vector2.RIGHT
	body.dash()
	body.die()
	_check(body.alive, "die is ignored while invulnerable")
	await _step(30)
	body.die()
	_check(not body.alive, "die sets alive false")
	_check(deaths[0] == 1, "died emitted once")
	body.die()
	_check(deaths[0] == 1, "second die does nothing")
	await _step(2)
	_check(body.visual != null, "tombstone visual present")
	var rest: Vector2 = body.global_position
	body.move_intent = Vector2.RIGHT
	await _step(10)
	_check(body.global_position.distance_to(rest) < 0.5, "dead body does not move")


func _test_carry_and_throw() -> void:
	_clear()
	var body: Character = _spawn(0, Character.Role.ATTACKER, Vector2(200.0, 200.0))
	var sandal: Sandal = _spawn_sandal(Vector2(400.0, 400.0))
	await _step(2)
	_check(body.pick_up(sandal), "pick_up takes a free sandal")
	_check(body.carried == sandal, "carried is set")
	_check(not body.pick_up(sandal), "second pick_up refused with full hands")
	body.move_intent = Vector2.RIGHT
	await _step(30)
	var carry_distance: float = body.global_position.x - 200.0
	_check(carry_distance > 20.0 and carry_distance < 230.0 * 0.6 * 0.6, "carrying slows the body")
	_check(sandal.global_position.distance_to(body.global_position) < 40.0, "sandal follows the carrier")
	body.move_intent = Vector2.ZERO
	_check(body.throw_sandal(Vector2.RIGHT, 0.1), "throw_sandal returns true")
	_check(is_equal_approx(sandal.last_range, 260.0 - (18.0 + 12.0)), "attacker throw has a fixed range, power ignored")
	_check(body.carried == null, "hands empty after throw")
	_check(sandal.in_flight, "sandal in flight after throw")
	_check(not body.throw_sandal(Vector2.RIGHT, 1.0), "throw with empty hands returns false")
	var manual_sandal: Sandal = _spawn_sandal(body.global_position)
	body.pick_up(manual_sandal)
	_check(body.throw_manual(Vector2.RIGHT, 0.5), "throw_manual returns true")
	_check(is_equal_approx(manual_sandal.last_range, 340.0 * 0.5 - (18.0 + 12.0)), "manual throw range follows power")
	_check(not body.throw_manual(Vector2.RIGHT, 1.0), "manual throw with empty hands returns false")
	var defender: Character = _spawn(1, Character.Role.DEFENDER, Vector2(600.0, 200.0))
	var defender_sandal: Sandal = _spawn_sandal(Vector2(700.0, 400.0))
	await _step(2)
	defender.pick_up(defender_sandal)
	defender.throw_sandal(Vector2.RIGHT, 0.5)
	_check(is_equal_approx(defender_sandal.linear_velocity.length(), 450.0) or defender_sandal.last_range < 0.0, "defender throw keeps power")


func _test_ring_movement() -> void:
	_clear()
	var centre: Vector2 = Vector2(400.0, 300.0)
	var attacker: Character = _spawn(0, Character.Role.ATTACKER, centre + Vector2(-260.0, 0.0))
	attacker.hold_on_ring(centre, 260.0, 230.0)
	var defender: Character = _spawn(1, Character.Role.DEFENDER, centre + Vector2(0.0, 100.0))
	defender.hold_on_ring(centre, 100.0, 100.0, true)
	await _step(2)
	attacker.move_intent = Vector2.RIGHT
	await _step(60)
	_check(absf(attacker.global_position.distance_to(centre) - 260.0) < 1.0, "ring attacker never steps off the ring")
	_check(attacker.global_position.x < centre.x - 200.0, "ring attacker pushed toward the stack stays outside it")
	attacker.move_intent = Vector2.DOWN
	var before: Vector2 = attacker.global_position
	await _step(30)
	_check(attacker.global_position.distance_to(before) > 20.0, "ring attacker moves along the ring")
	attacker.move_intent = Vector2.ZERO
	var rest: Vector2 = attacker.global_position
	await _step(10)
	_check(attacker.global_position.distance_to(rest) < 0.5, "ring attacker holds still with no input")
	var start_angle: float = (defender.global_position - centre).angle()
	await _step(60)
	var turned: float = absf(angle_difference(start_angle, (defender.global_position - centre).angle()))
	_check(turned > 0.5, "auto ring defender circles on its own")
	_check(absf(defender.global_position.distance_to(centre) - 100.0) < 1.0, "auto ring defender stays on its radius")
	var direction_before: float = defender.ring_direction
	defender.move_intent = Vector2.LEFT
	await _step(2)
	_check(defender.ring_direction == -direction_before, "stick left or right flips the spin direction")
	defender.move_intent = Vector2.UP
	var radius_before: float = defender.global_position.distance_to(centre)
	await _step(30)
	_check(absf(defender.global_position.distance_to(centre) - radius_before) < 1.0, "pushing toward the stack never leaves the orbit ring")
	attacker.hold_on_ring(centre, 0.0, 0.0)
	attacker.move_intent = Vector2.RIGHT
	await _step(30)
	_check(attacker.global_position.distance_to(centre) < 250.0, "a released ring lets the body walk freely")


func _test_pass() -> void:
	_clear()
	var arena: Arena = Arena.new()
	root.add_child(arena)
	var holder: Character = _spawn(0, Character.Role.DEFENDER, Vector2(100.0, 300.0))
	var mate: Character = _spawn(0, Character.Role.DEFENDER, Vector2(500.0, 300.0))
	var foe: Character = _spawn(1, Character.Role.ATTACKER, Vector2(300.0, 310.0))
	for member: Character in [holder, mate, foe]:
		arena.register_character(member)
	holder.arena = arena
	var sandal: Sandal = _spawn_sandal(Vector2(100.0, 300.0))
	sandal.is_pass_sandal = true
	await _step(2)
	holder.pick_up(sandal)
	var passed_to: Array[Character] = []
	holder.passed.connect(func(receiver: Character) -> void: passed_to.append(receiver))
	_check(holder.pass_to(mate), "defender pass_to returns true")
	_check(passed_to.size() == 1 and passed_to[0] == mate, "pass goes to the chosen teammate")
	_check(absf(sandal.linear_velocity.y) > 1.0, "pass bends around the attacker in the way")
	await _step(240)
	_check(mate.carried == sandal, "receiver catches the passed sandal")


func _test_lead_direction() -> void:
	_clear()
	var thrower: Character = _spawn(0, Character.Role.DEFENDER, Vector2(100.0, 300.0))
	var runner: Character = _spawn(1, Character.Role.ATTACKER, Vector2(500.0, 300.0))
	await _step(2)
	runner.velocity = Vector2(0.0, -200.0)
	var lead: Vector2 = thrower.lead_direction(runner, 1.0)
	var direct: Vector2 = (runner.global_position - thrower.global_position).normalized()
	_check(lead.y < direct.y - 0.01, "lead aims ahead of a moving target")
	runner.velocity = Vector2.ZERO
	_check(thrower.lead_direction(runner, 1.0).distance_to(direct) < 0.001, "no lead for a still target")


func _test_joystick() -> void:
	_clear()
	root.size = Vector2i(1280, 720)
	var stick: VirtualJoystick = VirtualJoystick.new()
	root.add_child(stick)
	var seen: Array[Vector2] = []
	stick.moved.connect(func(vector: Vector2) -> void: seen.append(vector))
	var down: InputEventScreenTouch = InputEventScreenTouch.new()
	down.index = 1
	down.pressed = true
	down.position = Vector2(100.0, 300.0)
	stick._input(down)
	var other: InputEventScreenDrag = InputEventScreenDrag.new()
	other.index = 2
	other.position = Vector2(300.0, 300.0)
	stick._input(other)
	_check(stick.vector == Vector2.ZERO, "joystick ignores another finger")
	var own: InputEventScreenDrag = InputEventScreenDrag.new()
	own.index = 1
	own.position = Vector2(100.0 + stick.base_radius * 2.0, 300.0)
	stick._input(own)
	_check(stick.vector.distance_to(Vector2.RIGHT) < 0.001, "joystick clamps to length one")
	var up: InputEventScreenTouch = InputEventScreenTouch.new()
	up.index = 1
	up.pressed = false
	stick._input(up)
	_check(stick.vector == Vector2.ZERO and stick.finger_index == -1, "joystick releases on finger up")


func _test_hit() -> void:
	_clear()
	var arena: Arena = Arena.new()
	root.add_child(arena)
	var thrower: Character = _spawn(0, Character.Role.DEFENDER, Vector2(100.0, 300.0))
	var runner: Character = _spawn(1, Character.Role.ATTACKER, Vector2(500.0, 300.0))
	arena.register_character(thrower)
	arena.register_character(runner)
	thrower.arena = arena
	var sandal: Sandal = _spawn_sandal(Vector2(100.0, 300.0))
	sandal.is_pass_sandal = true
	await _step(2)
	thrower.pick_up(sandal)
	runner.velocity = Vector2(0.0, -200.0)
	var direct: Vector2 = (runner.global_position - thrower.global_position).normalized()
	_check(thrower.hit(runner), "defender hit returns true")
	await _step(2)
	_check(sandal.linear_velocity.normalized().y < direct.y - 0.01, "hit leads a moving foe")
	var first_speed: float = sandal.linear_velocity.length()
	_check(first_speed > 100.0, "hit launches the sandal")
	_check(not thrower.hit(thrower), "a character cannot hit itself")


func _test_hero_power() -> void:
	_clear()
	var hero: HeroDef = HeroDef.new()
	hero.cooldown_seconds = 2.0
	hero.attack_params = {"duration": 0.5, "speed_mult": 2.0}
	hero.defence_params = {"duration": 0.5, "absorb": true}
	var body: Character = _spawn(0, Character.Role.ATTACKER, Vector2(300.0, 300.0))
	_check(not body.can_use_power(), "no hero means no power")
	body.hero = hero
	_check(body.can_use_power(), "hero power ready at start")
	_check(body.try_power(), "power starts")
	_check(not body.try_power(), "power refused while running")
	_check(is_equal_approx(body.power_cooldown_ratio(), 1.0), "running power counts as just used")
	await _step(60)
	_check(body.power_time_left <= 0.0, "power ends after its duration")
	_check(not body.can_use_power(), "cooldown still running after the power ends")
	_check(body.power_cooldown_ratio() > 0.0, "cooldown ratio above zero after use")
	body.power_cooldown_left = 0.0
	_check(body.try_power(), "power starts again after cooldown")
	body.role = Character.Role.DEFENDER
	_check(body.power_time_left <= 0.0, "role change ends the running power")
	body.power_cooldown_left = 0.0
	_check(body.try_power(), "defender form starts")
	body.die()
	_check(body.alive, "absorb survives the first hit")
	_check(not body.alive or body.power_time_left <= 0.0, "absorb is spent after one hit")
	body.end_power()
	body.die()
	_check(not body.alive, "dies once the absorb is gone")
	_check(not body.can_use_power(), "a dead hero cannot use power")


func _touch(index: int, pressed: bool, at: Vector2) -> InputEventScreenTouch:
	var event: InputEventScreenTouch = InputEventScreenTouch.new()
	event.index = index
	event.pressed = pressed
	event.position = at
	return event


func _test_hidden_button_ignores_touch() -> void:
	_clear()
	root.size = Vector2i(1280, 720)
	var button: DashButton = DashButton.new()
	root.add_child(button)
	var presses: Array[int] = []
	button.pressed.connect(func() -> void: presses.append(1))
	var on_button: Vector2 = Vector2(1280.0, 720.0) - button.edge_margin
	button.visible = false
	button._input(_touch(3, true, on_button))
	_check(presses.is_empty() and button.finger_index == -1, "a hidden button ignores a touch on it")
	button.visible = true
	button._input(_touch(3, true, on_button))
	_check(presses.size() == 1 and button.finger_index == 3, "a visible button takes the touch")
	button.visible = false
	button._input(_touch(3, false, on_button))
	_check(button.finger_index == -1, "a button hidden mid-press still lets go on release")


func _test_stale_finger_recovers() -> void:
	_clear()
	root.size = Vector2i(1280, 720)
	var stick: VirtualJoystick = VirtualJoystick.new()
	root.add_child(stick)
	stick._input(_touch(0, true, Vector2(100.0, 300.0)))
	_check(stick.finger_index == 0, "stick takes the first finger")
	stick._input(_touch(0, true, Vector2(150.0, 320.0)))
	_check(stick.finger_index == 0 and stick._origin.is_equal_approx(Vector2(150.0, 320.0)), "a press on the owner index restarts the stick when the release was lost")
	var cancel: InputEventScreenTouch = _touch(0, false, Vector2(150.0, 320.0))
	cancel.canceled = true
	stick._input(cancel)
	_check(stick.finger_index == -1, "a cancelled touch frees the stick")
