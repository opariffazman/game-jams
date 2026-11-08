class_name SmokeLocker
extends RefCounted
## Smoke checks of the Locker, the upgrades, and the save, through the real input path.

var _smoke: Smoke
var _main: HotSwapMain


## Binds the checks to [param smoke], which owns the game and the input helpers.
func _init(smoke: Smoke) -> void:
	_smoke = smoke
	_main = smoke.main


## From JOB COMPLETE: a tap opens the Locker, the balance shows, and CLOCK IN starts a new tower.
func win_to_new_tower() -> bool:
	if _main.phase != HotSwapMain.Phase.END:
		_smoke.fail("not on the end screen before the Locker check: phase %d" % _main.phase)
		return false
	var balance: int = int(_main.save["tips"])
	await _smoke.get_tree().create_timer(HotSwapMain.END_TAP_DELAY_MS / 1000.0 + 0.1, true, false, true).timeout
	_smoke.click(Smoke.CORNER)
	await _smoke.get_tree().process_frame
	if _main.phase != HotSwapMain.Phase.LOCKER or not _main.hud.locker.visible or balance <= 0:
		_smoke.fail("win screen did not open the Locker: phase %d, balance %d" % [_main.phase, balance])
		return false
	var first_seed: int = _main.run.seed
	_smoke.click(LockerView.CLOCK_RECT.get_center())
	await _smoke.get_tree().process_frame
	if _main.phase != HotSwapMain.Phase.PLAN or _main.run.seed == first_seed or _main.run.room_index != 0 or _main.hud.locker.visible:
		_smoke.fail("CLOCK IN after the win did not start a new tower: phase %d" % _main.phase)
		return false
	print("LOCKER OK: JOB COMPLETE, a tap opens the Locker with %d tips, CLOCK IN starts a new tower" % balance)
	return true


## Buys every upgrade by tap and key, checks the cost and the effect of each, then the save across a restart.
func upgrades() -> bool:
	if not await _poor_and_locked():
		return false
	if not await _buy_all():
		return false
	if not await _clock_in_with_upgrades():
		return false
	return await _check_save_files()


func _open_with_tips(tips: int) -> void:
	var save: Dictionary = SaveData.fresh()
	save["tips"] = tips
	SaveData.write(save)
	_main.reload_save()
	_main.open_locker()


func _tap_card(index: int, by_key: bool) -> void:
	if by_key:
		_smoke.key(KEY_1 + index)
	else:
		_smoke.click(LockerView.CARD_RECTS[index].get_center())


func _poor_and_locked() -> bool:
	_open_with_tips(30)
	_tap_card(Upgrades.Id.HEARTS_1, false)
	_tap_card(Upgrades.Id.HEARTS_2, true)
	await _smoke.get_tree().process_frame
	if int(_main.save["tips"]) != 30 or not _main.save["owned"].is_empty():
		_smoke.fail("a card bought without enough tips or before its requirement: %s" % [_main.save])
		return false
	print("LOCKER CHECK: Max Hearts I costs 40 and is refused with 30 tips, Max Hearts II is refused while locked")
	return true


func _buy_all() -> bool:
	_open_with_tips(400)
	var expected: int = 400
	for id: int in [Upgrades.Id.HEARTS_1, Upgrades.Id.HEARTS_2, Upgrades.Id.SPARE_SLACK, Upgrades.Id.OPENING_CHOICE, Upgrades.Id.CYAN_COAT, Upgrades.Id.AMBER_COAT]:
		_tap_card(id, id % 2 == 1)
		await _smoke.get_tree().process_frame
		expected -= Upgrades.COSTS[id]
		if int(_main.save["tips"]) != expected or id not in _main.save["owned"] or int(SaveData.load_save()["tips"]) != expected:
			_smoke.fail("buying %s: balance %d, expected %d, owned %s" % [Upgrades.NAMES[id], int(_main.save["tips"]), expected, _main.save["owned"]])
			return false
		print("LOCKER CHECK: %s cost %d, balance %d" % [Upgrades.NAMES[id], Upgrades.COSTS[id], expected])
	_tap_card(Upgrades.Id.CYAN_COAT, false)
	var cyan: bool = int(_main.save["coat"]) == Upgrades.Id.CYAN_COAT
	_tap_card(Upgrades.Id.CYAN_COAT, false)
	var off: bool = int(_main.save["coat"]) == -1
	_tap_card(Upgrades.Id.AMBER_COAT, true)
	if not cyan or not off or int(_main.save["coat"]) != Upgrades.Id.AMBER_COAT or int(_main.save["tips"]) != expected:
		_smoke.fail("equip by tap: cyan %s, off %s, coat %s, balance %d" % [cyan, off, _main.save["coat"], int(_main.save["tips"])])
		return false
	print("LOCKER CHECK: tapping an owned coat equips it, tapping it again takes it off, buying costs nothing more")
	return true


