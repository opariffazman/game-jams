extends Node2D
## Plays two fake rounds and a match end so the HUD can be seen without the game.

const Fake: GDScript = preload("res://tests/hud_fake.gd")
const HUD_SCENE: PackedScene = preload("res://scenes/hud.tscn")

var _manager: Node2D
var _stack: Node2D
var _human: Node2D
var _characters: Array[Node2D] = []


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.06, 0.09, 0.16))
	add_child(Camera2D.new())
	_manager = _make_fake(&"hud_round_manager", Vector2.ZERO)
	_stack = _make_fake(&"hud_stack", Vector2(640, 360))
	for team: int in 2:
		for slot: int in 3:
			var character: Node2D = _make_fake(&"hud_character", Vector2(300 + slot * 90 + team * 440, 200 + slot * 120))
			character.team = team
			_characters.append(character)
	_human = _characters[0]
	_human.add_to_group(&"human_controlled")
	add_child(HUD_SCENE.instantiate())
	_run()


func _make_fake(group_name: StringName, at: Vector2) -> Node2D:
	var fake: Node2D = Fake.new()
	fake.position = at
	fake.add_to_group(group_name)
	add_child(fake)
	return fake


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _run() -> void:
	await _wait(0.5)
	for round_index: int in 3:
		_manager.attacking_team = round_index % 2
		for character: Node2D in _characters:
			character.alive = true
		_stack.placed_count = 0
		_manager.phase_changed.emit(Fake.State.COIN_FLIP)
		await _wait(2.4)
		_manager.throws_left = 3
		_manager.phase_changed.emit(Fake.State.TOPPLE)
		for throw_index: int in 3:
			await _wait(0.5)
			_manager.throws_left -= 1
		_stack.toppled.emit()
		_manager.phase_changed.emit(Fake.State.SCATTER)
		for placed: int in 3:
			await _wait(0.5)
			_stack.placed_count = placed + 1
		var attackers: Array[Node2D] = _characters.filter(func(c: Node2D) -> bool: return c.team == _manager.attacking_team)
		attackers[0].alive = false
		await _wait(0.6)
		_manager.phase_changed.emit(Fake.State.ROUND_END)
		_manager.round_ended.emit(_manager.attacking_team)
		await _wait(0.8)
	_manager.phase_changed.emit(Fake.State.MATCH_END)
