class_name RoomPlay
extends Node2D
## Live play of one room: draws it, takes a tapped gunman, and animates the resolution in slow motion.

## Emitted when a swap finishes playing out.
signal resolved(hero_dead: bool, alive_left: int)

## Pixels around a gunman that count as a tap on him.
const TAP_RADIUS: float = 52.0
## Seconds into the resolution when gunmen fire.
const FIRE_T: float = 0.1
## Seconds into the resolution when the hero shoots.
const HERO_SHOT_T: float = FIRE_T
## Seconds a bullet takes to cross its line.
const TRAVEL_T: float = 0.16
## Seconds of resolution before the result shows.
const END_T: float = 0.36
## Hit stop on each kill, in milliseconds.
const HIT_STOP_MS: int = 60
## Seconds the end-of-turn steps and arrivals take.
const STEP_T: float = 0.2
## Engine time scale during the resolution.
const SLOWMO_SCALE: float = 0.25
## Particles in the spark where a wasted strike hits cover.
const WASTED_SPARKS: int = 10
## Seconds the hero fades out, then pops in, when the swap line crosses a wall. Each half takes this long.
const BLINK_HALF_T: float = 0.06
## Radius in pixels where a blink ring starts.
const BLINK_RING_R: float = 14.0

## Room state, read by the smoke test and the run flow.
var state: RoomState
## Camera that gets the kill punch.
var camera: Camera2D
## Boons of the run, read by every resolution.
var boons: BoonSet = BoonSet.new()
## True when the last resolution ended with a knife in the hero.
var stabbed: bool = false
## Color of the hero figure, his strike line, and his swap smear. The equipped coat sets it.
var hero_color: Color = Palette.INK
## True in the boss room: the floor lets the backdrop show through.
var boss_look: bool = false

var _planning: bool = false
var _resolving: bool = false
var _guns: Array[Figure] = []
var _hero: Figure
var _res: HotSwapRules.Resolution
var _res_t: float = 0.0
var _hero_shot_done: bool = false
var _hero_dead_shown: bool = false
var _bullet_lines: Array[Line2D] = []
var _hover: int = -1
var _hit_stop_until_ms: int = 0
var _slowmo_tween: Tween
var _punch_tween: Tween
var _steps_tween: Tween
var _pending_notes: Array[Dictionary] = []


func _process(delta: float) -> void:
	if not _resolving or Time.get_ticks_msec() < _hit_stop_until_ms:
		return
	_res_t += delta
	if not _hero_shot_done and _res_t >= HERO_SHOT_T:
		_play_hero_shot()
	_update_bullets()
	while not _pending_notes.is_empty() and _res_t >= float(_pending_notes[0]["t"]):
		var note: Dictionary = _pending_notes.pop_front()
		_float_text(note["pos"], str(note["text"]))
	if _res_t >= END_T:
		_finish_resolution()


func _exit_tree() -> void:
	Engine.time_scale = 1.0


func _draw() -> void:
	if state == null:
		return
	draw_rect(Rooms.FLOOR, Color("11111a", 0.8 if boss_look else 1.0))
	draw_rect(Rooms.FLOOR, Color(Palette.INK, 0.25), false, 2.0)
	for cover: Rect2 in state.covers:
		draw_rect(cover, Color("2a2a38"))
		draw_rect(cover, Color(Palette.INK, 0.6), false, 2.0)
	if not _planning:
		return
	draw_arc(state.hero, 22.0, 0.0, TAU, 32, Color(Palette.AMBER, 0.6), 2.0)
	RoomMarks.draw(self, state)
	for i: int in _guns.size():
		if not state.alive[i]:
			continue
		var gun_pos: Vector2 = state.guns[i]
		var ring_alpha: float = 0.9 if i == _hover else 0.35
		draw_arc(gun_pos, 34.0, 0.0, TAU, 32, Color(Palette.MAGENTA, ring_alpha), 2.0)
		if state.kinds[i] == RoomState.Kind.KNIFE or i in _jammed_now():
			continue
		var end: Vector2 = HotSwapRules.clip_to_cover(state.covers, gun_pos, state.hero)
		draw_dashed_line(gun_pos, end, Palette.AMBER, 3.0, 12.0)


