class_name RailsDirector
extends Node
## Runs the endless lane runner: glides the hero between hidden lanes, spawns rows of zombies and barriers, tracks hearts.
##
## The hero stays at the origin and the world scrolls toward it, so floating-point error never grows with distance.
## There is no game over. Losing every heart clears the road, refills the hearts and carries on.
## Lanes are never drawn. Every row leaves one lane open, so a clear path always exists.

## Emitted when the heart count changes.
signal hearts_changed(hearts: int)
## Emitted with a short on-screen message, or an empty string to hide it.
signal message_changed(text: String)
## Emitted when a horde begins.
signal wave_started
## Emitted when a horde is over.
signal wave_cleared
## Emitted when a zombie or barrier reaches the player and a heart is lost.
signal heart_lost
## Emitted after the hero starts a glide to another lane.
signal lane_changed(lane: int)
## Emitted once when the last heart is lost, with the metres run.
signal game_over(metres: int)

## Steps of the run.
enum Phase {
	IDLE, ## Waiting for the start screen to close.
	RUNNING, ## Running, rows keep spawning.
	GAME_OVER, ## Hearts ran out. The run is over until restart() or stop().
}

## Ground speed in metres per second. Was 9.0, slowed so the player has time to pick a weapon per zombie type.
const RUN_SPEED: float = 5.0
## Sideways distance between lane centres in metres.
const LANE_WIDTH: float = 2.4
## Metres ahead of the hero where hazards spawn. Was 1.2 s of travel (about 13 m). Deep inside the fog, so nothing pops in.
const SPAWN_AHEAD: float = 60.0
## Average zombie walking speed toward the hero in metres per second, used to size the warning distance.
const ZOMBIE_WALK_SPEED: float = 2.0
## Spring stiffness of the lane glide. Higher values glide faster. Damping is critical, so the hero never overshoots.
const GLIDE_STIFFNESS: float = 150.0
## Seconds a short message stays on screen.
const MESSAGE_SECONDS: float = 1.6
## Seconds of a calm stretch and of a horde.
const CALM_SECONDS: float = 9.0
const HORDE_SECONDS: float = 7.0
## Metres between rows in a calm stretch and in a horde.
const CALM_ROW_GAP: float = 15.0
const HORDE_ROW_GAP: float = 8.5
## Share of the lanes next to the open lane that get a hazard, in a calm stretch and in a horde.
const CALM_FILL: float = 0.45
const HORDE_FILL: float = 0.9
## Share of hazards that are barriers and not zombies.
const BARRIER_SHARE: float = 0.3
## A barrier hits when it is this close in z, and within BARRIER_HALF_WIDTH of the hero in x.
const BARRIER_REACH: float = 0.5
const BARRIER_HALF_WIDTH: float = 0.95
## Metres behind the hero where a barrier is removed.
const BARRIER_PASSED: float = 4.0
const BARRIER_POOL_SIZE: int = 8
## Share of barrier spots filled by a wrecked car instead of a traffic barrier.
const CAR_SHARE: float = 0.4
## A car is about 6k triangles, so the low tier keeps fewer in the pool and therefore fewer on screen.
const CAR_POOL_SIZE_HIGH: int = 2
const CAR_POOL_SIZE_LOW: int = 0
## Cars use LevelKit.CAR_SCALES, which sizes them against the hero and keeps the body inside one lane of LANE_WIDTH.
const CAR_YAW_LIMIT: float = 0.1
const CAR_TIP_CHANCE: float = 0.3
## Extra hit width on top of what the player sees, the same margin the traffic barrier has.
const CAR_HIT_MARGIN: float = 0.17
## Model size in metres at scale 1: half width, height, half length. Read from the glTF bounds.
const CAR_MODELS: Dictionary[String, Vector3] = {
	"Vehicle_Pickup": Vector3(1.16, 1.84, 2.6),
	"Vehicle_Sports": Vector3(1.34, 1.85, 2.83),
}
const CAR_TINTS: Array[Color] = [Color(0.2, 0.18, 0.18), Color(0.5, 0.3, 0.2), Color(0.33, 0.38, 0.42), Color(0.42, 0.4, 0.3)]
## Camera distance behind the hero in metres, and height above the ground.
const CAMERA_BACK: float = 5.2
const CAMERA_UP: float = 3.8
## Distance ahead of the hero the camera looks at, in metres.
const LOOK_AHEAD: float = 9.0
## Share of the hero's sideways offset the camera follows. Less than one keeps the hero moving on screen, which reads as a lane change.
const CAMERA_FOLLOW: float = 0.45
## Horizontal field of view in portrait, in degrees. It keeps the whole road in view on a narrow screen.
const PORTRAIT_FOV: float = 78.0
## Vertical field of view in landscape, in degrees.
const LANDSCAPE_FOV: float = 55.0
## Hero lean in radians per metre per second of sideways speed, and the largest lean.
const LEAN_PER_SPEED: float = 0.05
const MAX_LEAN: float = 0.35
## Screen shake: seconds to fade out and largest camera offset in metres.
const SHAKE_FADE_SECONDS: float = 0.25
const SHAKE_MAX_OFFSET: float = 0.18

