class_name HotSwapMain
extends Node2D
## Hot Shift run flow: one night up a tower of 12 rooms, a 3-phase boss in the last one, and the Locker between nights.
## Routes input, owns the run, hands play to [RoomPlay] and the screens to [Hud].

## Screens of the run flow. New values are appended so the smoke test output stays comparable.
enum Phase { PLAN, RESOLVE, FAILED, REPLAY, DOOR, BOON, END, INTRO, STINGER, LOCKER }

## Reels that play in 3D. A clear replay ends on the next screen, a review (the R key) returns to where it started,
## the death reel and the win chain end on the end panel, and a watched chain returns to the end panel.
enum Reel { CLEAR, REVIEW, DEATH, CHAIN_WIN, CHAIN_WATCH }

## Milliseconds after the end screen shows before a tap opens the Locker.
const END_TAP_DELAY_MS: int = 400
## Seconds the boss intro card shows when nobody taps.
const INTRO_S: float = 1.0
## Seconds the phase stinger shows when nobody taps.
const STINGER_S: float = 0.9
## Save file used by the smoke test and the demo, so they never touch the real save.
const SCRATCH_SAVE: String = "user://save_scratch.json"
## Seconds after a shift starts before the dead-end scan runs, so the tap shows its result first. Real time.
const SCAN_DELAY_S: float = 0.05
## Screen position used for key presses, which hit nothing.
const NO_POSITION: Vector2 = Vector2(-1, -1)

## Current screen, read by the smoke test.
var phase: Phase = Phase.PLAN
## Current run.
var run: RunState
## Swaps used in the current room.
var swaps: int = 0
## Swap budget of the current room.
var budget: int = 0
## Gunmen tapped in the current room, in order.
var taps: Array[int] = []
## Final state of the last live clear, compared against [member replay_outcome].
var live_outcome: Dictionary = {}
## Final state of the last finished replay.
var replay_outcome: Dictionary = {}
## Event timeline of the last replay, read by the smoke test.
var last_timeline: TurnEvents
## Kind of the reel that plays or played last, read by the smoke test.
var last_reel: Reel = Reel.CLEAR
## Persistent save: tips balance, best floor, owned upgrades, equipped coat.
var save: Dictionary = {}
## Room play layer.
var play: RoomPlay
## Screens and the top HUD.
var hud: Hud
## UNDO button, RETRY button, and the NO WAY OUT banner.
var controls: PlayControls
## Undos of the current room.
var undo: ShiftUndo = ShiftUndo.new()
## Result of the last dead-end scan: verdict, and for a dead end the cause and reason. Empty before the first scan of a shift.
var scan_info: Dictionary = {}
## Milliseconds the last dead-end scan took.
var last_scan_ms: float = 0.0

