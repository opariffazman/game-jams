class_name PlayerInput
extends Node
## Base class for anything that can aim and fire: camera hands, mouse or touch.
##
## The shooter and the reticle only talk to this interface, so the game plays the same without a camera.

## Most aim slots one input can drive.
const MAX_SLOTS: int = 4

## Share by which zombie hit radii grow for this input, because hand and touch aim are imprecise.
var hit_radius_scale: float = 1.5
## Whether the shooter fires on its own while the reticle is on a zombie.
var auto_fire: bool = false
## Whether this input has live tracking or pointer data.
var tracking_ok: bool = false


## Returns how many aim slots this input drives.
func get_slot_count() -> int:
	return 0


## Returns whether the slot currently has an aim point.
func is_aiming(_slot: int) -> bool:
	return false


## Returns the slot aim point in 0 to 1 screen space.
func get_aim_point(_slot: int) -> Vector2:
	return Vector2(0.5, 0.5)


## Returns whether the slot holds fire.
func is_firing(_slot: int) -> bool:
	return false
