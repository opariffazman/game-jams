class_name Stack
extends Node2D
## The centre pyramid of sandals. It owns the pyramid sandals, detects the topple and runs the rebuild.
##
## The pyramid is a teepee: three equal sandals stand on edge on a ring, 120 degrees apart, with the tips
## leaning inward to one apex. It is down
## when a base sandal moves farther than [member Tuning.topple_distance] from its slot. After that the
## attackers carry all three sandals into the build zone, and one builder places them one at a time
## through [method place_sandal]. The builder stays a normal body, so a defender can still hit them.

## Emitted once when the pyramid falls.
signal toppled
## Emitted when a complete pyramid has stood for [member Tuning.build_stable_seconds].
signal rebuilt
## Emitted when [member placed_count] changes.
signal placed_count_changed(count: int)
## Emitted when [param builder] starts to build.
signal build_started(builder: Character)
## Emitted when a build stops. [param completed] is true when the third sandal was placed.
signal build_ended(builder: Character, completed: bool)
## Emitted when a sandal in flight knocks the placed sandals loose again.
signal pyramid_knocked

## Group the stack joins.
const GROUP: StringName = &"stack"
## Slack added to the touch distance of two sandals, in pixels.
const KNOCK_MARGIN: float = 4.0

## True from the topple until [method reset].
var is_down: bool = false
## True while a complete pyramid stands: at round start, and once the third sandal is placed.
var is_built: bool = true
## Sandals in the pyramid. It counts up during a rebuild.
var placed_count: int = 0
## Tuning source. Defaults to [method Tuning.load_default].
var tuning: Tuning
## Sandals in the pyramid, in slot order. Empty once the pyramid is down and nothing is placed.
var standing_sandals: Array[Sandal] = []
## Foot of each slot relative to the stack, on a ring of [member Tuning.pyramid_base_radius]. Slot 0 points up
## the screen, the others follow clockwise at 120 degrees. Build steps fill the slots in this order.
var slot_positions: Array[Vector2] = []
## Unit vector from each slot toward the centre. Each sandal leans along it.
var slot_lean_directions: Array[Vector2] = []
## Angle from vertical, in radians, at which every standing sandal leans. It comes from [member Tuning.pyramid_lean_degrees].
var slot_lean_angle: float = 0.0
## The character that builds now, or null.
var builder: Character = null

var _marker: EntityVisual
var _stable_time: float = 0.0
var _win_sent: bool = false


func _ready() -> void:
	add_to_group(GROUP)
	if tuning == null:
		tuning = Tuning.load_default()
	rebuild_marker()
	reset()


## Builds the centre marker again from the active [VisualSet]. Call it after the skin changed.
func rebuild_marker() -> void:
	if _marker != null:
		remove_child(_marker)
		_marker.queue_free()
		_marker = null
	var skin: VisualSet = SkinRef.get_visual_set()
	if skin != null:
		_marker = skin.make(&"stack_marker")
		if _marker != null:
			add_child(_marker)


func _physics_process(delta: float) -> void:
	if not is_down:
		_check_topple()
		return
	_update_rebuild(delta)


## True when [param sandal] is standing in the pyramid.
func is_standing(sandal: Sandal) -> bool:
	return standing_sandals.has(sandal)


## True when [param world_point] is inside the build zone.
func is_in_zone(world_point: Vector2) -> bool:
	return world_point.distance_to(global_position) <= tuning.build_zone_radius


## Loose sandals inside the build zone, not counting the pass sandal.
func zone_sandals() -> Array[Sandal]:
	var found: Array[Sandal] = []
	for sandal: Sandal in _free_sandals():
		if not sandal.freeze and not sandal.in_flight and is_in_zone(sandal.global_position):
			found.append(sandal)
	return found


## True when a build can run now: the pyramid is down and unfinished, all three sandals are in the
## zone or placed, and nobody carries one.
func can_build() -> bool:
	if not is_down or is_built:
		return false
	return zone_sandals().size() + placed_count == tuning.stack_size and _free_sandals().size() == zone_sandals().size()


## Removes the old sandals and builds a fresh standing pyramid.
func reset() -> void:
	if builder != null:
		_finish_build(false)
	for child: Node in get_children():
		if child is Sandal:
			remove_child(child)
			child.queue_free()
	standing_sandals.clear()
	slot_positions.clear()
	slot_lean_directions.clear()
	is_down = false
	is_built = true
	builder = null
	_stable_time = 0.0
	_win_sent = false
	placed_count = tuning.stack_size
	slot_lean_angle = deg_to_rad(tuning.pyramid_lean_degrees)
	for index: int in tuning.stack_size:
		var around: Vector2 = Vector2.from_angle(-PI * 0.5 + TAU * float(index) / float(tuning.stack_size))
		slot_positions.append(around * tuning.pyramid_base_radius)
		slot_lean_directions.append(-around)
	for index: int in tuning.stack_size:
		var sandal: Sandal = Sandal.new()
		sandal.tuning = tuning
		sandal.position = slot_positions[index]
		add_child(sandal)
		# Round-start sandals stay dynamic, because the topple test needs them to move. Only a build locks one.
		sandal.stack_slot = index
		sandal.lean_direction = slot_lean_directions[index]
		sandal.lean_angle = slot_lean_angle
		sandal.rotation = slot_lean_directions[index].angle()
		standing_sandals.append(sandal)
	placed_count_changed.emit(placed_count)