var _room: Dictionary = {}
var _backdrop: BossBackdrop
var _stage: ReplayStage
var _director: ReplayDirector
var _offers: Array[int] = []
var _boon_offers: Array[int] = []
var _opening_pick: bool = false
var _card_token: int = 0
var _scan_token: int = 0
var _end_ready_ms: int = 0
var _replay_room: Dictionary = {}
var _replay_taps: Array[int] = []
var _replay_boons: BoonSet = BoonSet.new()
var _replay_place: String = ""
var _replay_resume: Phase = Phase.DOOR
var _death_room: Dictionary = {}
var _death_taps: Array[int] = []
var _death_boons: BoonSet = BoonSet.new()
var _death_place: String = ""
@onready var _camera: Camera2D = $Camera


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if "--gen" in args:
		PoolGen.write_all()
		get_tree().quit()
		return
	if "--deadend-table" in args:
		DeadEndReport.print_table()
		get_tree().quit()
		return
	if "--smoke" in args or "--run-demo" in args:
		SaveData.path = SCRATCH_SAVE
		DirAccess.remove_absolute(SCRATCH_SAVE)
	_backdrop = BossBackdrop.new()
	_backdrop.visible = false
	add_child(_backdrop)
	play = RoomPlay.new()
	play.camera = _camera
	play.resolved.connect(_on_resolved)
	add_child(play)
	hud = Hud.new()
	add_child(hud)
	controls = PlayControls.new()
	add_child(controls)
	save = SaveData.load_save()
	if Pool.rooms().is_empty():
		printerr("data/pool.json is missing or empty. Run with --headless -- --gen first.")
		return
	var url_seed: int = SeedCode.from_query(ShareLink.page_query())
	if "--daily" in args:
		start_run(RoomGen.daily_seed())
	else:
		start_run(url_seed if url_seed > 0 else RunState.new_seed())
	if "--replay-demo" in args:
		var reel_demo: Demo = Demo.new()
		add_child(reel_demo)
		reel_demo.reels(self)
	if "--deadend-demo" in args:
		var dead_demo: Demo = Demo.new()
		add_child(dead_demo)
		dead_demo.deadend_demo(self)
	if "--run-demo" in args:
		var demo: Demo = Demo.new()
		add_child(demo)
		demo.run(self)
	if "--smoke" in args:
		var smoke: Node = load("res://scripts/smoke.gd").new()
		add_child(smoke)
		smoke.call("run", self)


func _exit_tree() -> void:
	Engine.time_scale = 1.0


func _process(_delta: float) -> void:
	_sync_controls()


func _unhandled_input(event: InputEvent) -> void:
	if play == null:
		return
	if event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event
		play.set_hover(play.gun_at_screen(motion.position))
	elif event is InputEventMouseButton:
		var click: InputEventMouseButton = event
		if click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
			_on_tap(click.position)
	elif event is InputEventKey:
		var key: InputEventKey = event
		if key.pressed and not key.echo:
			_on_key(key.keycode)


## Starts a new run with [param run_seed]. Hearts and slack follow the bought upgrades.
func start_run(run_seed: int) -> void:
	run = RunState.new(run_seed, save["owned"])
	_replay_taps.clear()
	hud.locker.close()
	hud.hide_end()
	hud.hide_card()
	if Upgrades.Id.OPENING_CHOICE in run.upgrades:
		_opening_pick = true
		_show_boon_cards()
	else:
		enter_room()


## Starts the current room. The first boss phase opens with the intro card instead.
func enter_room() -> void:
	if run.is_last_room() and run.boss_phase == 1:
		_show_card(Phase.INTRO, "THE MANAGER", "3 PHASES - TAP TO START", Palette.MAGENTA, INTRO_S)
	else:
		_start_room(run.current_room())


## Plays [param room] in place of the current room. Used by the smoke test and the demo.
func play_room(room: Dictionary) -> void:
	if not run.is_last_room():
		run.rooms[run.room_index] = room
	_start_room(room)


## Opens the Locker with the current save.
func open_locker() -> void:
	phase = Phase.LOCKER
	play.visible = false
	_backdrop.visible = false
	hud.set_boss(0)
	hud.hide_end()
	hud.hide_card()
	hud.hide_boons()
	hud.hide_doors()
	hud.locker.open(save, "", SeedCode.encode(run.seed))
	_update_hud()


## Replays the last cleared room from its recorded taps. Works on the fail, door, and end screens.
func replay_last() -> void:
	if _replay_taps.is_empty() or phase == Phase.PLAN or phase == Phase.RESOLVE or phase == Phase.REPLAY:
		return
	_replay_resume = phase
	_start_reel(Reel.REVIEW)


## Returns the title card text of the reel, or an empty string when none shows. Read by the smoke test.
func reel_card_title() -> String:
	return _stage.overlay.title_text() if _stage != null else ""


## Returns true once the 3D replay layer exists. It is created on the first replay.
func has_replay_3d() -> bool:
	return _stage != null


## Returns the on-screen position of gunman [param index], for the smoke test.
func gun_screen_position(index: int) -> Vector2:
	return play.gun_screen_position(index)


