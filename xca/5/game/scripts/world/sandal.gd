class_name Sandal
extends RigidBody2D
## One sandal. A top-down physics body with no gravity.
##
## Joins the group [code]sandals[/code]. [member in_flight] is true while the sandal moves
## faster than [member Tuning.flight_min_speed] after a launch. It has no drawing code.
## The art is an [EntityVisual] built from the active [VisualSet].

## Emitted once per flight when this sandal in flight touches a living [Character].
signal hit_character(character: Character)

## Speed under which a contact makes no sound.
const CLACK_MIN_SPEED: float = 140.0
## Speed at which a contact sounds at full level.
const CLACK_FULL_SPEED: float = 700.0

## Group every sandal joins.
const GROUP: StringName = &"sandals"
## Value of [member owner_team] for a sandal nobody holds.
const NO_OWNER: int = -1

## True while the sandal flies after [method launch]. A flying sandal collides with
## characters, so a defender body blocks it. A resting sandal does not.
var in_flight: bool = false:
	set(value):
		in_flight = value
		collision_mask = _flight_mask() if value else _rest_mask()
		# A ranged throw runs with no damping. Leaving flight by any route restores it.
		if not value and tuning != null:
			_end_ranged()
		# A sandal that comes to rest on the field is shared again. A held one keeps its carrier.
		if not value and not freeze and not is_pass_sandal:
			owner_team = NO_OWNER
## Team of the character that holds or threw this sandal, or [constant NO_OWNER].
## The tint follows it: friendly blue or enemy red while owned, neutral sand otherwise.
var owner_team: int = NO_OWNER:
	set(value):
		owner_team = value
		_refresh_tint()
## Slot of the teepee this sandal stands in, or -1 while it is loose. See [member Stack.slot_positions].
var stack_slot: int = -1
## Unit vector, in world space, from the foot of the standing sandal toward the centre. It is ZERO while loose.
var lean_direction: Vector2 = Vector2.ZERO
## Angle in radians from vertical at which the placed sandal leans along [member lean_direction].
var lean_angle: float = 0.0
## True while a [Stack] holds this sandal in a pyramid slot.
var is_placed: bool = false
## True for the single sandal the defenders pass.
var is_pass_sandal: bool = false:
	set(value):
		is_pass_sandal = value
		if is_node_ready():
			_build_visual()
## Tuning source. Defaults to [method Tuning.load_default].
var tuning: Tuning
## Live visual child.
var visual: EntityVisual

## Distance of the last [method launch_ranged] throw in pixels, or -1 before any.
var last_range: float = -1.0

var _hit_this_flight: Array[Character] = []
var _shape: CollisionShape2D
var _range_left: float = 0.0
var _range_last_position: Vector2 = Vector2.ZERO
var _range_direction: Vector2 = Vector2.ZERO
var _last_finite_position: Vector2 = Vector2.ZERO


func _init() -> void:
	gravity_scale = 0.0
	collision_layer = Layers.SANDAL
	collision_mask = _rest_mask()
	contact_monitor = true
	max_contacts_reported = 8
	can_sleep = false
	lock_rotation = false
	continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE


func _ready() -> void:
	_last_finite_position = global_position
	add_to_group(GROUP)
	if tuning == null:
		tuning = Tuning.load_default()
	mass = tuning.sandal_mass
	linear_damp = tuning.sandal_damping
	angular_damp = tuning.sandal_angular_damping
	var material: PhysicsMaterial = PhysicsMaterial.new()
	material.bounce = tuning.sandal_bounce
	physics_material_override = material
	_shape = CollisionShape2D.new()
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = tuning.sandal_radius
	_shape.shape = circle
	add_child(_shape)
	_build_visual()
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	var other: Sandal = body as Sandal
	if other != null and other.in_flight and not in_flight and not is_placed and not freeze:
		linear_velocity = linear_velocity.limit_length(tuning.rest_hit_speed_cap)
	var speed: float = linear_velocity.length()
	# A NaN velocity passes the "<" test and would reach the audio volume. _physics_process recovers it next frame.
	if not is_finite(speed) or speed < CLACK_MIN_SPEED:
		return
	var loudness: float = linear_to_db(clampf(speed / CLACK_FULL_SPEED, 0.2, 1.0))
	AudioRef.play(&"hit_block" if body is Sandal and in_flight else &"sandal_clack", loudness)


