class_name RoomState
extends RefCounted
## Pure game state of one room: hero, gunmen, cover blocks, turn events, and the turn counter.

## Gunman types. A pistol fires, a shield also blocks from the front, a knife walks at the hero and never fires.
enum Kind { PISTOL, SHIELD, KNIFE }
## Four facing directions of a shield.
enum Facing { UP, DOWN, LEFT, RIGHT }

## Hero position.
var hero: Vector2 = Vector2.ZERO
## Gunman positions. Dead gunmen keep their last position.
var guns: PackedVector2Array = PackedVector2Array()
## Alive flag per gunman.
var alive: Array[bool] = []
## [enum Kind] per gunman.
var kinds: Array[int] = []
## [enum Facing] per gunman. Only a shield reads it.
var facings: Array[int] = []
## Static cover blocks that stop bullets.
var covers: Array[Rect2] = []
## Turn events, each a dictionary with turn (from 1), type, and params.
var events: Array[Dictionary] = []
## Turns resolved so far. The turn being planned is this plus one.
var turn: int = 0
## True once the Bulletproof Coat absorbed a bullet in this room.
var coat_spent: bool = false


## Returns the unit vector a shield with [param facing] looks along.
static func facing_vector(facing: int) -> Vector2:
	match facing:
		Facing.UP:
			return Vector2.UP
		Facing.DOWN:
			return Vector2.DOWN
		Facing.LEFT:
			return Vector2.LEFT
	return Vector2.RIGHT


## Builds a state from a room dictionary with keys hero, guns, covers, and optional kinds, facings, events.
static func from_room(room: Dictionary) -> RoomState:
	var state: RoomState = RoomState.new()
	state.hero = room["hero"]
	var room_kinds: Array = room.get("kinds", [])
	var room_facings: Array = room.get("facings", [])
	var index: int = 0
	for gun_pos: Vector2 in room["guns"]:
		state.add_gun(gun_pos, int(room_kinds[index]) if index < room_kinds.size() else Kind.PISTOL, int(room_facings[index]) if index < room_facings.size() else Facing.UP)
		index += 1
	if Rooms.COVER_ENABLED:
		for cover: Rect2 in room["covers"]:
			state.covers.append(cover)
	state.events.assign(room.get("events", []))
	return state


## Adds a living gunman and returns his index.
func add_gun(pos: Vector2, kind: int, facing: int) -> int:
	guns.append(pos)
	alive.append(true)
	kinds.append(kind)
	facings.append(facing)
	return guns.size() - 1


## Returns an independent copy.
func clone() -> RoomState:
	var copy: RoomState = RoomState.new()
	copy.hero = hero
	copy.guns = guns.duplicate()
	copy.alive = alive.duplicate()
	copy.kinds = kinds.duplicate()
	copy.facings = facings.duplicate()
	copy.covers = covers
	copy.events = events
	copy.turn = turn
	copy.coat_spent = coat_spent
	return copy


## Returns how many gunmen live.
func alive_count() -> int:
	var count: int = 0
	for flag: bool in alive:
		if flag:
			count += 1
	return count


## Returns the events of [param type] that fire on the turn being planned.
func events_now(type: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for event: Dictionary in events:
		if int(event["turn"]) == turn + 1 and event["type"] == type:
			out.append(event)
	return out