## Returns the live room state, for the smoke test.
func room_state() -> RoomState:
	return play.state


## Returns the end screen title, or an empty string when it is hidden.
func end_title() -> String:
	return hud.end_title()


## Returns the boon cards on offer, for the smoke test.
func boon_offers() -> Array[int]:
	return _boon_offers


## Returns the two doors on offer, for the smoke test.
func door_offers() -> Array[int]:
	return _offers


## Returns true while the boss silhouette shows, for the smoke test.
func backdrop_visible() -> bool:
	return _backdrop.visible


## Reloads the save from disk, as a restart does.
func reload_save() -> void:
	save = SaveData.load_save()
	_update_hud()


func _on_key(keycode: Key) -> void:
	if phase == Phase.RESOLVE:
		return
	if phase == Phase.LOCKER:
		if keycode >= KEY_1 and keycode < KEY_1 + Upgrades.COUNT:
			_activate_card(keycode - KEY_1)
		elif keycode == KEY_ENTER or keycode == KEY_KP_ENTER:
			_clock_in()
		return
	match keycode:
		KEY_R:
			replay_last()
		KEY_T:
			start_run(RoomGen.daily_seed())
		KEY_U:
			undo_shift()
		KEY_ENTER, KEY_KP_ENTER:
			if not retry_dead_end():
				_on_tap(NO_POSITION)
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
			var index: int = keycode - KEY_1
			if phase == Phase.DOOR:
				_pick_door(index)
			elif phase == Phase.BOON:
				_pick_boon(index)
			elif phase == Phase.PLAN and play.is_alive(index):
				_begin_swap(index)
		_:
			_on_tap(NO_POSITION)


func _on_tap(screen_pos: Vector2) -> void:
	hud.hide_hint()
	match phase:
		Phase.PLAN:
			if controls.undo_at(screen_pos):
				undo_shift()
				return
			if controls.retry_at(screen_pos):
				retry_dead_end()
				return
			var gun: int = play.gun_at_screen(screen_pos)
			if gun >= 0:
				_begin_swap(gun)
		Phase.FAILED:
			_start_room(_room)
		Phase.REPLAY:
			_finish_replay()
		Phase.DOOR:
			_pick_door(hud.door_at(screen_pos))
		Phase.BOON:
			_pick_boon(hud.boon_at(screen_pos))
		Phase.INTRO, Phase.STINGER:
			_start_room(run.current_room())
		Phase.LOCKER:
			if hud.locker.clock_in_at(screen_pos):
				_clock_in()
			elif hud.locker.card_at(screen_pos) >= 0:
				_activate_card(hud.locker.card_at(screen_pos))
		Phase.END:
			match hud.end_button_at(screen_pos):
				Hud.EndButton.WATCH:
					_watch_best_chain()
				Hud.EndButton.COPY:
					_copy_link()
				_:
					if Time.get_ticks_msec() >= _end_ready_ms:
						open_locker()


func _start_room(room: Dictionary) -> void:
	_stop_replay()
	_card_token += 1
	hud.hide_doors()
	hud.hide_boons()
	hud.hide_card()
	_room = room
	var boss: bool = run.is_last_room()
	_backdrop.visible = boss
	_backdrop.intensity = BossBackdrop.PLAY_ALPHA
	hud.set_boss(run.boss_phase if boss else 0)
	play.boons = run.boon_set()
	play.hero_color = Upgrades.hero_color(save)
	play.boss_look = boss
	play.load_room(room)
	play.visible = true
	budget = run.budget()
	swaps = 0
	taps.clear()
	undo.reset(run.undos_per_room)
	_scan_token += 1
	scan_info = {}
	controls.set_undo(undo.left)
	controls.hide_dead_end()
	hud.show_status("")
	phase = Phase.PLAN
	_update_hud()
	hud.show_banner(RoomMarks.banner(play.state))