## Endless road and prop scroller.
@export var course: RailsCourse
## Hero model that runs in place.
@export var hero: RailsHero
## Zombie pool for the rows.
@export var pool: ZombiePool
## Camera behind the hero.
@export var camera: Camera3D

## Current step of the run.
var phase: Phase = Phase.IDLE
## Hearts left.
var hearts: int = HeartsDisplay.DEFAULT_HEARTS
## Hearts the hero starts with. The hero table sets it.
var max_hearts: int = HeartsDisplay.DEFAULT_HEARTS
## Number of hidden lanes. The settings menu changes it, and the change applies on the next run.
var lane_count: int = 3
## Index of the lane the hero glides to.
var lane: int = 1
## Distance run in metres.
var distance: float = 0.0
## Whether hits shake the camera.
var shake_enabled: bool = true
## Whether a horde is on.
var horde_active: bool = false

var _hero_x: float = 0.0
var _hero_velocity: float = 0.0
var _open_lane: int = 1
var _row_timer: float = 0.0
var _stretch_timer: float = CALM_SECONDS
var _message_timer: float = 0.0
var _shake: float = 0.0
var _barriers: Array[Node3D] = []
var _barrier_root: Node3D
var _cars: Array[Node3D] = []
var _connected: bool = false


func _ready() -> void:
	set_process(false)


func _process(delta: float) -> void:
	_tick_message(delta)
	match phase:
		Phase.RUNNING:
			_run(delta)
	_glide(delta)
	_apply_camera(delta)


## Starts or restarts the run from the beginning of the road.
func restart() -> void:
	if not _connected:
		_connected = true
		pool.zombie_reached_player.connect(_on_hazard_reached_player)
		_build_barriers()
	set_process(true)
	pool.clear_all()
	_clear_barriers()
	distance = 0.0
	lane = lane_count / 2
	_open_lane = lane
	_hero_x = _lane_x(lane)
	_hero_velocity = 0.0
	_row_timer = 0.0
	_stretch_timer = CALM_SECONDS
	_end_horde()
	_set_hearts(max_hearts)
	hero.set_base(RailsHero.Base.MOVING)
	WorldScroll.speed = RUN_SPEED
	phase = Phase.RUNNING
	_show_message("Go!")


## Stops the run and clears the road, for the hero select screen.
func stop() -> void:
	set_process(false)
	pool.clear_all()
	_clear_barriers()
	phase = Phase.IDLE
	WorldScroll.speed = 0.0
	hero.set_base(RailsHero.Base.STOPPED)


## Moves one lane left (-1) or right (1). Does nothing at the edge, so a late flick costs nothing.
func step_lane(direction: int) -> void:
	go_to_lane(lane + direction)


## Glides to a lane index. Out-of-range values are clamped.
func go_to_lane(target: int) -> void:
	var clamped: int = clampi(target, 0, lane_count - 1)
	if clamped == lane or phase == Phase.IDLE:
		return
	lane = clamped
	lane_changed.emit(lane)


## Returns the world x of a lane centre.
func lane_x(index: int) -> float:
	return _lane_x(index)


## Returns the world x the hero currently stands at.
func get_hero_x() -> float:
	return _hero_x


## Restores hearts, never above the maximum.
func heal(amount: int = 1) -> void:
	_set_hearts(hearts + amount)


## Adds camera shake. Strength 0 to 1. Ignored when the setting is off.
func add_shake(strength: float) -> void:
	if shake_enabled:
		_shake = clampf(maxf(_shake, strength), 0.0, 1.0)


