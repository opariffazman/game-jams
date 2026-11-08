extends Node
## Hit stop and slow-motion through [member Engine.time_scale].
##
## This node keeps running while the tree is slowed, because timers use real time.

var _restore_task: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## Freezes the game for [param duration] real seconds.
func hit_stop(duration: float) -> void:
	_scale_for(0.0, duration)


## Slows the game to [param scale] for [param duration] real seconds.
func slow_motion(scale: float, duration: float) -> void:
	_scale_for(scale, duration)


## Returns the time scale to normal now.
func reset() -> void:
	_restore_task += 1
	Engine.time_scale = 1.0


func _scale_for(scale: float, duration: float) -> void:
	if duration <= 0.0:
		return
	_restore_task += 1
	var task: int = _restore_task
	Engine.time_scale = scale
	await get_tree().create_timer(duration, true, false, true).timeout
	if task == _restore_task:
		Engine.time_scale = 1.0