func _begin_swap(tap: int) -> void:
	undo.push(play.state, swaps, taps)
	swaps += 1
	taps.append(tap)
	phase = Phase.RESOLVE
	hud.show_banner("")
	controls.hide_dead_end()
	play.begin_swap(tap)
	_update_hud()
	_scan_soon()


## Takes back the last shift when an undo is left: positions, alive flags, turn, coat, the shift used, and the tap list. Returns true when it did.
func undo_shift() -> bool:
	if phase != Phase.PLAN or not undo.can_undo():
		return false
	var record: Dictionary = undo.pop()
	_scan_token += 1
	scan_info = {}
	swaps = int(record["swaps"])
	taps.assign(record["taps"])
	play.restore(record["state"])
	controls.set_undo(undo.left)
	controls.hide_dead_end()
	hud.show_banner(RoomMarks.banner(play.state))
	_update_hud()
	return true


## Gives up a room that has no way out: costs one heart and retries the same room. Returns true when the banner offered RETRY.
func retry_dead_end() -> bool:
	if phase != Phase.PLAN or not controls.retry_shown():
		return false
	_fail_room("NO WAY OUT", true)
	return true


## Runs the dead-end scan a moment after a shift starts, so the tap never waits for it. The result waits for the end of the resolution.
func _scan_soon() -> void:
	_scan_token += 1
	scan_info = {}
	var token: int = _scan_token
	await get_tree().create_timer(SCAN_DELAY_S, true, false, true).timeout
	if token == _scan_token and scan_info.is_empty():
		_scan_now()


func _scan_now() -> void:
	var left: int = budget - swaps
	if play.last_hero_dead() or left <= 0:
		scan_info = {"verdict": DeadEnd.Verdict.WIN}
		return
	var started: int = Time.get_ticks_usec()
	scan_info = DeadEnd.analyze(play.state, left, run.boon_set())
	last_scan_ms = float(Time.get_ticks_usec() - started) / 1000.0


func _on_resolved(hero_dead: bool, alive_left: int) -> void:
	if not hero_dead:
		run.chain.consider(play.last_kills(), _room, taps, run.boons, run.floor_now(), run.room_in_floor())
	if hero_dead:
		_fail_room("STABBED" if play.stabbed else "SHOT")
	elif alive_left == 0:
		_clear_room()
	elif swaps >= budget:
		_fail_room("OUT OF SHIFTS")
	else:
		phase = Phase.PLAN
		play.set_planning(true)
		hud.show_banner(RoomMarks.banner(play.state))
		if scan_info.is_empty():
			_scan_now()
		if scan_info["verdict"] == DeadEnd.Verdict.DEAD:
			controls.show_dead_end(str(scan_info["reason"]), undo.can_undo())


func _fail_room(reason: String, retry_now: bool = false) -> void:
	play.set_planning(false)
	_death_room = _room
	_death_taps = taps.duplicate()
	_death_boons = run.boon_set()
	_death_place = Reels.place(run.floor_now(), run.room_in_floor())
	if run.lose_heart():
		_end_run(false)
	elif retry_now:
		_start_room(_room)
	else:
		phase = Phase.FAILED
		hud.show_status("%s\ntap to retry" % reason)
	_update_hud()


func _clear_room() -> void:
	live_outcome = play.outcome(swaps)
	if not run.on_cleared():
		_show_card(Phase.STINGER, "PHASE %d" % run.boss_phase, "THE MANAGER", Palette.AMBER, STINGER_S)
		return
	_replay_room = _room
	_replay_taps = taps.duplicate()
	_replay_boons = run.boon_set()
	_replay_place = Reels.place(run.floor_now(), run.room_in_floor())
	_start_reel(Reel.CLEAR)


