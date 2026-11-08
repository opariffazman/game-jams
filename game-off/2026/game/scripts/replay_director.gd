class_name ReplayDirector
extends Node
## Plays a [TurnEvents] timeline as a first-person shot from the hero. Reads events only and applies no game rules.

## Emitted after the closing hold, once the title card can show.
signal finished

## Seconds of the opening shot.
const OPEN_S: float = 0.5
## Seconds of the swap dash.
const DASH_S: float = 0.15
## Seconds to look at the swapped gunman before the shot resolves.
const ARRIVE_S: float = 0.2
## Seconds between turns to turn toward the next swap.
const GAP_S: float = 0.2
## Seconds of the closing hold.
const CLOSE_S: float = 0.5
## Seconds the end-of-turn steps take.
const STEP_S: float = 0.25
## Slow-motion time scale during the resolution.
const SLOWMO_SCALE: float = 0.25
## Hit stop in milliseconds on each kill.
const HIT_STOP_MS: int = 60
## Distance in world units from the lens where the hero's tracer starts, so it never fills the frame.
const HERO_TRACER_START: float = 2.0
## Game seconds the hero turns to aim.
const AIM_S: float = 0.05
## Game seconds for a gunman bullet to cross its whole line.
const TRAVEL_S: float = 0.18
## Field of view in degrees at the peak of the dash kick.
const KICK_FOV: float = 115.0
## Seconds of the dim cut that replaces a dash across a wall: half in, half out.
const CUT_S: float = 0.08
## Slow-motion time scale while the bullet that ends the run arrives.
const FATAL_SLOW: float = 0.15
## Seconds, in real time, of the fade to black.
const FADE_S: float = 0.7
## Seconds, in real time, the black holds before the reel ends.
const BLACK_HOLD_S: float = 0.3
## Seconds a knife takes to lunge at the camera.
const LUNGE_S: float = 0.3
## Distance in world units where the lunging knife stops in front of the camera.
const LUNGE_STOP: float = 0.9

var _stage: ReplayStage
var _cancelled: bool = false
var _slow: float = 1.0
var _stop_until_ms: int = 0
var _slow_tween: Tween
var _ended_dark: bool = false


func _process(_delta: float) -> void:
	Engine.time_scale = 0.0 if Time.get_ticks_msec() < _stop_until_ms else _slow


func _exit_tree() -> void:
	Engine.time_scale = 1.0


## Plays [param timeline] on [param stage], from [member TurnEvents.start_room]. [param room] is the room it was built from. Awaitable.
## With [param fade_out] the reel ends in a fade to black, as the death reel does. Stops quietly after [method cancel].
func play(stage: ReplayStage, room: Dictionary, timeline: TurnEvents, fade_out: bool = false) -> void:
	_stage = stage
	room = timeline.start_room if not timeline.start_room.is_empty() else room
	stage.build(room)
	stage.show_view(true)
	var turns: Array[Dictionary] = timeline.turns
	if turns.is_empty():
		finished.emit()
		return
	var first_plan: Array[Dictionary] = turns[0]["plan"]
	stage.fx.show_telegraphs(_lines3(first_plan, -1))
	var rig: Node3D = stage.rig()
	var centroid: Vector3 = _alive_centroid(room)
	rig.rotation.y = ReplayStage.yaw_to(rig.position, centroid)
	var forward: Vector3 = -rig.basis.z
	create_tween().tween_property(rig, "position", rig.position + forward * 0.45, OPEN_S).set_trans(Tween.TRANS_SINE)
	if not await _wait(OPEN_S):
		return
	for i: int in turns.size():
		if i > 0:
			stage.fx.show_telegraphs(_lines3(turns[i]["plan"], -1))
			_tween_yaw(ReplayStage.yaw_to(rig.position, stage.figures[int(turns[i]["tap"])].position), GAP_S)
			if not await _wait(GAP_S):
				return
		if not await _play_turn(turns[i]):
			return
		if _ended_dark:
			break
	if not _ended_dark:
		if not await _wait(CLOSE_S):
			return
		if fade_out:
			stage.overlay.fade_to_black(FADE_S)
			if not await _wait_real(FADE_S + BLACK_HOLD_S):
				return
	Engine.time_scale = 1.0
	finished.emit()


## Stops before the next step and restores normal time.
func cancel() -> void:
	_cancelled = true
	if _slow_tween:
		_slow_tween.kill()
	Engine.time_scale = 1.0
	queue_free()


