class_name RoundManager
extends Node
## Runs the match: coin flip, topple phase, scatter phase, round end, role swap, score.
##
## Spawns both teams every round, hands each attacker one sandal at a time in queue order, and
## kills attackers hit by the pass sandal. Phases are an unnamed enum so
## [code]RoundManager.TOPPLE[/code] resolves for any script.

## Emitted on every phase change. [param phase] is one of the phase constants.
signal phase_changed(phase: int)
## Emitted when a round ends. [param winner_team] won the round.
signal round_ended(winner_team: int)
## Emitted once when a team reaches [member Tuning.rounds_to_win].
signal match_ended(winner_team: int)
## Emitted when the human starts or ends a build. The 2D camera zooms on [param focus_world_position]
## and the 3D view reads the same signal.
signal build_view_changed(active: bool, focus_world_position: Vector2)
## Emitted by the start countdown. [param step] counts down 3, 2, 1, then 0 when play unlocks.
signal countdown_tick(step: int)

enum { COIN_FLIP, TOPPLE, SCATTER, ROUND_END, MATCH_END } ## Match phases.

## Group the round manager joins.
const GROUP: StringName = &"round_manager"
## Group of the character the human controls.
const HUMAN_GROUP: StringName = &"human_controlled"
## Scene of one character.
const CHARACTER_SCENE_PATH: String = "res://scenes/character.tscn"
## Speed under which a sandal counts as still.
const STILL_SPEED: float = 30.0
## Angle of the first defender when a round starts. The defenders then stay 120 degrees apart.
const ORBIT_START_ANGLE: float = PI * 0.5
## Camera zoom during the last-throw slow-mo.
const LAST_THROW_ZOOM: float = 1.3
## Two kills inside this many milliseconds earn the combo line.
const COMBO_WINDOW_MS: int = 4000
## Models of the regular players, per team. A team keeps its own look and the hero model differs from both.
const REGULAR_MODELS: Array = [
	["character-male-a", "character-female-a", "character-male-c", "character-female-c", "character-male-e", "character-female-e"],
	["character-female-b", "character-male-b", "character-female-d", "character-male-d", "character-female-f", "character-male-f"],
]
const MODEL_DIR: String = "res://assets/kenney/characters/"

## Arena the match runs in.
@export var arena: Arena
## Camera that zooms on the last throw. Optional.
@export var camera: Camera2D
## Parent of the touch controls. A canvas layer is created when null.
@export var touch_ui_parent: Node

## Current phase.
var phase: int = -1
## Team that attacks this round.
var attacking_team: int = 0
## Throws the attackers still have in the topple phase. It drops when a throw has settled,
## so the next attacker's turn starts together with the sandal in their hands.
var throws_left: int = 0
## Seconds left before the defenders win the scatter phase.
var scatter_time_left: float = 0.0
## Round wins per team.
var scores: Array[int] = [0, 0]
## Tuning source. Defaults to [method Tuning.load_default].
var tuning: Tuning
## Controller of the human player.
var human: HumanController
## Hero of each team, indexed by team. A null entry means that team has no hero.
var heroes: Array[HeroDef] = [null, null]

var _character_scene: PackedScene
var _bots_root: Node
var _bots: Dictionary = {}
var _thrown: Array[Sandal] = []
var _throws_done: int = 0
var _total_throws: int = 0
var _awaiting_settle: bool = false
var _idle_time: float = 0.0
var _timer: float = 0.0
var _round_over: bool = false
var _round_winner: int = 0
var _clearing: bool = false
var _countdown_step: int = -1
var _last_kill_ms: int = -1000000
var _throw_clock: float = 0.0
var _build_zoom_tween: Tween
var _human_building: bool = false


func _ready() -> void:
	add_to_group(GROUP)
	if tuning == null:
		tuning = Tuning.load_default()
	if arena == null:
		arena = get_tree().get_first_node_in_group(Arena.GROUP) as Arena
	_character_scene = load(CHARACTER_SCENE_PATH) as PackedScene
	_bots_root = Node.new()
	_bots_root.name = "Bots"
	add_child(_bots_root)
	_build_human()
	if arena == null or _character_scene == null:
		push_error("RoundManager: needs an Arena and %s." % CHARACTER_SCENE_PATH)
		return
	arena.stack.toppled.connect(_on_stack_toppled)
	arena.stack.rebuilt.connect(_on_stack_rebuilt)
	arena.stack.build_started.connect(_on_build_started)
	arena.stack.build_ended.connect(_on_build_ended)
	phase_changed.connect(_play_phase_feedback)
	round_ended.connect(_play_round_end_feedback)
	match_ended.connect(_play_match_end_feedback)
	_pick_default_heroes()
	start_match()
	_hook_hero_select()