func _clock_in_with_upgrades() -> bool:
	_smoke.key(KEY_ENTER)
	await _smoke.get_tree().process_frame
	var run: RunState = _main.run
	if _main.phase != HotSwapMain.Phase.BOON or _main.boon_offers().size() != BoonSet.COUNT or run.hearts != RunState.START_HEARTS + 2:
		_smoke.fail("Enter did not start a run with the Opening Choice: phase %d, cards %d, hearts %d" % [_main.phase, _main.boon_offers().size(), run.hearts])
		return false
	_smoke.click(Hud.CARD_RECTS[1].get_center())
	await _smoke.get_tree().process_frame
	var par: int = int(run.current_room()["par"])
	var expected_budget: int = par + RoomGen.slack_for(1) + 1 + (1 if BoonSet.Boon.SPARE_CLIP in run.boons else 0)
	if _main.phase != HotSwapMain.Phase.PLAN or run.boons != [BoonSet.Boon.SPARE_CLIP] or run.room_index != 0 or _main.budget != expected_budget:
		_smoke.fail("Opening Choice pick: phase %d, boons %s, budget %d, expected %d" % [_main.phase, run.boons, _main.budget, expected_budget])
		return false
	var by_floor: Array[int] = []
	for index: int in [0, 3, 6, 9]:
		var probe: RunState = RunState.new(1, [Upgrades.Id.SPARE_SLACK])
		var plain: RunState = RunState.new(1)
		probe.room_index = index
		plain.room_index = index
		by_floor.append(probe.budget() - plain.budget())
	if by_floor != [1, 1, 0, 0] or _main.play.hero_color != Palette.AMBER:
		_smoke.fail("Spare Slack by floor %s (want [1, 1, 0, 0]) or hero color %s is not amber" % [by_floor, _main.play.hero_color])
		return false
	print("LOCKER CHECK: hearts start at %d, Spare Slack adds a shift on floors 1 and 2 only, Opening Choice offers %d boons, the hero is amber" % [run.hearts, BoonSet.COUNT])
	return true


func _check_save_files() -> bool:
	_main.save = SaveData.fresh()
	_main.reload_save()
	if _main.save["owned"].size() != Upgrades.COUNT or int(_main.save["tips"]) != 70 or int(_main.save["coat"]) != Upgrades.Id.AMBER_COAT:
		_smoke.fail("upgrades did not persist across a simulated restart: %s" % [_main.save])
		return false
	var file: FileAccess = FileAccess.open(SaveData.path, FileAccess.WRITE)
	file.store_string('{"tips": 5, "best_floor": 1, "owned": [99, "x", 2, 2], "coat": 4}')
	file.close()
	var partial: Dictionary = SaveData.load_save()
	if partial["owned"] != [2] or int(partial["coat"]) != -1 or int(partial["tips"]) != 5:
		_smoke.fail("a save with bad upgrade ids loaded as %s" % [partial])
		return false
	file = FileAccess.open(SaveData.path, FileAccess.WRITE)
	file.store_string("{ not json")
	file.close()
	if SaveData.load_save() != SaveData.fresh():
		_smoke.fail("a corrupt save did not start fresh")
		return false
	DirAccess.remove_absolute(SaveData.path)
	_main.reload_save()
	if _main.save != SaveData.fresh():
		_smoke.fail("a missing save did not start fresh")
		return false
	_main.open_locker()
	var biggest: bool = true
	for rect: Rect2 in LockerView.CARD_RECTS:
		biggest = biggest and LockerView.CLOCK_RECT.get_area() > rect.get_area() * 2.0 and rect.size.y >= 72.0
	_smoke.click(LockerView.CLOCK_RECT.get_center())
	await _smoke.get_tree().process_frame
	if not biggest or _main.phase != HotSwapMain.Phase.PLAN or _main.run.hearts != RunState.START_HEARTS:
		_smoke.fail("fresh save: CLOCK IN largest %s, phase %d, hearts %d" % [biggest, _main.phase, _main.run.hearts])
		return false
	print("SAVE OK: upgrades and coat persist across a restart, bad ids are dropped, corrupt and missing saves start clean, a fresh save is one tap from play")
	return true