func _physics_process(_delta: float) -> void:
	if freeze:
		in_flight = false
		return
	if not (global_position.is_finite() and linear_velocity.is_finite()):
		_recover_from_non_finite_state()
		return
	_cap_speed()
	_keep_inside_arena()
	var swept_from: Vector2 = _last_finite_position
	_last_finite_position = global_position
	if _range_left > 0.0:
		_fly_ranged()
	if in_flight and linear_velocity.length() < tuning.flight_min_speed:
		in_flight = false
		_hit_this_flight.clear()
	if in_flight:
		_check_character_hits(swept_from)
	if visual != null and linear_velocity.length_squared() > 4.0:
		visual.set_facing(linear_velocity.angle())


## Throws the sandal along [param direction] at [param power] from 0 to 1.
func launch(direction: Vector2, power: float) -> void:
	freeze = false
	linear_velocity = direction.normalized() * tuning.throw_speed_max * clampf(power, 0.0, 1.0)
	_hit_this_flight.clear()
	in_flight = true


## Throws the sandal along [param direction] and stops it after exactly [param distance] pixels.
## The sandal keeps a constant speed until then, so the landing spot does not depend on damping.
## A contact with a wall or another sandal ends the fixed range and normal damping takes over.
## [param speed_power] from 0 to 1 sets the speed, so a weak manual throw still reaches its spot.
func launch_ranged(direction: Vector2, distance: float, speed_power: float = 1.0) -> void:
	last_range = distance
	# A range of zero never ends, so the sandal would keep zero damping and drift for ever.
	if distance <= 0.0:
		freeze = false
		_hit_this_flight.clear()
		halt()
		return
	_range_direction = direction.normalized()
	_range_left = maxf(distance, 0.0)
	_range_last_position = global_position
	linear_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	launch(_range_direction, speed_power)


## A contact with a body or another sandal can hand a sandal far more speed than any throw. That speed
## carries it through a wall in one step, so no sandal moves faster than a full-power throw.
func _cap_speed() -> void:
	linear_velocity = linear_velocity.limit_length(tuning.throw_speed_max)


## Puts the sandal at [param world_position], moved inside the walls. A sandal that starts inside a wall
## or outside the arena can never be picked up, so every hand-off goes through here.
func place_inside(world_position: Vector2) -> void:
	global_position = clamp_to_arena(world_position)


## [param world_position] moved to the nearest point where a sandal fits inside the walls.
func clamp_to_arena(world_position: Vector2) -> Vector2:
	var inside: Rect2 = Rect2(tuning.arena_centre - tuning.arena_half_extents, tuning.arena_half_extents * 2.0).grow(-tuning.sandal_radius)
	return Vector2(
		clampf(world_position.x, inside.position.x, inside.end.x),
		clampf(world_position.y, inside.position.y, inside.end.y))


## Puts a sandal that left the walls back inside, stopped. A sandal outside the walls can never be picked up,
## so the round would wait for it forever.
func _keep_inside_arena() -> void:
	var inside: Rect2 = Rect2(tuning.arena_centre - tuning.arena_half_extents, tuning.arena_half_extents * 2.0).grow(-tuning.sandal_radius)
	if inside.has_point(global_position):
		return
	place_inside(global_position)
	halt()
	_hit_this_flight.clear()


## Puts the sandal back at its last finite position and stops it. A sandal with a NaN position is
## never loose, never picked up and never found, so the defenders would wait for it forever.
func _recover_from_non_finite_state() -> void:
	global_position = _last_finite_position
	angular_velocity = 0.0
	halt()
	_hit_this_flight.clear()


## Stands the sandal on edge in teepee slot [param slot] at [param world_position]. It leans along
## [param lean_toward] (unit vector toward the centre) by [param lean_radians], so the tips meet at the apex.
## It keeps its collision, so a throw can still hit it.
func lock_in_stack(world_position: Vector2, slot: int, lean_toward: Vector2, lean_radians: float) -> void:
	halt()
	freeze_mode = RigidBody2D.FREEZE_MODE_STATIC
	freeze = true
	global_position = world_position
	rotation = lean_toward.angle()
	stack_slot = slot
	lean_direction = lean_toward
	lean_angle = lean_radians
	is_placed = true
	owner_team = NO_OWNER