func _physics_process(delta: float) -> void:
	match phase:
		COIN_FLIP:
			_timer -= delta
			if _timer <= 0.0:
				_advance_start()
		TOPPLE:
			_update_topple(delta)
		SCATTER:
			_update_scatter(delta)
		ROUND_END:
			_timer -= delta
			if _timer <= 0.0:
				_leave_round_end()


## Sets the hero of each team and starts the match again, so the new heroes stand on the field.
func set_heroes(human_hero: HeroDef, enemy_hero: HeroDef) -> void:
	if tuning.human_team != 0 and tuning.human_team != 1:
		heroes = [human_hero, enemy_hero]
	else:
		heroes[tuning.human_team] = human_hero
		heroes[1 - tuning.human_team] = enemy_hero
	start_match()


func _pick_default_heroes() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	if tuning.human_team != 0 and tuning.human_team != 1:
		heroes[0] = HeroRoster.random_hero(rng)
		heroes[1] = HeroRoster.random_hero(rng)
		return
	var human_id: StringName = &"kilat"
	var settings: Node = get_node_or_null("/root/Settings")
	if settings != null and settings.get("hero_id") is StringName:
		human_id = settings.get("hero_id")
	var human_hero: HeroDef = HeroRoster.get_hero(human_id)
	if human_hero == null:
		human_hero = HeroRoster.random_hero(rng)
	heroes[tuning.human_team] = human_hero
	heroes[1 - tuning.human_team] = HeroRoster.random_hero(rng)


# The select screen opens after the title Play tap. A skipped title skips the select too.
func _hook_hero_select() -> void:
	var title: Node = get_tree().get_first_node_in_group(TitleScreen.GROUP)
	if title == null or not title is TitleScreen or not (title as TitleScreen).is_open():
		return
	(title as TitleScreen).played.connect(_open_hero_select, CONNECT_ONE_SHOT)


func _open_hero_select() -> void:
	if HeroRoster.all().is_empty():
		return
	var select: HeroSelect = HeroSelect.new()
	get_parent().add_child(select)
	select.open(self)


## Resets the score and starts at the coin flip.
func start_match() -> void:
	scores = [0, 0]
	attacking_team = randi() % 2
	_spawn_round()
	_begin_start()


## Restarts the whole match: scores, roles, coin flip, loose sandals, stack and characters.
##
## The scene reloads inside the running engine, so the web page, the fullscreen state and the
## loaded files stay. A reload also rebuilds the HUD, which keeps its own copy of the scores.
## Returns [constant OK] when the reload is queued.
## [b]Note:[/b] This needs the match scene to be the current scene of the tree.
func restart_match() -> Error:
	var feel: Node = get_node_or_null("/root/GameFeel")
	if feel != null:
		feel.call("reset")
	var result: Error = get_tree().reload_current_scene()
	if result != OK:
		push_error("RoundManager: restart failed, the match scene is not the current scene (%s)." % error_string(result))
	return result


## Ends the round for [param winner_team]. Ignored when the round is over.
func end_round(winner_team: int) -> void:
	if _round_over:
		return
	_round_over = true
	_round_winner = winner_team
	scores[winner_team] += 1
	_awaiting_settle = false
	_timer = tuning.round_end_delay
	_set_phase(ROUND_END)
	round_ended.emit(winner_team)


## Enters the coin flip phase. With the countdown on, bodies stand still until play unlocks.
func _begin_start() -> void:
	_timer = maxf(tuning.coin_flip_time, tuning.countdown_intro_time) if tuning.match_countdown else tuning.coin_flip_time
	_countdown_step = -1
	_freeze_all(tuning.match_countdown)
	_set_phase(COIN_FLIP)


## Moves the start sequence on one step: coin flip, then 3, 2, 1, then play.
func _advance_start() -> void:
	if not tuning.match_countdown or _countdown_step == 0:
		_start_topple()
		return
	_countdown_step = 3 if _countdown_step < 0 else _countdown_step - 1
	_timer = tuning.countdown_step_time
	if _countdown_step == 0:
		_freeze_all(false)
		_timer = 0.0
		countdown_tick.emit(0)
		AudioRef.play(&"voice_fight")
		_start_topple()
		return
	countdown_tick.emit(_countdown_step)
	AudioRef.play(&"voice_%s" % ["", "one", "two", "three"][_countdown_step])