## Shows a centered card over the boss silhouette. It ends after [param seconds] or on a tap, whichever comes first.
func _show_card(card_phase: Phase, title: String, sub: String, color: Color, seconds: float) -> void:
	_card_token += 1
	phase = card_phase
	play.visible = false
	_backdrop.visible = true
	_backdrop.intensity = BossBackdrop.CARD_ALPHA
	hud.hide_doors()
	hud.hide_boons()
	hud.show_banner("")
	hud.show_status("")
	hud.set_boss(run.boss_phase)
	hud.show_card(title, sub, color)
	_update_hud()
	get_tree().create_timer(seconds, true, false, true).timeout.connect(_on_card_timeout.bind(_card_token))


func _on_card_timeout(token: int) -> void:
	if token == _card_token and (phase == Phase.INTRO or phase == Phase.STINGER):
		_start_room(run.current_room())


func _after_clear() -> void:
	if run.is_last_room():
		_end_run(true)
		return
	phase = Phase.DOOR
	play.visible = false
	_offers = run.door_offers()
	hud.show_doors(_offers)
	_update_hud()


func _pick_door(index: int) -> void:
	if index < 0 or index >= _offers.size():
		return
	run.apply_door(_offers[index])
	if _offers[index] == RunState.Door.BOON:
		_opening_pick = false
		_show_boon_cards()
		return
	enter_room()


func _show_boon_cards() -> void:
	phase = Phase.BOON
	play.visible = false
	_boon_offers = run.unowned_boons()
	hud.hide_doors()
	hud.show_banner("")
	hud.show_boons(_boon_offers)
	_update_hud()


func _pick_boon(index: int) -> void:
	if index < 0 or index >= _boon_offers.size():
		return
	if _opening_pick:
		_opening_pick = false
		run.add_boon(_boon_offers[index])
	else:
		run.take_boon(_boon_offers[index])
	enter_room()


func _end_run(won: bool) -> void:
	run.finish(won)
	play.visible = false
	_backdrop.visible = false
	hud.set_boss(0)
	save = SaveData.record_run(run.floor_now(), run.tips)
	_update_hud()
	if won and run.chain.has_chain():
		_start_reel(Reel.CHAIN_WIN)
	elif not won:
		_start_reel(Reel.DEATH)
	else:
		_show_end_panel()


## Shows the end panel with the run numbers, the tower code and the buttons, and lets a tap open the Locker after a short delay.
func _show_end_panel() -> void:
	phase = Phase.END
	play.visible = false
	_end_ready_ms = Time.get_ticks_msec() + END_TAP_DELAY_MS
	hud.show_end("JOB COMPLETE" if run.won else "NIGHT OVER", run.floor_now(), run.rooms_cleared, run.tips, int(save["tips"]), SeedCode.encode(run.seed), run.chain.has_chain())
	get_tree().create_timer(END_TAP_DELAY_MS / 1000.0, true, false, true).timeout.connect(hud.set_end_ready.bind(true))
	_update_hud()


func _watch_best_chain() -> void:
	_replay_resume = Phase.END
	_start_reel(Reel.CHAIN_WATCH)


## Copies the share link from inside the tap handler, as browsers require. Shows the link as text when the copy fails.
func _copy_link() -> void:
	var text: String = ShareLink.text_for(run.seed)
	var started: bool = ShareLink.copy(text)
	hud.show_copy_result(started, text)
	if started and OS.has_feature("web"):
		await get_tree().create_timer(0.4, true, false, true).timeout
		if ShareLink.web_copy_failed():
			hud.show_copy_result(false, text)


func _activate_card(id: int) -> void:
	var result: Upgrades.Result = Upgrades.activate(save, id)
	var note: String = ""
	match result:
		Upgrades.Result.BOUGHT:
			note = "Bought %s." % Upgrades.NAMES[id]
		Upgrades.Result.EQUIPPED:
			note = "Equipped %s." % Upgrades.NAMES[id]
		Upgrades.Result.UNEQUIPPED:
			note = "%s off." % Upgrades.NAMES[id]
		Upgrades.Result.POOR:
			note = "Not enough money for %s." % Upgrades.NAMES[id]
		Upgrades.Result.LOCKED:
			note = "Buy the earlier upgrade first."
	if result == Upgrades.Result.BOUGHT or result == Upgrades.Result.EQUIPPED or result == Upgrades.Result.UNEQUIPPED:
		SaveData.write(save)
	hud.locker.refresh(save, note)


