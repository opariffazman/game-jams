class_name SmokeBoss
extends RefCounted
## Smoke checks of the boss fight and of the telegraph, both through the real input path.

## A screen point that hits no gunman and no door.
const CORNER: Vector2 = Vector2(5, 5)

var _smoke: Smoke


## Binds the checks to [param smoke], which owns the game and the input helpers.
func _init(smoke: Smoke) -> void:
	_smoke = smoke


## Plays the boss from its intro to JOB COMPLETE. Phase 2 fails once first. Appends the phase room ids to [param played_ids].
func play(played_ids: Array[String]) -> bool:
	var main: HotSwapMain = _smoke.main
	var run: RunState = main.run
	if main.phase != HotSwapMain.Phase.INTRO or main.hud.card_title() != "THE MANAGER" or not main.backdrop_visible() or main.hud.boss_pips() != 3:
		_smoke.fail("boss intro: phase %d, card '%s', pips %d" % [main.phase, main.hud.card_title(), main.hud.boss_pips()])
		return false
	_smoke.click(CORNER)
	await _smoke.get_tree().process_frame
	for phase_number: int in range(1, RunState.BOSS_PHASES + 1):
		var room: Dictionary = run.current_room()
		played_ids.append(str(room["id"]))
		var spare: int = 1 if BoonSet.Boon.SPARE_CLIP in run.boons else 0
		if main.phase != HotSwapMain.Phase.PLAN or run.boss_phase != phase_number or main.hud.boss_pips() != RunState.BOSS_PHASES - phase_number + 1 or main.budget != int(room["par"]) + spare:
			_smoke.fail("boss phase %d: phase %d, boss phase %d, pips %d, budget %d, par %s" % [phase_number, main.phase, run.boss_phase, main.hud.boss_pips(), main.budget, room["par"]])
			return false
		if phase_number == 2 and not await _fail_once(room):
			return false
		var plan: Array[int] = HotSwapRules.solve(main.room_state(), 6, run.boon_set())
		if plan.is_empty():
			_smoke.fail("boss phase %d has no solution" % phase_number)
			return false
		var tips_before: int = run.tips
		for tap: int in plan:
			if not await _smoke.click_gun(tap):
				return false
		if not await _after_phase(phase_number, tips_before):
			return false
	return await _smoke.finish_replay(RunState.ROOM_COUNT - 1)


## Checks that the intro card ends by itself and the first phase starts.
func intro_auto() -> bool:
	var main: HotSwapMain = _smoke.main
	main.start_run(31)
	main.run.room_index = RunState.ROOM_COUNT - 1
	main.enter_room()
	if main.phase != HotSwapMain.Phase.INTRO:
		_smoke.fail("boss intro did not show: phase %d" % main.phase)
		return false
	await _smoke.get_tree().create_timer(HotSwapMain.INTRO_S + 0.3, true, false, true).timeout
	if main.phase != HotSwapMain.Phase.PLAN or main.run.boss_phase != 1 or main.hud.card_title() != "":
		_smoke.fail("boss intro did not end by itself: phase %d, card '%s'" % [main.phase, main.hud.card_title()])
		return false
	print("BOSS INTRO OK: the card shows THE MANAGER, a tap skips it, and it ends by itself after %.1f s" % HotSwapMain.INTRO_S)
	return true


## Checks the knife danger zone and the advance step as the player meets them: a tap on a gunman, then the room state.
func telegraph_input() -> bool:
	var main: HotSwapMain = _smoke.main
	main.start_run(41)
	var base: Array = [[Vector2i(4, 7), RuleChecks.PISTOL, RuleChecks.UP], [Vector2i(4, 6), RuleChecks.PISTOL, RuleChecks.UP]]
	var inside: Dictionary = _test_room(base + [[Vector2i(5, 6), RuleChecks.KNIFE, RuleChecks.UP]])
	var hearts: int = main.run.hearts
	main.play_room(inside)
	if not await _smoke.click_gun(0) or main.phase != HotSwapMain.Phase.FAILED or main.run.hearts != hearts - 1 or not main.play.stabbed:
		_smoke.fail("hero landed inside the knife zone: phase %d, hearts %d, stabbed %s" % [main.phase, main.run.hearts, main.play.stabbed])
		return false
	var outside: Dictionary = _test_room(base + [[Vector2i(1, 5), RuleChecks.KNIFE, RuleChecks.UP]])
	main.play_room(outside)
	if not await _smoke.click_gun(0) or main.phase != HotSwapMain.Phase.PLAN or Rooms.cell_of(main.room_state().guns[2]) != Vector2i(1, 6):
		_smoke.fail("hero outside the knife zone: phase %d, knife at %s" % [main.phase, Rooms.cell_of(main.room_state().guns[2])])
		return false
	var marched: Dictionary = _test_room([[Vector2i(4, 7), RuleChecks.PISTOL, RuleChecks.UP], [Vector2i(4, 6), RuleChecks.PISTOL, RuleChecks.UP], [Vector2i(1, 5), RuleChecks.PISTOL, RuleChecks.UP]], [{"turn": 1, "type": "advance", "params": {}}])
	main.play_room(marched)
	if not await _smoke.click_gun(0) or Rooms.cell_of(main.room_state().guns[2]) != Vector2i(1, 6):
		_smoke.fail("advance stepped to %s, not toward the start-of-turn hero cell" % Rooms.cell_of(main.room_state().guns[2]))
		return false
	print("TELEGRAPH OK: by tap, a hero inside a knife zone is stabbed and outside is not, and knife and advance steps follow the start-of-turn hero cell")
	return true