## Loads [param room] and starts planning.
func load_room(room: Dictionary) -> void:
	_reset_effects()
	state = RoomState.from_room(room)
	_build_figures()
	for i: int in _guns.size():
		_guns[i].tag = str(i + 1)


## Puts the room back to [param snapshot], a state saved before a shift, and starts planning. Used by undo.
func restore(snapshot: RoomState) -> void:
	_reset_effects()
	state = snapshot.clone()
	_build_figures()


## Returns true when the last swap killed the hero.
func last_hero_dead() -> bool:
	return _res != null and _res.hero_dead


## Shows or hides the telegraph lines and gunman rings, and resets the standing poses.
func set_planning(on: bool) -> void:
	_planning = on
	if on:
		for i: int in _guns.size():
			if state.alive[i]:
				_guns[i].aim_dir = _guns[i].position.direction_to(_hero.position)
				_guns[i].pose = Figure.Pose.AIM
		_hero.pose = Figure.Pose.STAND
	queue_redraw()


## Returns true while a swap plays out.
func is_resolving() -> bool:
	return _resolving


## Marks gunman [param index] as hovered, or -1 for none.
func set_hover(index: int) -> void:
	if index != _hover:
		_hover = index
		queue_redraw()


## Returns the gunman nearest to [param screen_pos] within tap range, or -1.
func gun_at_screen(screen_pos: Vector2) -> int:
	var world_pos: Vector2 = get_canvas_transform().affine_inverse() * screen_pos
	var best: int = -1
	var best_dist: float = TAP_RADIUS
	for i: int in _guns.size():
		if not state.alive[i]:
			continue
		var dist: float = state.guns[i].distance_to(world_pos)
		if dist <= best_dist:
			best_dist = dist
			best = i
	return best


## Returns the on-screen position of gunman [param index].
func gun_screen_position(index: int) -> Vector2:
	return get_canvas_transform() * state.guns[index]


## Returns true if [param index] is a gunman who is still alive.
func is_alive(index: int) -> bool:
	return index >= 0 and index < _guns.size() and state.alive[index]


## Returns the final state summary after [param swap_count] swaps, to compare with the replay.
func outcome(swap_count: int) -> Dictionary:
	return {"swaps": swap_count, "alive": state.alive_count(), "hero": state.hero, "guns": state.guns, "dead": _res.hero_dead}


## Returns how many gunmen the last swap killed: the hero strike plus friendly fire.
func last_kills() -> int:
	return _res.kill_count() if _res != null else 0


## Swaps with gunman [param tap] and starts the resolution in the same frame.
func begin_swap(tap: int) -> void:
	_res = HotSwapRules.resolve(state, tap, boons)
	stabbed = _res.stabbed
	var through_wall: bool = HotSwapRules.crosses_cover(state.covers, _res.old_hero, _res.old_gun)
	if through_wall:
		_blink(_hero, _res.old_hero, _res.old_gun)
		_blink(_guns[tap], _res.old_gun, _res.old_hero)
	else:
		_spawn_smear(_res.old_hero, _res.old_gun, hero_color)
		_spawn_smear(_res.old_gun, _res.old_hero, Palette.MAGENTA)
		_hero.position = _res.old_gun
		_guns[tap].position = _res.old_hero
	_hero.pose = Figure.Pose.STAND
	_guns[tap].pose = Figure.Pose.STAND
	for fig: Figure in _guns:
		fig.tag = ""
	_planning = false
	_resolving = true
	_res_t = 0.0
	_hero_shot_done = false
	_hero_dead_shown = false
	queue_redraw()
	for shot: HotSwapRules.Shot in _res.shots:
		_bullet_lines.append(_make_trail(shot))
	for i: int in _guns.size():
		if _guns[i].pose != Figure.Pose.FALL and i != tap:
			_guns[i].aim_dir = _guns[i].position.direction_to(_res.old_hero)
			_guns[i].pose = Figure.Pose.AIM
	_hero.aim_dir = _hero.position.direction_to(_res.impact if _res.wasted else _guns[_res.target].position)
	_queue_notes()
	_slowmo_tween = create_tween().set_ignore_time_scale(true)
	_slowmo_tween.tween_property(Engine, "time_scale", SLOWMO_SCALE, 0.05)
	_slowmo_tween.tween_interval(0.55)
	_slowmo_tween.tween_property(Engine, "time_scale", 1.0, 0.2)


