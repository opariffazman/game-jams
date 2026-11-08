extends SceneTree
## Headless test of the hero select screen against a fake manager.
##
## Run: godot --headless --path game --script res://tests/hero_select_test.gd

class FakeManager extends Node:
	var heroes: Array[HeroDef] = []
	var tuning: Object = FakeTuning.new()
	var human_pick: HeroDef
	var enemy_pick: HeroDef

	func set_heroes(human_hero: HeroDef, enemy_hero: HeroDef) -> void:
		human_pick = human_hero
		enemy_pick = enemy_hero


class FakeTuning extends RefCounted:
	var human_team: int = 0


var _failures: int = 0
var _confirmed: HeroDef


func _initialize() -> void:
	await _run()
	print("hero_select_test: %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(_failures)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   ", label)
	else:
		print("  FAIL ", label)
		_failures += 1


func _key(code: Key) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	root.push_input(event)


func _open(manager: FakeManager) -> HeroSelect:
	var screen: HeroSelect = HeroSelect.new()
	root.add_child(screen)
	screen.confirmed.connect(func(hero: HeroDef) -> void: _confirmed = hero)
	screen.open(manager)
	await process_frame
	return screen


func _run() -> void:
	await process_frame
	var settings: Node = root.get_node("Settings")
	settings.path = "user://hero_select_test_settings.cfg"
	settings.hero_id = &"lontar"
	var manager: FakeManager = FakeManager.new()
	manager.heroes = [HeroRoster.get_hero(&"kilat"), HeroRoster.get_hero(&"tukang")]
	root.add_child(manager)
	var screen: HeroSelect = await _open(manager)
	_check(screen.cards.size() == 5, "five cards")
	_check(screen.selected == 3 and screen.heroes[3].id == &"lontar", "opens on the saved hero")
	_check(paused, "tree is paused while open")
	for card: Control in screen.cards:
		_check(card.size.x >= 44.0 and card.size.y >= 44.0, "card hit target at least 44 px")
	var lifted: float = screen.cards[screen.selected].position.y
	_check(lifted < screen.cards[0].position.y, "selected card sits higher")
	screen.select(1)
	_check(screen.selected == 1, "select moves")
	_key(KEY_RIGHT)
	_check(screen.selected == 2, "right key moves on")
	_key(KEY_LEFT)
	_key(KEY_LEFT)
	_check(screen.selected == 0, "left key moves back")
	_key(KEY_LEFT)
	_check(screen.selected == 4, "left key wraps")
	_key(KEY_ENTER)
	await process_frame
	_check(_confirmed != null and _confirmed.id == &"tangkap", "enter confirms the selected hero")
	_check(settings.hero_id == &"tangkap", "confirm saves hero_id")
	_check(manager.human_pick != null and manager.human_pick.id == &"tangkap", "manager gets the human hero")
	_check(manager.enemy_pick == HeroRoster.get_hero(&"tukang"), "manager keeps the rolled enemy hero")
	_check(not paused, "tree unpaused after confirm")
	_check(not is_instance_valid(screen) or screen.is_queued_for_deletion(), "screen frees itself")
	_confirmed = null
	var again: HeroSelect = await _open(manager)
	again.confirm(&"perisai")
	_check(_confirmed != null and _confirmed.id == &"perisai", "public confirm works")
	var third: HeroSelect = await _open(manager)
	third.confirm(&"nobody")
	_check(_confirmed.id == &"perisai" and third.is_open(), "unknown id does nothing")
	third.free()