func _fail_once(room: Dictionary) -> bool:
	var main: HotSwapMain = _smoke.main
	var run: RunState = main.run
	var hearts: int = run.hearts
	var kept: BoonSet = main.play.boons
	main.play.boons = BoonSet.new()
	var failing: Array[int] = _smoke.failing_taps(true, main.play.boons)
	if failing.is_empty():
		_smoke.fail("no failing taps in boss phase 2 room %s" % room["id"])
		return false
	for tap: int in failing:
		if not await _smoke.click_gun(tap):
			return false
	main.play.boons = kept
	if main.phase != HotSwapMain.Phase.FAILED or run.hearts != hearts - 1 or run.boss_phase != 2:
		_smoke.fail("boss fail: phase %d, hearts %d (was %d), boss phase %d" % [main.phase, run.hearts, hearts, run.boss_phase])
		return false
	_smoke.click(CORNER)
	await _smoke.get_tree().process_frame
	if main.phase != HotSwapMain.Phase.PLAN or run.boss_phase != 2 or str(run.current_room()["id"]) != str(room["id"]) or main.swaps != 0:
		_smoke.fail("boss retry did not restart phase 2 only: phase %d, boss phase %d" % [main.phase, run.boss_phase])
		return false
	print("BOSS FAIL OK: a failed phase costs a heart and retries phase 2 only")
	return true


func _after_phase(phase_number: int, tips_before: int) -> bool:
	var main: HotSwapMain = _smoke.main
	var run: RunState = main.run
	if phase_number == RunState.BOSS_PHASES:
		var paid: int = run.tips - tips_before
		if main.phase != HotSwapMain.Phase.REPLAY or paid != RunState.ROOM_TIPS + RunState.FLOOR_TIPS + RunState.BOSS_TIPS:
			_smoke.fail("last phase: phase %d, tips paid %d" % [main.phase, paid])
			return false
		print("BOSS WIN OK: the 3D replay plays after phase 3 only, and the boss paid %d tips" % paid)
		return true
	var title: String = "PHASE %d" % (phase_number + 1)
	if main.phase != HotSwapMain.Phase.STINGER or main.hud.card_title() != title or run.boss_phase != phase_number + 1 or run.tips != tips_before or main.hud.boss_pips() != RunState.BOSS_PHASES - phase_number:
		_smoke.fail("stinger after phase %d: phase %d, card '%s', pips %d" % [phase_number, main.phase, main.hud.card_title(), main.hud.boss_pips()])
		return false
	if phase_number == 1:
		_smoke.click(CORNER)
		await _smoke.get_tree().process_frame
	else:
		await _smoke.get_tree().create_timer(HotSwapMain.STINGER_S + 0.3, true, false, true).timeout
	if main.phase != HotSwapMain.Phase.PLAN:
		_smoke.fail("the stinger did not lead to phase %d: phase %d" % [phase_number + 1, main.phase])
		return false
	print("BOSS PHASE %d OK: a pip is gone, the stinger reads %s, no replay and no door, phase %d starts" % [phase_number, title, phase_number + 1])
	return true


func _test_room(guns: Array, events: Array[Dictionary] = []) -> Dictionary:
	var room: Dictionary = RuleChecks.room(Vector2i(3, 8), guns, events)
	room["par"] = 2
	room["floor"] = 1
	room["id"] = "smoke"
	room["motif"] = "smoke"
	return room