func _build_figures() -> void:
	for i: int in state.guns.size():
		var gun: Figure = _make_gun(i)
		if not state.alive[i]:
			gun.pose = Figure.Pose.FALL
			gun.modulate = Color(1, 1, 1, 0.6)
		_guns.append(gun)
	_hero = _make_figure(hero_color, state.hero)
	_resolving = false
	set_planning(true)


func _reset_effects() -> void:
	if _punch_tween:
		_punch_tween.kill()
	if _slowmo_tween:
		_slowmo_tween.kill()
	if _steps_tween:
		_steps_tween.kill()
	_pending_notes.clear()
	Engine.time_scale = 1.0
	if camera:
		camera.offset = Vector2.ZERO
		camera.zoom = Vector2.ONE
	for fig: Figure in _guns:
		fig.queue_free()
	_guns.clear()
	if _hero:
		_hero.queue_free()
	for line: Line2D in _bullet_lines:
		line.queue_free()
	_bullet_lines.clear()


func _make_gun(index: int) -> Figure:
	var gun: Figure = _make_figure(Palette.MAGENTA, state.guns[index])
	gun.kind = state.kinds[index]
	gun.facing = state.facings[index]
	return gun


func _jammed_now() -> Array[int]:
	var out: Array[int] = []
	for event: Dictionary in state.events_now("jam"):
		var params: Dictionary = event["params"]
		out.append(int(params["gun"]))
	return out


func _make_figure(color: Color, pos: Vector2) -> Figure:
	var fig: Figure = Figure.new()
	fig.color = color
	fig.position = pos
	add_child(fig)
	return fig


func _make_trail(shot: HotSwapRules.Shot) -> Line2D:
	var line: Line2D = Line2D.new()
	line.width = 4.0
	line.default_color = Palette.AMBER
	line.add_point(shot.from)
	line.add_point(shot.from)
	add_child(line)
	return line


func _spawn_smear(from: Vector2, to: Vector2, color: Color) -> void:
	var line: Line2D = Line2D.new()
	line.width = 26.0
	line.default_color = Color(color, 0.55)
	line.add_point(from)
	line.add_point(to)
	add_child(line)
	var tween: Tween = create_tween().set_ignore_time_scale(true)
	tween.tween_property(line, "modulate:a", 0.0, 0.12)
	tween.tween_callback(line.queue_free)


## Swaps [param fig] to [param to] without a flight, since the smear would cross a wall. A ghost fades out at [param from] with a ring, then the figure pops in at [param to] with a ring.
func _blink(fig: Figure, from: Vector2, to: Vector2) -> void:
	var ghost: Figure = _make_figure(fig.color, from)
	ghost.kind = fig.kind
	ghost.facing = fig.facing
	ghost.aim_dir = fig.aim_dir
	var fade: Tween = create_tween().set_ignore_time_scale(true)
	fade.tween_property(ghost, "modulate:a", 0.0, BLINK_HALF_T)
	fade.tween_callback(ghost.queue_free)
	_blink_ring(from, fig.color, 0.0)
	fig.position = to
	fig.modulate.a = 0.0
	create_tween().set_ignore_time_scale(true).tween_property(fig, "modulate:a", 1.0, BLINK_HALF_T).set_delay(BLINK_HALF_T)
	_blink_ring(to, fig.color, BLINK_HALF_T)