func _play_turn(turn: Dictionary) -> bool:
	var events: Array = turn["events"]
	var swap: Dictionary = events[0]
	var swapped: Figure3D = _stage.figures[int(swap["gun"])]
	var old_hero: Vector3 = ReplayStage.to3(swap["hero_from"])
	var arrival: Vector3 = ReplayStage.to3(swap["gun_from"])
	for figure: Figure3D in _stage.figures:
		figure.set_ring(false)
		figure.set_jam(false)
		figure.face(old_hero)
	for event: Dictionary in events:
		if event["type"] == "jam":
			_stage.figures[int(event["gun"])].set_jam(true)
	swapped.position = old_hero
	swapped.set_ring(true)
	swapped.face(arrival)
	_stage.fx.show_telegraphs(_lines3(turn["plan"], int(swap["gun"])))
	if bool(swap.get("crosses_cover", false)):
		_cut(arrival, old_hero)
	else:
		_dash(arrival, old_hero)
	if not await _wait(DASH_S + ARRIVE_S):
		return false
	_set_slow(SLOWMO_SCALE, 0.05)
	var hero_shot: Dictionary = _first_of(events, "hero_shot")
	var victim_pos: Vector3 = _strike_point(hero_shot)
	_tween_yaw(ReplayStage.yaw_to(arrival, victim_pos), AIM_S)
	if not await _wait(AIM_S + 0.03):
		return false
	var fire_s: float = 0.08
	var fatal: Dictionary = _first_of(events, "hero_hit")
	var stab: Dictionary = _first_of(events, "knife_contact")
	var ends_run: bool = not fatal.is_empty() or not stab.is_empty()
	if not fatal.is_empty():
		_set_slow(FATAL_SLOW, 0.05)
	for event: Dictionary in events:
		match event["type"]:
			"hero_shot":
				_fire_hero(_strike_point(event), bool(event["blocked"]) or bool(event["wasted"]))
			"shot":
				_fire_shot(event, fire_s)
			"death":
				_schedule_death(event, fire_s)
			"coat_block":
				_after(fire_s + TRAVEL_S * float(event["frac"]), func() -> void: _stage.fx.coat_ring(_stage.camera))
	if ends_run:
		return await _play_ending(fatal, stab, arrival, fire_s)
	_after(fire_s, func() -> void: _tween_yaw(ReplayStage.yaw_to(arrival, old_hero), TRAVEL_S))
	if not await _wait(fire_s + TRAVEL_S + 0.06):
		return false
	_set_slow(1.0, 0.2)
	_tween_fov(ReplayStage.BASE_FOV, STEP_S)
	return await _play_steps(events)


## Plays the moment the hero is hit: a slow bullet from [param fatal], or a knife lunge for [param stab], then a fade to black.
func _play_ending(fatal: Dictionary, stab: Dictionary, arrival: Vector3, fire_s: float) -> bool:
	if not fatal.is_empty():
		var shooter_pos: Vector3 = ReplayStage.to3(fatal["from"])
		_after(fire_s, func() -> void: _tween_yaw(ReplayStage.yaw_to(arrival, shooter_pos), 0.1))
		if not await _wait(fire_s + TRAVEL_S * float(fatal["frac"])):
			return false
	else:
		var knife: Figure3D = _stage.figures[int(stab["gun"])]
		var lunge_to: Vector3 = arrival + (knife.position - arrival).normalized() * LUNGE_STOP
		lunge_to.y = knife.position.y
		_tween_yaw(ReplayStage.yaw_to(arrival, knife.position), LUNGE_S)
		create_tween().tween_property(knife, "position", lunge_to, LUNGE_S).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		if not await _wait(LUNGE_S):
			return false
	_stage.shake()
	_stop_until_ms = Time.get_ticks_msec() + HIT_STOP_MS
	_stage.overlay.fade_to_black(FADE_S)
	_ended_dark = true
	return await _wait_real(FADE_S + BLACK_HOLD_S)


## Moves the figures that step at the end of the turn and shows the reinforcements. Waits only when something moves.
func _play_steps(events: Array) -> bool:
	var moved: bool = false
	for event: Dictionary in events:
		match event["type"]:
			"step":
				moved = true
				var figure: Figure3D = _stage.figures[int(event["gun"])]
				create_tween().tween_property(figure, "position", ReplayStage.to3(event["to"]), STEP_S).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			"spawn":
				moved = true
				_stage.add_figure(ReplayStage.to3(event["pos"]), _stage.hero_floor_pos())
	return not moved or await _wait(STEP_S + 0.1)


func _first_of(events: Array, type: String) -> Dictionary:
	for event: Dictionary in events:
		if event["type"] == type:
			return event
	return {}