## Returns a short text for the readout.
func get_status_text() -> String:
	return "%s lane %d/%d %dm" % [Phase.keys()[phase].to_lower(), lane + 1, lane_count, int(distance)]


func _lane_x(index: int) -> float:
	return (float(index) - float(lane_count - 1) * 0.5) * LANE_WIDTH


func _run(delta: float) -> void:
	distance += RUN_SPEED * delta
	course.set_scroll(distance)
	_stretch_timer -= delta
	if _stretch_timer <= 0.0:
		if horde_active:
			_end_horde()
			wave_cleared.emit()
			_stretch_timer = CALM_SECONDS
		else:
			_begin_horde()
			_stretch_timer = HORDE_SECONDS
	_row_timer -= delta
	if _row_timer <= 0.0:
		_spawn_row()
		_row_timer = (HORDE_ROW_GAP if horde_active else CALM_ROW_GAP) / RUN_SPEED
	_update_barriers(delta)


func _begin_horde() -> void:
	horde_active = true
	wave_started.emit()
	_show_message("Horde!")


func _end_horde() -> void:
	horde_active = false


func _spawn_row() -> void:
	var step: int = [-1, 0, 1].pick_random()
	_open_lane = clampi(_open_lane + step, 0, lane_count - 1)
	var fill: float = HORDE_FILL if horde_active else CALM_FILL
	for index: int in lane_count:
		if index == _open_lane or randf() > fill:
			continue
		var point := Vector3(_lane_x(index), 0.0, -SPAWN_AHEAD)
		if randf() < BARRIER_SHARE and _place_barrier(point):
			continue
		pool.spawn(_pick_type(), point, hero)


func _pick_type() -> int:
	var roll: float = randf()
	if distance > 400.0 and roll < 0.12:
		return 2
	if roll < 0.55:
		return 0
	return 1 if roll < 0.75 else 3


func _build_barriers() -> void:
	_barrier_root = Node3D.new()
	_barrier_root.name = "Barriers"
	add_child(_barrier_root)
	var model: PackedScene = load("res://assets/level/TrafficBarrier_1.gltf")
	for index: int in BARRIER_POOL_SIZE:
		var barrier: Node3D = model.instantiate()
		barrier.visible = false
		_barrier_root.add_child(barrier)
		_barriers.append(barrier)
	for index: int in (CAR_POOL_SIZE_HIGH if Quality.is_high() else CAR_POOL_SIZE_LOW):
		_cars.append(_build_car(CAR_MODELS.keys()[index % CAR_MODELS.size()], CAR_TINTS[index % CAR_TINTS.size()]))


## A holder that keeps the car's yaw, around a body that keeps its tip. The tint hides the cheerful paint of the kit.
func _build_car(model_name: String, tint: Color) -> Node3D:
	var holder := Node3D.new()
	holder.visible = false
	holder.set_meta(&"model", model_name)
	var body: Node3D = (load("res://assets/level/%s.gltf" % model_name) as PackedScene).instantiate()
	holder.add_child(body)
	for mesh: MeshInstance3D in body.find_children("*", "MeshInstance3D", true, false):
		var material := mesh.get_active_material(0).duplicate() as StandardMaterial3D
		material.albedo_color = tint
		mesh.material_override = material
	_barrier_root.add_child(holder)
	return holder


## Gives a pooled car a random yaw and sometimes tips it on its side. Its hit width follows what the player sees.
func _pose_car(holder: Node3D) -> void:
	var model_name: String = holder.get_meta(&"model")
	var size: Vector3 = CAR_MODELS[model_name]
	var car_scale: float = LevelKit.CAR_SCALES[model_name]
	var yaw: float = randf_range(-CAR_YAW_LIMIT, CAR_YAW_LIMIT)
	var tip: float = 0.0
	if randf() < CAR_TIP_CHANCE:
		tip = PI * 0.5 * (1.0 if randf() < 0.5 else -1.0)
	var half_width: float = size.x * car_scale
	var base_x: float = 0.0
	var base_y: float = 0.0
	if tip != 0.0:
		half_width = size.y * car_scale * 0.5
		base_x = signf(tip) * half_width
		base_y = size.x * car_scale
	holder.rotation.y = yaw
	var body: Node3D = holder.get_child(0)
	body.transform = Transform3D(Basis(Vector3.BACK, tip) * Basis.from_scale(Vector3.ONE * car_scale), Vector3(base_x, base_y, 0.0))
	var reach: float = half_width * cos(yaw) + size.z * car_scale * sin(absf(yaw))
	holder.set_meta(&"hit_half_width", reach + CAR_HIT_MARGIN)