## Pops a ring at [param at] that grows and fades over one blink half, after [param delay] seconds.
func _blink_ring(at: Vector2, color: Color, delay: float) -> void:
	var ring: Line2D = Line2D.new()
	for step: int in 25:
		ring.add_point(Vector2.from_angle(TAU * float(step) / 24.0) * BLINK_RING_R)
	ring.position = at
	ring.width = 3.0
	ring.default_color = Color(color, 0.9)
	ring.modulate.a = 0.0
	add_child(ring)
	var tween: Tween = create_tween().set_ignore_time_scale(true)
	tween.tween_interval(delay)
	tween.tween_callback(func() -> void: ring.modulate.a = 1.0)
	tween.tween_property(ring, "scale", Vector2.ONE * 2.4, BLINK_HALF_T * 2.0 - delay).from(Vector2.ONE * 0.6)
	tween.parallel().tween_property(ring, "modulate:a", 0.0, BLINK_HALF_T * 2.0 - delay)
	tween.tween_callback(ring.queue_free)


func _play_hero_shot() -> void:
	_hero_shot_done = true
	_hero.pose = Figure.Pose.AIM
	if _res.wasted:
		_play_wasted_strike()
	for target: int in _res.targets:
		var victim: Figure = _guns[target]
		var line: Line2D = Line2D.new()
		line.width = 5.0
		line.default_color = hero_color
		line.add_point(_hero.position)
		line.add_point(victim.position)
		add_child(line)
		_fade_out(line, 0.2)
		if target in _res.struck:
			_kill_figure(victim, victim.position - _hero.position)


## Draws the tracer to the cover block it hit and pops a small spark there, since cover hides every gunman.
func _play_wasted_strike() -> void:
	var line: Line2D = Line2D.new()
	line.width = 5.0
	line.default_color = hero_color
	line.add_point(_hero.position)
	line.add_point(_res.impact)
	add_child(line)
	_fade_out(line, 0.2)
	_burst(_res.impact, Palette.AMBER, _hero.position.direction_to(_res.impact) * -1.0, WASTED_SPARKS)


func _update_bullets() -> void:
	var head: float = clampf((_res_t - FIRE_T) / TRAVEL_T, 0.0, 1.0)
	for i: int in _res.shots.size():
		var shot: HotSwapRules.Shot = _res.shots[i]
		var line: Line2D = _bullet_lines[i]
		line.set_point_position(0, shot.from.lerp(shot.to, maxf(head - 0.3, 0.0)))
		line.set_point_position(1, shot.from.lerp(shot.to, head))
		line.visible = _res_t >= FIRE_T
		for v: int in shot.victims.size():
			var victim: Figure = _guns[shot.victims[v]]
			if head >= shot.victim_fracs[v] and victim.pose != Figure.Pose.FALL:
				_kill_figure(victim, shot.to - shot.from)
		if shot.hero_frac >= 0.0 and head >= shot.hero_frac and not _hero_dead_shown:
			_hero_dead_shown = true
			_kill_figure(_hero, shot.to - shot.from)
	if head >= 1.0:
		for line: Line2D in _bullet_lines:
			if line.modulate.a == 1.0:
				_fade_out(line, 0.15)


func _kill_figure(fig: Figure, push: Vector2) -> void:
	fig.pose = Figure.Pose.FALL
	fig.fall_side = 1.0 if push.x >= 0.0 else -1.0
	fig.modulate = Color(1, 1, 1, 0.6)
	_hit_stop_until_ms = Time.get_ticks_msec() + HIT_STOP_MS
	_punch_camera(fig.position)
	_burst(fig.position, fig.color, push.normalized())
	var tween: Tween = create_tween().set_ignore_time_scale(true)
	tween.tween_property(fig, "position:x", fig.position.x + push.normalized().x * 14.0, 0.15)


