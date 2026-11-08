extends SceneTree
## Headless test of the team colour rule: friendly blue, enemy red, never swapping, sandals follow.
##
## Run: godot --headless --path game --script res://tests/colour_test.gd

const MIN_FLOOR_CONTRAST: float = 4.5
const FLOOR_COLOR: Color = Color(23.0 / 255.0, 33.0 / 255.0, 56.0 / 255.0)

var _failures: int = 0


func _initialize() -> void:
	await _run()
	print("colour_test: %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
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


func _luminance(color: Color) -> float:
	var channels: Array[float] = []
	for value: float in [color.r, color.g, color.b]:
		channels.append(value / 12.92 if value <= 0.04045 else pow((value + 0.055) / 1.055, 2.4))
	return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]


func _contrast(a: Color, b: Color) -> float:
	var high: float = maxf(_luminance(a), _luminance(b))
	var low: float = minf(_luminance(a), _luminance(b))
	return (high + 0.05) / (low + 0.05)


func _same(a: Color, b: Color) -> bool:
	return a.is_equal_approx(b)


func _spawn(arena: Arena, tuning: Tuning, team: int, role: Character.Role, at: Vector2) -> Character:
	var character: Character = (load("res://scenes/character.tscn") as PackedScene).instantiate() as Character
	character.configure(team, role, tuning)
	character.arena = arena
	character.stack = arena.stack
	character.position = at
	arena.add_child(character)
	return character


func _run() -> void:
	var tuning: Tuning = Tuning.load_default()
	var friendly: Color = tuning.friendly_color
	var enemy: Color = tuning.enemy_color
	_check(_contrast(friendly, FLOOR_COLOR) >= MIN_FLOOR_CONTRAST, "friendly colour reads %.2f:1 on the floor" % _contrast(friendly, FLOOR_COLOR))
	_check(_contrast(enemy, FLOOR_COLOR) >= MIN_FLOOR_CONTRAST, "enemy colour reads %.2f:1 on the floor" % _contrast(enemy, FLOOR_COLOR))
	_check(friendly.b > friendly.r and friendly.b > 0.9, "friendly is blue")
	_check(enemy.r > 0.9 and enemy.r > enemy.b * 2.0, "enemy is red")

	var arena: Arena = (load("res://scenes/arena.tscn") as PackedScene).instantiate() as Arena
	root.add_child(arena)
	await _frames(3)

	var human_team: int = tuning.human_team
	var enemy_team: int = 1 - human_team
	var human: Character = _spawn(arena, tuning, human_team, Character.Role.ATTACKER, arena.centre_spot + Vector2(-260.0, 0.0))
	var foe: Character = _spawn(arena, tuning, enemy_team, Character.Role.DEFENDER, arena.centre_spot + Vector2(100.0, 0.0))
	human.add_to_group(Character.HUMAN_GROUP)
	human.role = Character.Role.ATTACKER
	foe.role = Character.Role.DEFENDER
	await _frames(2)
	_check(_same(human.visual.team_color, friendly), "human attacker is friendly blue")
	_check(_same(foe.visual.team_color, enemy), "enemy defender is enemy red")

	human.role = Character.Role.DEFENDER
	foe.role = Character.Role.ATTACKER
	await _frames(2)
	_check(_same(human.visual.team_color, friendly), "human stays blue after the role swap")
	_check(_same(foe.visual.team_color, enemy), "enemy stays red after the role swap")

	human.role = Character.Role.ATTACKER
	foe.role = Character.Role.DEFENDER
	var mate: Character = _spawn(arena, tuning, human_team, Character.Role.ATTACKER, arena.centre_spot + Vector2(-260.0, 60.0))
	await _frames(2)
	human.remove_from_group(Character.HUMAN_GROUP)
	mate.add_to_group(Character.HUMAN_GROUP)
	await _frames(2)
	_check(_same(human.visual.team_color, friendly), "control moving to a teammate does not recolour the old character")
	_check(_same(mate.visual.team_color, friendly), "the new controlled character is friendly blue")

	var stack_sandal: Sandal = arena.stack.standing_sandals[0]
	_check(stack_sandal.owner_team == Sandal.NO_OWNER, "stack sandal has no owner")
	_check(_same(stack_sandal.visual.team_color, tuning.neutral_sandal_color), "stack sandal stays neutral sand")

	var loose: Sandal = Sandal.new()
	loose.tuning = tuning
	loose.position = arena.centre_spot + Vector2(0.0, 200.0)
	arena.add_child(loose)
	await _frames(2)
	_check(not loose.freeze, "loose sandal far from every character stays on the field")
	_check(_same(loose.visual.team_color, tuning.neutral_sandal_color), "loose sandal is neutral sand")
	loose.global_position = human.global_position + Vector2(10.0, 0.0)
	human.pick_up(loose)
	await _frames(2)
	_check(loose.owner_team == human_team, "picked-up sandal takes the carrier's team")
	_check(_same(loose.visual.team_color, friendly), "carried sandal is friendly blue")

	human.role = Character.Role.DEFENDER
	human.throw_sandal(Vector2.UP, 0.4)
	await physics_frame
	_check(loose.in_flight, "a thrown sandal is in flight")
	_check(loose.owner_team == human_team, "thrown sandal keeps the thrower's team in flight")
	_check(_same(loose.visual.team_color, friendly), "thrown sandal is the thrower's colour")
	await _frames(240)
	_check(not loose.in_flight, "the sandal comes to rest")
	_check(loose.owner_team == Sandal.NO_OWNER, "a sandal at rest on the field is shared again")
	_check(_same(loose.visual.team_color, tuning.neutral_sandal_color), "a resting sandal is neutral sand again")
	human.role = Character.Role.ATTACKER

	var foe_sandal: Sandal = Sandal.new()
	foe_sandal.tuning = tuning
	foe_sandal.position = foe.position + Vector2(0.0, 40.0)
	arena.add_child(foe_sandal)
	await _frames(2)
	foe.pick_up(foe_sandal)
	await _frames(2)
	_check(_same(foe_sandal.visual.team_color, enemy), "enemy-carried sandal is enemy red")

	var pass_sandal: Sandal = Sandal.new()
	pass_sandal.tuning = tuning
	pass_sandal.is_pass_sandal = true
	pass_sandal.position = foe.position + Vector2(0.0, -40.0)
	arena.add_child(pass_sandal)
	await _frames(2)
	foe.carried = null
	foe.pick_up(pass_sandal)
	await _frames(2)
	_check(_same(pass_sandal.visual.team_color, enemy), "pass sandal takes the holder's colour")
	var flat_art: PrimitiveSkinVisual = pass_sandal.visual as PrimitiveSkinVisual
	var depth_art: DepthVisual = pass_sandal.visual as DepthVisual
	var has_ring: bool = (flat_art != null and flat_art.ring_color.a > 0.0) or (depth_art != null and depth_art.kind == DepthVisual.Kind.PASS_SANDAL)
	_check(has_ring, "pass sandal keeps its distinct ring")

	_check(not _same(friendly, enemy), "friendly and enemy colours differ")
	_check(not _same(friendly, tuning.neutral_sandal_color) and not _same(enemy, tuning.neutral_sandal_color), "neither team colour equals neutral sand")
