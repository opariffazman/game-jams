class_name Gunman
extends StickFigure
## Magenta gunman. Sways and fires on a world-time clock.

## World seconds a gunman waits between shots, minimum and maximum.
const FIRE_INTERVAL := Vector2(1.5, 2.6)

## False after the gunman is shot.
var alive: bool = true

var _base_position: Vector2 = Vector2.ZERO
var _phase: float = 0.0
var _clock: float = 0.0
var _cooldown: float = 0.0


## Places the gunman and randomizes sway and the first shot delay.
func setup(spawn_position: Vector2) -> void:
	_base_position = spawn_position
	position = spawn_position
	_phase = randf() * TAU
	_cooldown = randf_range(0.8, FIRE_INTERVAL.y)
	set_pose(Pose.AIM)


## Advances in world time. Returns true when the gunman fires this step.
func tick(world_dt: float, target: Vector2) -> bool:
	_clock += world_dt
	position = _base_position + Vector2(sin(_clock * 0.9 + _phase) * 32.0, cos(_clock * 0.7 + _phase) * 12.0)
	aim_at((target - (position + Vector2(0.0, -32.0))).angle())
	_cooldown -= world_dt
	if _cooldown > 0.0:
		return false
	_cooldown = randf_range(FIRE_INTERVAL.x, FIRE_INTERVAL.y)
	return true


## Plays the fall pose and dims the body.
func die() -> void:
	alive = false
	set_pose(Pose.FALL)
	position.y += 14.0
	modulate.a = 0.5