func _punch_camera(at: Vector2) -> void:
	camera.zoom = Vector2(1.05, 1.05)
	camera.offset = (at - camera.position) * 0.04
	_punch_tween = create_tween().set_ignore_time_scale(true).set_parallel(true)
	_punch_tween.tween_property(camera, "zoom", Vector2.ONE, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_punch_tween.tween_property(camera, "offset", Vector2.ZERO, 0.2)


func _burst(at: Vector2, color: Color, dir: Vector2, amount: int = 18) -> void:
	var puff: CPUParticles2D = CPUParticles2D.new()
	puff.position = at
	puff.one_shot = true
	puff.explosiveness = 1.0
	puff.amount = amount
	puff.lifetime = 0.5
	puff.direction = dir
	puff.spread = 70.0
	puff.gravity = Vector2.ZERO
	puff.initial_velocity_min = 90.0
	puff.initial_velocity_max = 260.0
	puff.scale_amount_min = 2.0
	puff.scale_amount_max = 4.5
	puff.color = color
	puff.emitting = true
	puff.finished.connect(puff.queue_free)
	add_child(puff)


func _fade_out(line: Line2D, seconds: float) -> void:
	var tween: Tween = create_tween().set_ignore_time_scale(true)
	tween.tween_property(line, "modulate:a", 0.0, seconds)


func _finish_resolution() -> void:
	if _slowmo_tween:
		_slowmo_tween.kill()
	Engine.time_scale = 1.0
	for line: Line2D in _bullet_lines:
		line.queue_free()
	_bullet_lines.clear()
	_resolving = false
	if _res.stabbed:
		_kill_figure(_hero, Vector2.UP)
		_float_text(_hero.position + Vector2(-48, -52), "IN RANGE")
	if _res.steps.is_empty() and _res.spawns.is_empty():
		resolved.emit(_res.hero_dead, state.alive_count())
		return
	_play_end_of_turn()


## Moves the stepping gunmen, drops in the reinforcements, then reports the result.
func _play_end_of_turn() -> void:
	_steps_tween = create_tween().set_ignore_time_scale(true).set_parallel(true)
	for step: Dictionary in _res.steps:
		var fig: Figure = _guns[int(step["gun"])]
		_steps_tween.tween_property(fig, "position", step["to"], STEP_T).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	for index: int in _res.spawns:
		var fig: Figure = _make_gun(index)
		fig.modulate = Color(1, 1, 0.6, 0.0)
		_guns.append(fig)
		_steps_tween.tween_property(fig, "modulate:a", 1.0, STEP_T)
		_float_text(state.guns[index] + Vector2(-16, -44), "+1")
	_steps_tween.chain().tween_callback(_report_after_steps)


func _report_after_steps() -> void:
	resolved.emit(_res.hero_dead, state.alive_count())


func _queue_notes() -> void:
	_pending_notes.clear()
	if _res.wasted and Rooms.COVER_ENABLED:
		_pending_notes.append({"t": HERO_SHOT_T, "pos": _res.impact + Vector2(-34, -48), "text": "COVER"})
	for target: int in _res.blocked_strikes:
		_pending_notes.append({"t": HERO_SHOT_T, "pos": _guns[target].position + Vector2(-40, -48), "text": "BLOCKED"})
	for shot: HotSwapRules.Shot in _res.shots:
		if shot.blocked_by >= 0:
			_pending_notes.append({"t": FIRE_T + TRAVEL_T, "pos": _guns[shot.blocked_by].position + Vector2(-40, -48), "text": "BLOCKED"})
	if _res.coat_used:
		_pending_notes.append({"t": FIRE_T + TRAVEL_T, "pos": _hero.position + Vector2(-26, -48), "text": "COAT"})
	_pending_notes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["t"]) < float(b["t"]))


func _float_text(at: Vector2, text: String) -> void:
	var label: Label = Label.new()
	label.text = text
	label.position = at
	label.add_theme_font_size_override("font_size", 26)
	label.add_theme_color_override("font_color", Palette.INK)
	label.add_theme_color_override("font_outline_color", Palette.PANEL)
	label.add_theme_constant_override("outline_size", 8)
	add_child(label)
	var tween: Tween = create_tween().set_ignore_time_scale(true).set_parallel(true)
	tween.tween_property(label, "position:y", at.y - 22.0, 0.7)
	tween.tween_property(label, "modulate:a", 0.0, 0.7).set_delay(0.3)
	tween.chain().tween_callback(label.queue_free)
