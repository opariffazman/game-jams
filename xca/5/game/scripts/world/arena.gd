class_name Arena
extends Node2D
## The play area: floor art, four walls, the centre spot and the stack.
##
## Walls are static bodies. The floor and markings come from the active [VisualSet].
## Characters register through [method register_character].

## Group the arena joins.
const GROUP: StringName = &"arena"

## Centre of the stack spot in world pixels.
var centre_spot: Vector2 = Vector2(640.0, 360.0)
## Tuning source. Defaults to [method Tuning.load_default].
var tuning: Tuning
## The stack at the centre spot.
var stack: Stack

var _characters: Dictionary = {0: [], 1: []}
var _floor: EntityVisual


func _ready() -> void:
	add_to_group(GROUP)
	if tuning == null:
		tuning = Tuning.load_default()
	centre_spot = tuning.arena_centre
	_build_walls()
	_build_floor()
	stack = Stack.new()
	stack.tuning = tuning
	stack.name = "Stack"
	stack.position = centre_spot
	add_child(stack)


## Adds [param character] to team lists, so [method get_characters] returns it.
func register_character(character: Character) -> void:
	var team: int = character.team
	if not _characters.has(team):
		_characters[team] = []
	if not _characters[team].has(character):
		_characters[team].append(character)


## Forgets every registered character.
func clear_characters() -> void:
	_characters = {0: [], 1: []}


## Returns the characters of [param team], dead ones included.
func get_characters(team: int) -> Array:
	var members: Array = _characters.get(team, [])
	members = members.filter(func(entry: Variant) -> bool: return is_instance_valid(entry))
	_characters[team] = members
	return members


## Returns sandals that are neither standing, flying, nor carried.
func get_loose_sandals() -> Array:
	var loose: Array = []
	for node: Node in get_tree().get_nodes_in_group(Sandal.GROUP):
		var sandal: Sandal = node as Sandal
		if sandal == null or sandal.in_flight or sandal.freeze or sandal.is_queued_for_deletion():
			continue
		if stack != null and stack.is_standing(sandal):
			continue
		loose.append(sandal)
	return loose


## Returns a random point inside the walls, kept [param margin] away from them.
func random_point(margin: float = 40.0) -> Vector2:
	var half: Vector2 = tuning.arena_half_extents - Vector2.ONE * margin
	return centre_spot + Vector2(randf_range(-half.x, half.x), randf_range(-half.y, half.y))


## Builds the floor again from the active [VisualSet]. Call it after the skin changed.
func rebuild_art() -> void:
	if _floor != null:
		remove_child(_floor)
		_floor.queue_free()
		_floor = null
	_build_floor()
	if stack != null:
		stack.rebuild_marker()


func _build_floor() -> void:
	var skin: VisualSet = SkinRef.get_visual_set()
	if skin == null:
		return
	_floor = skin.make(&"arena")
	if _floor == null:
		return
	_floor.position = centre_spot
	_floor.z_index = -10
	_floor.set_extent(tuning.arena_half_extents * 2.0)
	_floor.set_guide_radii(tuning.throw_radius, tuning.orbit_radius)
	add_child(_floor)


func _build_walls() -> void:
	var half: Vector2 = tuning.arena_half_extents
	var thick: float = tuning.wall_thickness
	var specs: Array[Rect2] = [
		Rect2(-half.x - thick, -half.y - thick, (half.x + thick) * 2.0, thick),
		Rect2(-half.x - thick, half.y, (half.x + thick) * 2.0, thick),
		Rect2(-half.x - thick, -half.y, thick, half.y * 2.0),
		Rect2(half.x, -half.y, thick, half.y * 2.0),
	]
	for rect: Rect2 in specs:
		var wall: StaticBody2D = StaticBody2D.new()
		wall.collision_layer = Layers.WORLD
		wall.collision_mask = 0
		wall.position = centre_spot + rect.position + rect.size * 0.5
		var shape: CollisionShape2D = CollisionShape2D.new()
		var box: RectangleShape2D = RectangleShape2D.new()
		box.size = rect.size
		shape.shape = box
		wall.add_child(shape)
		add_child(wall)
