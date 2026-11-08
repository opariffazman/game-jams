class_name ShiftUndo
extends RefCounted
## Undo stock of one room: the states before each shift, and how many undos are left. The run sets the stock per room, so an upgrade can raise it.

## Undos left in this room.
var left: int = 0

var _stack: Array[Dictionary] = []


## Empties the stack and sets the undos of a fresh room to [param per_room].
func reset(per_room: int) -> void:
	left = per_room
	_stack.clear()


## Records the state before a shift: [param state], the shifts used, and the tap list. Copies all three.
func push(state: RoomState, shifts_used: int, taps: Array[int]) -> void:
	_stack.append({"state": state.clone(), "swaps": shifts_used, "taps": taps.duplicate()})


## Returns true when one more undo is allowed and a shift can be taken back.
func can_undo() -> bool:
	return left > 0 and not _stack.is_empty()


## Takes the last record and spends one undo. Returns a dictionary with state, swaps, and taps. Call only when [method can_undo] is true.
func pop() -> Dictionary:
	left -= 1
	return _stack.pop_back()
