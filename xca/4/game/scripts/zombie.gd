class_name Zombie
extends Node3D
## One pooled zombie with a small animation state machine.
##
## Hit tests use a generous sphere instead of physics, so a shaky fingertip still lands shots.
## States: walking (move or attack clip by distance), hit (brief HitReact), dying (Death clip, then shrink).

## Emitted once when a shot defeats the zombie.
signal defeated(zombie: Zombie)
## Emitted when the zombie reaches the player.
signal reached_player(zombie: Zombie)
## Emitted when a shot hurts the zombie without defeating it.
signal hurt(zombie: Zombie)
## Emitted on every damage, with the lives taken and whether it defeated the zombie. Effects listen to this one.
signal damaged(zombie: Zombie, amount: int, killed: bool)

## Life cycle of a pooled zombie.
enum State {
	INACTIVE, ## Hidden and waiting in the pool.
	WALKING, ## Moving toward the player.
	HIT, ## Playing HitReact after a shot, not moving.
	DYING, ## Playing Death or shrinking away.
}

## Uniform scale applied to every model so zombies read well from the camera.
const MODEL_SCALE: float = 1.35
## Distance ahead of the player in metres at which a zombie counts as reaching the player.
const REACH_DISTANCE: float = 1.8
## Sideways distance in metres within which a zombie in reach hits the player. Beside it the zombie runs past.
const HIT_HALF_WIDTH: float = 1.1
## Distance behind the player in metres at which a zombie that ran past is removed.
const PASSED_DISTANCE: float = 3.0
## Speed in metres per second a hit pushes the zombie back, and how fast that push fades.
const KNOCKBACK_SPEED: float = 9.0
const KNOCKBACK_DECAY: float = 14.0
## Seconds the white hit flash lasts.
const FLASH_SECONDS: float = 0.07
## Milliseconds between flashes anywhere on screen. Under three flashes per second is the safe limit for flashing light, and this gap allows 2.8.
const FLASH_GAP_MSEC: int = 360
## Distance in metres at which a zombie switches to its attack clip.
const ATTACK_DISTANCE: float = 5.0
## Seconds a zombie stands in HitReact before it walks on.
const HIT_STUN_SECONDS: float = 0.35
## Seconds the Death clip plays before the shrink-away starts.
const DEATH_SECONDS: float = 0.4
## Seconds the shrink-away takes.
const SHRINK_SECONDS: float = 0.15
## Shots needed per type, in the order basic, chubby, arm brute, ribcage runner.
const TYPE_HEALTH: Array[int] = [2, 4, 5, 1]
## Move speed in metres per second per type.
const TYPE_SPEED: Array[float] = [1.5, 1.0, 1.4, 2.6]
## Hit sphere centre height in metres per type, before scaling.
const TYPE_CENTER_HEIGHT: Array[float] = [0.75, 0.9, 0.85, 0.55]
## Clip played while approaching, per type. The runner uses Run, the brute uses Run_Arms.
const MOVE_CLIPS: Array[StringName] = [&"Walk", &"Walk", &"Run_Arms", &"Run"]
## Clip played within reach of the player, per type. The ribcage has no attack clip.
const ATTACK_CLIPS: Array[StringName] = [&"Run_Attack", &"Run_Attack", &"Run_Attack", &"Run"]
## Animation speed multiplier per type.
const TYPE_ANIM_SPEED: Array[float] = [1.0, 0.8, 1.0, 1.0]

## Current life cycle state.
var state: State = State.INACTIVE
## Index into the type tables.
var type_id: int = 0

var _health: int = 0
var _hero: Node3D
var _model: Node3D
var _meshes: Array[MeshInstance3D] = []
var _knockback: float = 0.0
var _flash_left: float = 0.0
var _animation: AnimationPlayer
var _tween: Tween
var _hit_timer: float = 0.0
var _attacking: bool = false


func _process(delta: float) -> void:
	_tick_flash(delta)
	global_position.z += _knockback * delta
	_knockback = move_toward(_knockback, 0.0, KNOCKBACK_DECAY * delta)
	if state == State.HIT:
		# A stunned zombie stands on the scrolling ground, so it still slides toward the player at the ground speed.
		global_position.z += WorldScroll.speed * delta
		_hit_timer -= delta
		if _hit_timer <= 0.0:
			state = State.WALKING
			_play_current_clip()
		_check_reach()
		return
	if state != State.WALKING:
		return
	var ahead: float = _distance_ahead()
	var near: bool = ahead <= ATTACK_DISTANCE
	if near != _attacking:
		_attacking = near
		_play_current_clip()
	global_position.z += (TYPE_SPEED[type_id] + WorldScroll.speed) * delta
	_check_reach()


## Builds the model and blob shadow once. The zombie starts inactive.
func setup(type: int, scene: PackedScene, blob_mesh: QuadMesh) -> void:
	type_id = type
	_model = scene.instantiate()
	add_child(_model)
	_animation = AnimUtil.find_player(_model)
	if _animation != null:
		AnimUtil.configure_loops(_animation)
	for mesh: Node in _model.find_children("*", "MeshInstance3D"):
		_meshes.append(mesh as MeshInstance3D)
	var blob: MeshInstance3D = MeshInstance3D.new()
	blob.mesh = blob_mesh
	blob.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	blob.position = Vector3(0.0, 0.02, 0.0)
	blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(blob)
	_deactivate()