func _freeze_all(enabled: bool) -> void:
	for team: int in 2:
		for entry: Variant in arena.get_characters(team):
			(entry as Character).frozen = enabled


func _intro_slot() -> StringName:
	if _is_final_round():
		return &"voice_final_round"
	var round_number: int = scores[0] + scores[1] + 1
	if round_number == 1:
		return &"voice_prepare"
	return StringName("voice_round_%d" % mini(round_number, 5))


func _is_final_round() -> bool:
	var last: int = tuning.rounds_to_win - 1
	return scores[0] >= last and scores[1] >= last


func _play_phase_feedback(new_phase: int) -> void:
	var music: Array[String] = AudioSet.MUSIC_FINAL if _is_final_round() else AudioSet.MUSIC_TOPPLE
	match new_phase:
		COIN_FLIP:
			AudioRef.play(&"coin_tick")
			if tuning.match_countdown:
				AudioRef.play(_intro_slot())
			AudioRef.play_music(music)
		TOPPLE:
			AudioRef.play(&"round_start")
			if not tuning.match_countdown:
				AudioRef.play(&"voice_final_round" if _is_final_round() else &"voice_fight")
			AudioRef.play_music(music)
		SCATTER:
			AudioRef.play(&"coin_end")
			AudioRef.play_music(AudioSet.MUSIC_FINAL)
		MATCH_END:
			AudioRef.play_music([])


func _play_round_end_feedback(winner_team: int) -> void:
	AudioRef.play(&"round_win" if winner_team == tuning.human_team else &"round_lose")


func _play_match_end_feedback(winner_team: int) -> void:
	var won: bool = winner_team == tuning.human_team
	AudioRef.play(&"match_win" if won else &"match_lose")
	var shutout: bool = won and scores[1 - winner_team] == 0
	AudioRef.play(&"voice_flawless" if shutout else (&"voice_you_win" if won else &"voice_you_lose"))


func _set_phase(new_phase: int) -> void:
	phase = new_phase
	phase_changed.emit(phase)


func _start_topple() -> void:
	_set_pickup(false)
	_hold_rings(true)
	var attackers: Array[Character] = _attackers()
	_total_throws = attackers.size() * tuning.throws_per_attacker
	throws_left = _total_throws
	_throws_done = 0
	_idle_time = 0.0
	_awaiting_settle = false
	if not attackers.is_empty():
		_give_throw_sandal(attackers[0])
	_set_phase(TOPPLE)


func _update_topple(delta: float) -> void:
	if not _awaiting_settle:
		if _turn_lost_its_sandal():
			_count_lost_turn()
			return
		_auto_throw_for_idle_thrower(delta)
		return
	_idle_time = _idle_time + delta if _everything_still() else 0.0
	if _idle_time < tuning.topple_settle_time:
		return
	_awaiting_settle = false
	throws_left -= 1
	if throws_left > 0:
		var attackers: Array[Character] = _attackers()
		var turn: int = _throws_done / tuning.throws_per_attacker
		if turn < attackers.size():
			_give_throw_sandal(attackers[turn])
	else:
		_topple_failed()


## True when it is a throw turn but no attacker holds a sandal. A pass that missed its mate leaves
## the sandal on the floor and sends no throw signal, so without this the turn would wait for ever.
func _turn_lost_its_sandal() -> bool:
	for attacker: Character in _attackers():
		if attacker.carried != null:
			return false
	return not _attackers().is_empty()


## Counts the lost turn as a throw and waits for the stray sandal to settle like any other throw.
func _count_lost_turn() -> void:
	for node: Node in get_tree().get_nodes_in_group(Sandal.GROUP):
		var sandal: Sandal = node as Sandal
		if sandal != null and not sandal.is_pass_sandal and sandal.get_parent() == arena and not _thrown.has(sandal):
			_thrown.append(sandal)
	_throws_done += 1
	_idle_time = 0.0
	_awaiting_settle = true
	if _throws_done >= _total_throws:
		_play_last_throw_feel()