func _clock_in() -> void:
	start_run(RunState.new_seed(run.seed))


## Shows the room controls in the room phases only, so a tap in the same frame as a screen change already sees the right buttons.
func _sync_controls() -> void:
	if controls == null:
		return
	controls.set_active(phase == Phase.PLAN or phase == Phase.RESOLVE)


func _update_hud() -> void:
	_sync_controls()
	hud.update_run(run.floor_now(), run.room_in_floor(), run.hearts, swaps, budget, int(save["tips"]) + (0 if run.over else run.tips))
	hud.set_boons(run.boons, play.state != null and play.state.coat_spent)


func _stop_replay() -> void:
	if _director:
		_director.cancel()
		_director.queue_free()
		_director = null
	Engine.time_scale = 1.0
	if _stage:
		_stage.show_view(false)
	hud.visible = true


## Starts the 3D reel of [param kind]. Any tap skips it.
func _start_reel(kind: Reel) -> void:
	_stop_replay()
	last_reel = kind
	phase = Phase.REPLAY
	play.visible = false
	_backdrop.visible = false
	hud.visible = false
	if _stage == null:
		_stage = ReplayStage.new()
		add_child(_stage)
	_stage.set_hero_color(Upgrades.hero_color(save), int(save["coat"]) >= 0)
	var room: Dictionary = _replay_room
	var title: String = "ROOM CLEAR"
	var sub: String = "%s - %s" % [_replay_place, Reels.counted(_replay_taps.size(), "shift")]
	var color: Color = Palette.CYAN
	match kind:
		Reel.DEATH:
			room = _death_room
			last_timeline = Reels.death_timeline(_death_room, _death_taps, _death_boons)
			title = "NIGHT OVER"
			sub = _death_place
			color = Palette.MAGENTA
		Reel.CHAIN_WIN, Reel.CHAIN_WATCH:
			room = run.chain.room
			last_timeline = Reels.chain_timeline(run.chain)
			title = "BEST CHAIN: %s" % Reels.counted(run.chain.kills, "kill")
			sub = Reels.place(run.chain.level, run.chain.number)
			color = Palette.AMBER
		_:
			last_timeline = TurnEvents.build(_replay_room, _replay_taps, _replay_boons)
	_director = ReplayDirector.new()
	add_child(_director)
	_director.finished.connect(_on_replay_finished)
	_director.play(_stage, room, last_timeline, kind == Reel.DEATH)
	_stage.overlay.show_card(title, sub, color)


func _on_replay_finished() -> void:
	if last_reel == Reel.CLEAR or last_reel == Reel.REVIEW:
		replay_outcome = last_timeline.outcome(_replay_taps.size(), false)
	_finish_replay()


func _finish_replay() -> void:
	_stop_replay()
	match last_reel:
		Reel.CLEAR:
			_after_clear()
		Reel.DEATH, Reel.CHAIN_WIN:
			_show_end_panel()
		_:
			phase = _replay_resume
			play.visible = phase == Phase.FAILED
			_backdrop.visible = play.visible and run.is_last_room()


## Plays [param taps] on [param room] as a reel of [param kind] for the demo and screen recordings.
func demo_reel(kind: Reel, room: Dictionary, taps: Array[int]) -> void:
	_room = room
	_replay_room = room
	_replay_taps = taps.duplicate()
	_replay_boons = BoonSet.new()
	_replay_place = Reels.place(run.floor_now(), run.room_in_floor())
	_death_room = room
	_death_taps = taps.duplicate()
	_death_boons = BoonSet.new()
	_death_place = _replay_place
	_replay_resume = Phase.PLAN
	_start_reel(kind)
