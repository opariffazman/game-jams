class_name ChainTracker
extends RefCounted
## Best chain of a run: the single swap with the most kills in one resolution. A tie keeps the earlier swap.

## Kills of the best swap so far. Zero means none yet.
var kills: int = 0
## Room the best swap happened in.
var room: Dictionary = {}
## Taps from the room start up to and including the best swap.
var taps: Array[int] = []
## Boons owned during the best swap, in pick order.
var boons: Array[int] = []
## Floor of the room, 1 to 4.
var level: int = 1
## Room number on its floor, 1 to 3.
var number: int = 1


## Offers a swap that killed [param swap_kills] gunmen. Returns true when it becomes the best chain.
func consider(swap_kills: int, swap_room: Dictionary, swap_taps: Array[int], owned_boons: Array[int], floor_number: int, room_number: int) -> bool:
	if swap_kills <= kills:
		return false
	kills = swap_kills
	room = swap_room
	taps = swap_taps.duplicate()
	boons = owned_boons.duplicate()
	level = floor_number
	number = room_number
	return true


## Returns true once a swap has been recorded.
func has_chain() -> bool:
	return kills > 0