## A human who never throws would hold the queue forever. After [member Tuning.topple_throw_seconds]
## the game throws for the human at the stack, so the turn always moves on.
func _auto_throw_for_idle_thrower(delta: float) -> void:
	var holder: Character = null
	for attacker: Character in _attackers():
		if attacker.carried != null and not attacker.carried.is_pass_sandal:
			holder = attacker
			break
	if holder == null or _bots.get(holder) == null:
		return
	var bot: BotController = _bots[holder] as BotController
	if bot.character == holder:
		_throw_clock = 0.0
		return
	_throw_clock += delta
	if _throw_clock >= tuning.topple_throw_seconds:
		_throw_clock = 0.0
		holder.throw_sandal((arena.centre_spot - holder.global_position).normalized(), 1.0)


## A human attacker who holds a stack sandal and never moves blocks the build, because nobody can
## build while a sandal is carried. After [member Tuning.topple_throw_seconds] the sandal drops.
func _drop_for_idle_carrier(delta: float) -> void:
	var holder: Character = null
	for attacker: Character in _attackers():
		if attacker.alive and attacker.carried != null and not attacker.carried.is_pass_sandal:
			holder = attacker
			break
	if holder == null or _bots.get(holder) == null or (_bots[holder] as BotController).character == holder:
		_throw_clock = 0.0
		return
	_throw_clock += delta
	if _throw_clock >= tuning.topple_throw_seconds:
		_throw_clock = 0.0
		var spread: Vector2 = Vector2.from_angle(float(scores[0] + scores[1]) * 2.4) * tuning.build_zone_radius * 0.5
		holder.drop_carried(arena.centre_spot + spread)


func _topple_failed() -> void:
	_round_over = true
	for attacker: Character in _attackers():
		attacker.die()
	_round_over = false
	end_round(1 - attacking_team)


func _start_scatter() -> void:
	_awaiting_settle = false
	scatter_time_left = tuning.scatter_time_limit
	_clear_loose_throw_sandals()
	var defenders: Array[Character] = _defenders()
	if not defenders.is_empty():
		var pass_sandal: Sandal = Sandal.new()
		pass_sandal.tuning = tuning
		pass_sandal.is_pass_sandal = true
		pass_sandal.position = defenders[0].position
		pass_sandal.hit_character.connect(_on_pass_hit.bind(pass_sandal))
		arena.add_child(pass_sandal)
		defenders[0].pick_up(pass_sandal)
	_hold_rings(false)
	_set_pickup(true)
	_set_phase(SCATTER)


## The defenders win when the attackers cannot build in time, so every round ends.
func _update_scatter(delta: float) -> void:
	scatter_time_left = maxf(scatter_time_left - delta, 0.0)
	_drop_for_idle_carrier(delta)
	if scatter_time_left <= 0.0 and not _round_over:
		end_round(1 - attacking_team)


func _leave_round_end() -> void:
	if scores[_round_winner] >= tuning.rounds_to_win:
		_set_phase(MATCH_END)
		match_ended.emit(_round_winner)
		return
	attacking_team = 1 - attacking_team
	_spawn_round()
	if tuning.match_countdown:
		_begin_start()
	else:
		_start_topple()


func _spawn_round() -> void:
	_round_over = false
	_clear_round()
	if SkinRef.follow_view_setting():
		arena.rebuild_art()
	arena.stack.reset()
	var attackers_count: int = tuning.team_size
	var spacing: float = deg_to_rad(tuning.throw_ring_spacing_degrees)
	for index: int in attackers_count:
		var slot: float = float(index) - float(attackers_count - 1) * 0.5
		var position: Vector2 = arena.centre_spot + Vector2.from_angle(PI + slot * spacing) * tuning.throw_radius
		_spawn_character(attacking_team, Character.Role.ATTACKER, position, index)
	for index: int in tuning.team_size:
		var angle: float = ORBIT_START_ANGLE + TAU * float(index) / float(tuning.team_size)
		var position: Vector2 = arena.centre_spot + Vector2.from_angle(angle) * tuning.orbit_radius
		_spawn_character(1 - attacking_team, Character.Role.DEFENDER, position, index)
	_attach_controllers()
	_hold_rings(true)


func _spawn_character(team: int, role: Character.Role, position: Vector2, seat: int) -> void:
	var character: Character = _character_scene.instantiate() as Character
	character.configure(team, role, tuning, SkinRef.get_visual_set())
	if seat == 0:
		character.hero = heroes[team]
	var models: Array = REGULAR_MODELS[team]
	character.model_path = MODEL_DIR + String(models[seat % models.size()]) + ".glb"
	character.arena = arena
	character.stack = arena.stack
	character.pickup_enabled = false
	character.facing_angle = (arena.centre_spot - position).angle()
	character.position = position
	character.threw.connect(_on_threw)
	character.died.connect(_on_character_died)
	arena.add_child(character)
	arena.register_character(character)