## Starts a build by [param character]. Returns false unless [method can_build] holds, the character
## stands in the zone and nobody else builds.
func begin_build(character: Character) -> bool:
	if character == null or not character.alive or builder != null or not can_build():
		return false
	if not is_in_zone(character.global_position):
		return false
	builder = character
	build_started.emit(character)
	return true


## Stops the build of [param character]. Placed sandals stay placed.
func end_build(character: Character) -> void:
	if builder == null or builder != character:
		return
	_finish_build(false)


## Stops the current build, whoever builds.
func cancel_build() -> void:
	if builder != null:
		_finish_build(false)


## Places the next sandal in its slot. Returns false when no build is possible.
func place_sandal() -> bool:
	if not can_build():
		return false
	var slot: int = placed_count
	var world_slot: Vector2 = to_global(slot_positions[slot])
	var nearest: Sandal = null
	for sandal: Sandal in zone_sandals():
		if nearest == null or sandal.global_position.distance_to(world_slot) < nearest.global_position.distance_to(world_slot):
			nearest = sandal
	if nearest == null:
		return false
	nearest.lock_in_stack(world_slot, slot, slot_lean_directions[slot], slot_lean_angle)
	standing_sandals.append(nearest)
	placed_count = standing_sandals.size()
	placed_count_changed.emit(placed_count)
	FxRef.burst(&"pickup", world_slot)
	AudioRef.play(&"place")
	if placed_count >= tuning.stack_size:
		is_built = true
		_stable_time = 0.0
		_finish_build(true)
	return true


func _check_topple() -> void:
	for index: int in standing_sandals.size():
		var sandal: Sandal = standing_sandals[index]
		if is_instance_valid(sandal) and sandal.global_position.distance_to(to_global(slot_positions[index])) > tuning.topple_distance:
			_topple()
			return


func _update_rebuild(delta: float) -> void:
	if placed_count > 0 and _impact_on_placed():
		_knock_loose()
		return
	if builder != null and not _builder_can_continue():
		_finish_build(false)
	if is_built and not _win_sent:
		_stable_time += delta
		if _stable_time >= tuning.build_stable_seconds:
			_win_sent = true
			AudioRef.play(&"rebuilt")
			rebuilt.emit()


func _builder_can_continue() -> bool:
	if not is_instance_valid(builder) or not builder.alive or not is_in_zone(builder.global_position):
		return false
	return is_built or can_build()


func _finish_build(completed: bool) -> void:
	var finished: Character = builder
	builder = null
	build_ended.emit(finished, completed)


func _impact_on_placed() -> bool:
	var touch: float = tuning.sandal_radius * 2.0 + KNOCK_MARGIN
	for node: Node in get_tree().get_nodes_in_group(Sandal.GROUP):
		var flying: Sandal = node as Sandal
		if flying == null or not flying.in_flight or flying.is_placed or flying.is_queued_for_deletion():
			continue
		if flying.linear_velocity.length() < tuning.knock_min_speed:
			continue
		for placed: Sandal in standing_sandals:
			if is_instance_valid(placed) and placed.global_position.distance_to(flying.global_position) <= touch:
				return true
	return false


func _knock_loose() -> void:
	if builder != null:
		_finish_build(false)
	var impulse: float = tuning.knock_impulse
	for index: int in standing_sandals.size():
		var sandal: Sandal = standing_sandals[index]
		if not is_instance_valid(sandal):
			continue
		var outward: Vector2 = Vector2.from_angle(TAU * float(index) / float(tuning.stack_size) + 0.5)
		sandal.release_from_stack(outward * impulse)
	standing_sandals.clear()
	placed_count = 0
	is_built = false
	_stable_time = 0.0
	AudioRef.play(&"topple")
	FxRef.burst(&"topple", global_position)
	pyramid_knocked.emit()
	placed_count_changed.emit(placed_count)


## Sandals that belong to the pyramid and are not in it: loose, carried or flying. The pass sandal is not one.
func _free_sandals() -> Array[Sandal]:
	var found: Array[Sandal] = []
	for node: Node in get_tree().get_nodes_in_group(Sandal.GROUP):
		var sandal: Sandal = node as Sandal
		if sandal == null or sandal.is_pass_sandal or sandal.is_placed or sandal.is_queued_for_deletion():
			continue
		if sandal.get_parent() != self:
			continue
		found.append(sandal)
	return found


func _topple() -> void:
	is_down = true
	is_built = false
	placed_count = 0
	for sandal: Sandal in standing_sandals:
		if is_instance_valid(sandal):
			sandal.release_from_stack()
	standing_sandals.clear()
	_stable_time = 0.0
	_win_sent = false
	var skin: VisualSet = SkinRef.get_visual_set()
	if skin != null:
		var effect: EntityVisual = skin.make(&"topple_effect")
		if effect != null:
			effect.position = position
			get_parent().add_child(effect)
	AudioRef.play(&"topple")
	FxRef.burst(&"topple", global_position)
	toppled.emit()
	placed_count_changed.emit(placed_count)