## Puts the zombie at a spawn point in a lane. It walks toward the player along that lane and rises out of the ground.
func activate(spawn_point: Vector3, hero: Node3D) -> void:
	_kill_tween()
	position = spawn_point
	_hero = hero
	_health = TYPE_HEALTH[type_id]
	_attacking = false
	_knockback = 0.0
	_flash_left = 0.0
	_set_overlay(null)
	_model.scale = Vector3.ONE * MODEL_SCALE
	look_at(spawn_point + Vector3.BACK, Vector3.UP, true)
	visible = true
	state = State.WALKING
	set_process(true)
	reset_animation_speed()
	_play_current_clip()


## Returns how far in front of the player the zombie stands in metres. It is negative after the zombie passed the player.
func distance_ahead() -> float:
	return _distance_ahead()


## Returns the world position of the hit sphere centre.
func get_center() -> Vector3:
	return global_position + Vector3.UP * TYPE_CENTER_HEIGHT[type_id] * MODEL_SCALE


## Returns whether a shot can hit this zombie now.
func is_targetable() -> bool:
	return state == State.WALKING or state == State.HIT


## Removes one life and returns true when that defeats the zombie.
func take_hit() -> bool:
	return take_damage(1)


## Removes several lives at once and returns true when that defeats the zombie. Emits one hurt signal at most.
func take_damage(amount: int) -> bool:
	_health -= amount
	_knockback = -KNOCKBACK_SPEED
	_flash()
	if _health <= 0:
		damaged.emit(self, amount, true)
		_die()
		return true
	state = State.HIT
	_hit_timer = HIT_STUN_SECONDS
	AnimUtil.play(_animation, &"HitReact", true)
	damaged.emit(self, amount, false)
	hurt.emit(self)
	return false


## Hides the zombie and returns it to the pool without any effect.
func clear() -> void:
	_kill_tween()
	_deactivate()


## Applies the animation level of detail. Far zombies advance on alternate frames at double speed.
func apply_animation_lod(is_far: bool, skip_frame: bool) -> void:
	if _animation == null:
		return
	var factor: float = 0.0 if skip_frame else (2.0 if is_far else 1.0)
	_animation.speed_scale = TYPE_ANIM_SPEED[type_id] * factor


## Restores full animation speed.
func reset_animation_speed() -> void:
	if _animation != null:
		_animation.speed_scale = TYPE_ANIM_SPEED[type_id]


func _die() -> void:
	state = State.DYING
	defeated.emit(self)
	AnimUtil.play(_animation, &"Death", true)
	_kill_tween()
	_tween = create_tween()
	_tween.tween_interval(DEATH_SECONDS)
	_tween.tween_property(_model, "scale", Vector3.ZERO, SHRINK_SECONDS)
	_tween.tween_callback(_deactivate)


func _distance_ahead() -> float:
	return _hero.global_position.z - global_position.z


## A zombie in reach hits the player when it shares the player's lane and otherwise runs past.
func _check_reach() -> void:
	var ahead: float = _distance_ahead()
	if ahead <= REACH_DISTANCE and absf(global_position.x - _hero.global_position.x) < HIT_HALF_WIDTH:
		reached_player.emit(self)
		_vanish()
	elif ahead < -PASSED_DISTANCE:
		_vanish()


func _flash() -> void:
	var now: int = Time.get_ticks_msec()
	if now - _last_flash_msec < FLASH_GAP_MSEC:
		return
	_last_flash_msec = now
	_flash_left = FLASH_SECONDS
	_set_overlay(_flash_material())


func _tick_flash(delta: float) -> void:
	if _flash_left <= 0.0:
		return
	_flash_left -= delta
	if _flash_left <= 0.0:
		_set_overlay(null)


func _set_overlay(material: Material) -> void:
	for mesh: MeshInstance3D in _meshes:
		mesh.material_overlay = material


static var _shared_flash: StandardMaterial3D
static var _last_flash_msec: int = -FLASH_GAP_MSEC


static func _flash_material() -> StandardMaterial3D:
	if _shared_flash == null:
		_shared_flash = StandardMaterial3D.new()
		_shared_flash.albedo_color = Color(1.0, 1.0, 1.0, 0.65)
		_shared_flash.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_shared_flash.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return _shared_flash


func _vanish() -> void:
	state = State.DYING
	_kill_tween()
	_tween = create_tween()
	_tween.tween_property(_model, "scale", Vector3.ZERO, SHRINK_SECONDS)
	_tween.tween_callback(_deactivate)


func _play_current_clip() -> void:
	var clips: Array[StringName] = ATTACK_CLIPS if _attacking else MOVE_CLIPS
	AnimUtil.play(_animation, clips[type_id])


func _deactivate() -> void:
	state = State.INACTIVE
	visible = false
	set_process(false)
	if _animation != null:
		_animation.pause()


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