## Frees the sandal from a pyramid slot. [param impulse] sends it away from the pyramid.
func release_from_stack(impulse: Vector2 = Vector2.ZERO) -> void:
	stack_slot = -1
	lean_direction = Vector2.ZERO
	lean_angle = 0.0
	is_placed = false
	collision_layer = Layers.SANDAL
	collision_mask = _rest_mask()
	freeze = false
	if impulse != Vector2.ZERO:
		apply_central_impulse(impulse)


## Stops all movement and ends the flight.
func halt() -> void:
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	in_flight = false
	_end_ranged()


func _fly_ranged() -> void:
	if get_contact_count() > 0:
		_end_ranged()
		return
	_range_left -= global_position.distance_to(_range_last_position)
	_range_last_position = global_position
	if _range_left > 0.0:
		return
	global_position += _range_direction * _range_left
	halt()


func _end_ranged() -> void:
	if linear_damp_mode == RigidBody2D.DAMP_MODE_COMBINE:
		return
	_range_left = 0.0
	linear_damp_mode = RigidBody2D.DAMP_MODE_COMBINE
	linear_damp = tuning.sandal_damping


## Reports each living character this flight touched, along the whole path since [param from].
## Samples are at most one sandal radius apart, so a fast sandal cannot step over a body.
## A character that can block stops the scan: the sandal moves back to the contact point first.
func _check_character_hits(from: Vector2) -> void:
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	query.shape = _shape.shape
	query.collision_mask = Layers.CHARACTER
	query.collide_with_bodies = true
	query.exclude = [get_rid()]
	var end: Vector2 = global_position
	var steps: int = maxi(ceili(from.distance_to(end) / tuning.sandal_radius), 1)
	for step: int in range(1, steps + 1):
		var point: Vector2 = from.lerp(end, float(step) / float(steps))
		query.transform = Transform2D(rotation, point)
		for result: Dictionary in space.intersect_shape(query, 8):
			var character: Character = result.get("collider") as Character
			if character == null or not character.alive or _hit_this_flight.has(character):
				continue
			_hit_this_flight.append(character)
			var blocked_before: int = ricochets
			if character.can_block():
				global_position = point
			hit_character.emit(character)
			if ricochets != blocked_before or not in_flight:
				return


## Number of guard blocks this sandal has had.
var ricochets: int = 0


## Bounces the sandal off [param blocker] along the contact normal. The speed scales by
## [member Tuning.block_bounce] and the sandal always leaves the body, so it never passes through.
func ricochet(blocker: Character) -> void:
	ricochets += 1
	var speed: float = linear_velocity.length()
	var normal: Vector2 = global_position - blocker.global_position
	if normal.length_squared() < 1.0 and speed > 0.0:
		normal = -linear_velocity
	if normal.length_squared() < 1.0:
		halt()
		return
	normal = normal.normalized()
	var reflected: Vector2 = linear_velocity.bounce(normal) * tuning.block_bounce
	if reflected.dot(normal) <= 0.0:
		reflected = normal * speed * tuning.block_bounce
	var clearance: float = tuning.sandal_radius + blocker.get_body_radius() + 1.0
	global_position = blocker.global_position + normal * clearance
	linear_velocity = reflected
	_end_ranged()
	if reflected.length() < tuning.flight_min_speed:
		halt()


func _build_visual() -> void:
	if visual != null:
		remove_child(visual)
		visual.queue_free()
		visual = null
	var skin: VisualSet = SkinRef.get_visual_set()
	if skin == null:
		return
	visual = skin.make(&"pass_sandal" if is_pass_sandal else &"sandal")
	if visual != null:
		add_child(visual)
		_refresh_tint()


func _refresh_tint() -> void:
	if visual == null or not is_inside_tree():
		return
	if owner_team == NO_OWNER:
		visual.set_team_color(Character.neutral_sandal_color(tuning))
	else:
		visual.set_team_color(Character.color_for_team(owner_team, get_tree(), tuning))


func _rest_mask() -> int:
	return Layers.WORLD | Layers.SANDAL


func _flight_mask() -> int:
	return Layers.WORLD | Layers.SANDAL | Layers.CHARACTER