func _dash(arrival: Vector3, look_at: Vector3) -> void:
	var rig: Node3D = _stage.rig()
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(rig, "position", Vector3(arrival.x, ReplayStage.EYE_HEIGHT, arrival.z), DASH_S).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_tween_yaw(ReplayStage.yaw_to(arrival, look_at), DASH_S)
	var kick: Tween = create_tween()
	kick.tween_property(_stage.camera, "fov", KICK_FOV, DASH_S * 0.4)
	kick.tween_property(_stage.camera, "fov", ReplayStage.FOCUS_FOV, DASH_S * 0.6 + 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_stage.fx.speed_lines(_stage.camera, DASH_S + 0.05)


## Replaces the dash with a short dim cut to the new spot, since the straight flight would cross a wall.
func _cut(arrival: Vector3, look_at: Vector3) -> void:
	var rig: Node3D = _stage.rig()
	var place: Callable = func() -> void:
		rig.position = Vector3(arrival.x, ReplayStage.EYE_HEIGHT, arrival.z)
		rig.rotation.y = ReplayStage.yaw_to(arrival, look_at)
		_stage.camera.fov = ReplayStage.FOCUS_FOV
	_stage.fx.dim_cut(_stage.camera, CUT_S * 0.5, place)


## Returns where the hero's strike ends: the victim, or the cover block of a wasted strike.
func _strike_point(event: Dictionary) -> Vector3:
	if bool(event["wasted"]):
		return ReplayStage.to3(event["to"], 0.0)
	return _stage.figures[int(event["victim"])].position


func _fire_hero(victim_pos: Vector3, blocked: bool) -> void:
	var rig: Node3D = _stage.rig()
	var target: Vector3 = Vector3(victim_pos.x, ReplayFx.CHEST, victim_pos.z)
	var aim: Vector3 = (target - rig.position).normalized()
	var reach: float = minf(HERO_TRACER_START, rig.position.distance_to(target) * 0.4)
	var muzzle: Vector3 = rig.position + aim * reach + rig.basis * Vector3(0.3, -0.3, 0.0)
	_stage.fx.bullet(muzzle, target, AIM_S + 0.04, true)
	_stage.fx.muzzle_flash(muzzle)
	if blocked:
		_after(AIM_S + 0.04, func() -> void: _stage.fx.spark_ring(target - aim * 0.3, muzzle))


func _fire_shot(event: Dictionary, delay: float) -> void:
	var from: Vector3 = ReplayStage.to3(event["from"], ReplayFx.CHEST)
	var to: Vector3 = ReplayStage.to3(event["to"], ReplayFx.CHEST)
	var ahead: Vector3 = (to - from).normalized() if from.distance_squared_to(to) > 0.0001 else Vector3.FORWARD
	_after(delay, func() -> void:
		_stage.fx.bullet(from, to, TRAVEL_S)
		_stage.fx.muzzle_flash(from + ahead * 0.8 + Vector3(0.0, -0.05, 0.0)))
	if int(event["blocked_by"]) >= 0:
		_after(delay + TRAVEL_S, func() -> void: _stage.fx.spark_ring(to - ahead * 0.3, from))


func _schedule_death(event: Dictionary, delay: float) -> void:
	var wait_s: float = 0.0 if event["cause"] == "hero" else delay + TRAVEL_S * float(event["frac"])
	if event["cause"] == "hero":
		wait_s = AIM_S + 0.04
	var figure: Figure3D = _stage.figures[int(event["gun"])]
	_after(wait_s, func() -> void:
		figure.fall(figure.global_position - _stage.camera.global_position)
		_stage.shake()
		_stop_until_ms = Time.get_ticks_msec() + HIT_STOP_MS)


func _lines3(plan: Array[Dictionary], skip_gun: int) -> Array[Dictionary]:
	var lines: Array[Dictionary] = []
	for line: Dictionary in plan:
		if int(line["gun"]) != skip_gun:
			lines.append({"from": ReplayStage.to3(line["from"]), "to": ReplayStage.to3(line["to"])})
	return lines


func _alive_centroid(room: Dictionary) -> Vector3:
	var sum: Vector2 = Vector2.ZERO
	var count: int = 0
	var guns: Array = room["guns"]
	var alive: Array = room.get("alive", [])
	for i: int in guns.size():
		if i >= alive.size() or bool(alive[i]):
			sum += guns[i]
			count += 1
	return ReplayStage.to3(sum / float(maxi(count, 1)))


func _tween_fov(target: float, seconds: float) -> void:
	create_tween().tween_property(_stage.camera, "fov", target, seconds).set_trans(Tween.TRANS_SINE)


func _tween_yaw(target: float, seconds: float) -> void:
	var rig: Node3D = _stage.rig()
	var start: float = rig.rotation.y
	create_tween().tween_method(func(t: float) -> void: rig.rotation.y = lerp_angle(start, target, t), 0.0, 1.0, seconds).set_trans(Tween.TRANS_SINE)


func _set_slow(scale: float, seconds: float) -> void:
	if _slow_tween:
		_slow_tween.kill()
	_slow_tween = create_tween().set_ignore_time_scale(true)
	_slow_tween.tween_property(self, "_slow", scale, seconds)


func _after(seconds: float, action: Callable) -> void:
	get_tree().create_timer(seconds).timeout.connect(func() -> void:
		if not _cancelled:
			action.call())


func _wait_real(seconds: float) -> bool:
	await get_tree().create_timer(seconds, true, false, true).timeout
	return not _cancelled


func _wait(seconds: float) -> bool:
	await get_tree().create_timer(seconds).timeout
	return not _cancelled