func _place_barrier(point: Vector3) -> bool:
	var pool_nodes: Array[Node3D] = _cars if not _cars.is_empty() and randf() < CAR_SHARE else _barriers
	for barrier: Node3D in pool_nodes:
		if barrier.visible:
			continue
		if pool_nodes == _cars:
			_pose_car(barrier)
		barrier.global_position = point
		barrier.visible = true
		return true
	return false


func _clear_barriers() -> void:
	for barrier: Node3D in _barriers + _cars:
		barrier.visible = false


## A car is long, so it hits when its near end reaches the hero and not its centre.
func _update_barriers(delta: float) -> void:
	for barrier: Node3D in _barriers + _cars:
		if not barrier.visible:
			continue
		barrier.global_position.z += RUN_SPEED * delta
		var is_car: bool = barrier.has_meta(&"model")
		var front_offset: float = 0.0
		var half_width: float = BARRIER_HALF_WIDTH
		if is_car:
			front_offset = CAR_MODELS[barrier.get_meta(&"model")].z * LevelKit.CAR_SCALES[barrier.get_meta(&"model")]
			half_width = barrier.get_meta(&"hit_half_width")
		var z: float = barrier.global_position.z
		if z - front_offset > BARRIER_PASSED:
			barrier.visible = false
		elif z + front_offset > -BARRIER_REACH and absf(barrier.global_position.x - _hero_x) < half_width:
			barrier.visible = false
			_on_hazard_reached_player()


func _on_hazard_reached_player() -> void:
	if phase != Phase.RUNNING:
		return
	_set_hearts(hearts - 1)
	heart_lost.emit()
	hero.play_react()
	add_shake(0.8)
	if hearts > 0:
		return
	pool.clear_all()
	_clear_barriers()
	phase = Phase.GAME_OVER
	_end_horde()
	WorldScroll.speed = 0.0
	hero.play_death()
	game_over.emit(int(distance))


func _set_hearts(value: int) -> void:
	hearts = clampi(value, 0, max_hearts)
	hearts_changed.emit(hearts)


func _show_message(text: String, seconds: float = MESSAGE_SECONDS) -> void:
	_message_timer = seconds
	message_changed.emit(text)


func _tick_message(delta: float) -> void:
	if _message_timer <= 0.0:
		return
	_message_timer -= delta
	if _message_timer <= 0.0:
		message_changed.emit("")


## Critically damped spring, so the hero eases into a lane without overshoot and the sideways speed drives the lean.
func _glide(delta: float) -> void:
	var damping: float = 2.0 * sqrt(GLIDE_STIFFNESS)
	var target: float = _lane_x(lane)
	var step: float = minf(delta, 0.05)
	_hero_velocity += ((target - _hero_x) * GLIDE_STIFFNESS - _hero_velocity * damping) * step
	_hero_x += _hero_velocity * step
	hero.global_position = Vector3(_hero_x, 0.0, 0.0)
	hero.run_pose(_hero_velocity, LEAN_PER_SPEED, MAX_LEAN)


## Portrait keeps the road width in view and shows more road ahead. Landscape keeps the height and shows more to the sides.
## Runs every frame, so rotating the device mid-run changes the view and never the run.
func fit_camera() -> void:
	var size: Vector2 = get_viewport().get_visible_rect().size
	if size.y > size.x:
		camera.keep_aspect = Camera3D.KEEP_WIDTH
		camera.fov = PORTRAIT_FOV
	else:
		camera.keep_aspect = Camera3D.KEEP_HEIGHT
		camera.fov = LANDSCAPE_FOV


func _apply_camera(delta: float) -> void:
	fit_camera()
	_shake = maxf(_shake - delta / SHAKE_FADE_SECONDS, 0.0)
	var jitter := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), 0.0) * _shake * SHAKE_MAX_OFFSET
	var follow_x: float = _hero_x * CAMERA_FOLLOW
	camera.global_position = Vector3(follow_x, CAMERA_UP, CAMERA_BACK) + jitter
	camera.look_at(Vector3(follow_x, 0.5, -LOOK_AHEAD))