func _attach_controllers() -> void:
	var human_character: Character = null
	for team: int in 2:
		for entry: Variant in arena.get_characters(team):
			var character: Character = entry as Character
			var bot: BotController = BotController.new()
			bot.bind(arena, self, tuning)
			_bots_root.add_child(bot)
			bot.attach(character)
			_bots[character] = bot
			if human_character == null and team == tuning.human_team:
				human_character = character
	if human_character != null:
		_bots[human_character].detach()
		human.attach(human_character)


func _clear_round() -> void:
	_clearing = true
	human.detach()
	for bot: Node in _bots_root.get_children():
		_bots_root.remove_child(bot)
		bot.queue_free()
	_bots.clear()
	for team: int in 2:
		for entry: Variant in arena.get_characters(team):
			var character: Character = entry as Character
			character.remove_from_group(HUMAN_GROUP)
			arena.remove_child(character)
			character.queue_free()
	arena.clear_characters()
	_remove_non_stack_sandals()
	_thrown.clear()
	_clearing = false


func _remove_non_stack_sandals() -> void:
	for node: Node in get_tree().get_nodes_in_group(Sandal.GROUP):
		if node.get_parent() != arena.stack:
			node.get_parent().remove_child(node)
			node.queue_free()


func _clear_loose_throw_sandals() -> void:
	# Hands first, so no attacker keeps a pointer to a sandal that is about to be freed.
	for attacker: Character in _attackers():
		if attacker.carried != null and is_instance_valid(attacker.carried) and not attacker.carried.is_pass_sandal:
			attacker.carried = null
	# The stack sandals are children of the stack. Every other sandal is a throw sandal, including a passed one
	# that no throw signal ever reported.
	for node: Node in get_tree().get_nodes_in_group(Sandal.GROUP):
		var sandal: Sandal = node as Sandal
		if sandal != null and not sandal.is_pass_sandal and sandal.get_parent() == arena:
			arena.remove_child(sandal)
			sandal.queue_free()
	_thrown.clear()


func _build_human() -> void:
	human = HumanController.new()
	human.name = "Human"
	add_child(human)
	var parent: Node = touch_ui_parent
	if parent == null:
		var layer: CanvasLayer = CanvasLayer.new()
		layer.name = "TouchUi"
		layer.layer = 2
		add_child(layer)
		parent = layer
	human.build_touch_ui(parent, arena)
	var overlay: BuildOverlay = BuildOverlay.new()
	overlay.name = "BuildOverlay"
	overlay.round_manager = self
	overlay.tuning = tuning
	overlay.stack = arena.stack
	parent.add_child(overlay)
	human.character_changed.connect(_on_human_changed)


func _give_throw_sandal(attacker: Character) -> void:
	_throw_clock = 0.0
	var sandal: Sandal = Sandal.new()
	sandal.tuning = tuning
	sandal.position = attacker.position
	arena.add_child(sandal)
	attacker.pick_up(sandal)


func _hold_rings(enabled: bool) -> void:
	for team: int in 2:
		for entry: Variant in arena.get_characters(team):
			var character: Character = entry as Character
			if not enabled:
				character.hold_on_ring(arena.centre_spot, 0.0, 0.0)
			elif character.role == Character.Role.ATTACKER:
				character.hold_on_ring(arena.centre_spot, tuning.throw_radius, tuning.move_speed)
			else:
				character.hold_on_ring(arena.centre_spot, tuning.orbit_radius, tuning.orbit_radius * tuning.orbit_speed, true)


func _set_pickup(enabled: bool) -> void:
	for team: int in 2:
		for entry: Variant in arena.get_characters(team):
			(entry as Character).pickup_enabled = enabled


func _attackers() -> Array[Character]:
	return _alive_team(attacking_team)


func _defenders() -> Array[Character]:
	return _alive_team(1 - attacking_team)


func _alive_team(team: int) -> Array[Character]:
	var members: Array[Character] = []
	for entry: Variant in arena.get_characters(team):
		var character: Character = entry as Character
		if character != null and character.alive:
			members.append(character)
	return members


func _everything_still() -> bool:
	for node: Node in get_tree().get_nodes_in_group(Sandal.GROUP):
		var sandal: Sandal = node as Sandal
		if sandal == null or sandal.freeze:
			continue
		if sandal.in_flight or sandal.linear_velocity.length() > STILL_SPEED:
			return false
	return true


