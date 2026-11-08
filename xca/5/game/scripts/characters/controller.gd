class_name Controller
extends Node
## Base class for anything that drives a [Character].
##
## A controller only writes [member Character.move_intent] and calls the character's
## throw, pass, dash and pick-up methods. It never writes other state on the character.

## Emitted when the controlled character changes. Either value can be null.
signal character_changed(previous: Character, current: Character)

## The driven character, or null.
var character: Character


## Starts driving [param target]. Stops driving the previous character.
func attach(target: Character) -> void:
	if target == character:
		return
	var previous: Character = character
	if previous != null:
		_on_detached(previous)
		previous.move_intent = Vector2.ZERO
	character = target
	if target != null:
		_on_attached(target)
	character_changed.emit(previous, target)


## Stops driving the current character.
func detach() -> void:
	attach(null)


## Hook for subclasses. Runs after [member character] is set.
func _on_attached(_target: Character) -> void:
	pass


## Hook for subclasses. Runs before [member character] is cleared.
func _on_detached(_target: Character) -> void:
	pass
