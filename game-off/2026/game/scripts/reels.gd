class_name Reels
extends RefCounted
## Builds the timelines and the card texts of the death reel and the best-chain clip.

## Most swaps the death reel shows. Earlier swaps are fast-forwarded without presentation.
const DEATH_SWAPS: int = 3


## Returns the death reel of a failed attempt: the last [constant DEATH_SWAPS] swaps of [param taps] on [param room].
static func death_timeline(room: Dictionary, taps: Array[int], boons: BoonSet) -> TurnEvents:
	return TurnEvents.build(room, taps, boons, maxi(taps.size() - DEATH_SWAPS, 0))


## Returns the best-chain clip, from the room start through every tap up to the best swap.
static func chain_timeline(chain: ChainTracker) -> TurnEvents:
	return TurnEvents.build(chain.room, chain.taps, BoonSet.from_owned(chain.boons))


## Returns [param count] with its noun, such as "1 shift" or "2 shifts".
static func counted(count: int, noun: String) -> String:
	return "%d %s" % [count, noun if count == 1 else noun + "s"]


## Returns the place of a room, such as "F2 R3".
static func place(level: int, number: int) -> String:
	return "F%d R%d" % [level, number]