func _on_threw(sandal: Sandal) -> void:
	if phase != TOPPLE:
		return
	_throws_done += 1
	_thrown.append(sandal)
	_idle_time = 0.0
	_awaiting_settle = true
	if _throws_done >= _total_throws:
		_play_last_throw_feel()


func _on_stack_toppled() -> void:
	if phase == TOPPLE:
		_start_scatter()


func _on_stack_rebuilt() -> void:
	if phase == SCATTER:
		end_round(attacking_team)


func _on_build_started(builder: Character) -> void:
	if builder != null and builder.is_in_group(HUMAN_GROUP):
		_human_building = true
		build_view_changed.emit(true, arena.stack.global_position)
		_zoom_camera(tuning.build_zoom)


func _on_build_ended(_builder: Character, _completed: bool) -> void:
	if _human_building:
		_human_building = false
		build_view_changed.emit(false, arena.stack.global_position)
		_zoom_camera(1.0)


func _zoom_camera(target: float) -> void:
	if camera == null:
		return
	if _build_zoom_tween != null:
		_build_zoom_tween.kill()
	_build_zoom_tween = create_tween().set_ignore_time_scale(true)
	_build_zoom_tween.tween_property(camera, "zoom", Vector2.ONE * target, 0.25)


func _on_character_died(_character: Character = null) -> void:
	if _round_over or phase != SCATTER:
		return
	if _alive_team(attacking_team).is_empty():
		end_round(1 - attacking_team)


func _on_pass_hit(character: Character, sandal: Sandal) -> void:
	if phase != SCATTER or character.role != Character.Role.ATTACKER or not character.alive:
		return
	if character.is_invulnerable():
		return
	if character.can_block():
		sandal.ricochet(character)
		character.block(character.global_position - sandal.global_position)
		return
	var feel: Node = get_node_or_null("/root/GameFeel")
	if feel != null:
		feel.call("hit_stop", tuning.hit_stop_duration)
	var skin: VisualSet = SkinRef.get_visual_set()
	if skin != null:
		var effect: EntityVisual = skin.make(&"hit_effect")
		if effect != null:
			effect.position = character.position
			arena.add_child(effect)
	AudioRef.play(&"pass_kill")
	var now_ms: int = Time.get_ticks_msec()
	AudioRef.play(&"voice_combo" if now_ms - _last_kill_ms <= COMBO_WINDOW_MS else &"voice_hype")
	_last_kill_ms = now_ms
	FxRef.burst(&"hit", character.position)
	var travel: Vector2 = sandal.linear_velocity
	if travel.length_squared() < 1.0:
		travel = character.global_position - sandal.global_position
	character.die()
	# A dead body has no collision, so without this the sandal flies on and kills the whole line.
	sandal.halt()
	# The tombstone stands where the body fell and would hide a sandal that stops inside it.
	sandal.global_position = character.global_position - travel.normalized() * (tuning.character_radius + tuning.sandal_radius + 6.0)
	var inside: Rect2 = Rect2(tuning.arena_centre - tuning.arena_half_extents, tuning.arena_half_extents * 2.0).grow(-tuning.sandal_radius)
	sandal.global_position = Vector2(
		clampf(sandal.global_position.x, inside.position.x, inside.end.x),
		clampf(sandal.global_position.y, inside.position.y, inside.end.y))


func _on_human_changed(previous: Character, current: Character) -> void:
	if _clearing:
		return
	if previous != null and is_instance_valid(previous):
		previous.remove_from_group(HUMAN_GROUP)
		var old_bot: BotController = _bots.get(previous) as BotController
		if old_bot != null and previous.alive:
			old_bot.attach(previous)
	if current != null:
		current.add_to_group(HUMAN_GROUP)
		var bot: BotController = _bots.get(current) as BotController
		if bot != null:
			bot.detach()


func _play_last_throw_feel() -> void:
	var feel: Node = get_node_or_null("/root/GameFeel")
	if feel != null:
		feel.call("slow_motion", tuning.slow_motion_scale, tuning.slow_motion_duration)
	if camera == null:
		return
	var zoom_in: Tween = create_tween().set_ignore_time_scale(true)
	zoom_in.tween_property(camera, "zoom", Vector2.ONE * LAST_THROW_ZOOM, 0.2)
	zoom_in.tween_interval(tuning.slow_motion_duration)
	zoom_in.tween_property(camera, "zoom", Vector2.ONE, 0.3)
