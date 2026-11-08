class_name Character
extends CharacterBody2D
## One playable body, driven by a [Controller].
##
## Holds movement, carry, throw, pass, dash and death. It draws nothing: its look
## comes from an [EntityVisual] child built from the active [VisualSet].
## Every number comes from [Tuning]. A missing field falls back to [constant TUNING_DEFAULTS].
##
## [b]Note:[/b] [method die] is ignored while the dash window is open. The scene puts characters
## on collision layer 2 and collides them with layer 1 (walls) only. The round manager sets
## [member pickup_enabled] to false during the topple phase so queued attackers do not take loose sandals.

## Emitted once when this character becomes mati.
signal died
## Emitted when a sandal leaves the hands by [method throw_sandal].
signal threw(sandal: Sandal)
## Emitted when a pass leaves the hands. The human controller follows [param receiver].
signal passed(receiver: Character)
## Emitted when a dash starts.
signal dashed

## Which side of the round this character plays.
enum Role { ATTACKER, DEFENDER }

## Stick push on x under this value keeps the spin direction of an automatic ring.
const RING_DIRECTION_DEADZONE: float = 0.3
## Group of the character the human steers.
const HUMAN_GROUP: StringName = &"human_controlled"
## Colours used when [Tuning] lacks a colour field.
const COLOR_DEFAULTS: Dictionary = {
	&"friendly_color": Color("40bfff"),
	&"enemy_color": Color("ff5230"),
	&"neutral_sandal_color": Color("f4d58d"),
}
## Path of the active skin file. It holds a [SkinRef] or a [VisualSet].
const ACTIVE_SKIN_PATH: String = "res://assets/skins/active.tres"
## Scenes used when the skin file or one of its slots is missing.
const FALLBACK_VISUALS: Dictionary = {
	&"attacker": "res://scenes/visuals/primitives/attacker_visual.tscn",
	&"defender": "res://scenes/visuals/primitives/defender_visual.tscn",
	&"tombstone": "res://scenes/visuals/primitives/tombstone_visual.tscn",
}
## Used for every [Tuning] field that is missing. Units are pixels and seconds.
const TUNING_DEFAULTS: Dictionary = {
	&"move_speed": 230.0,
	&"carry_speed_multiplier": 0.6,
	&"dash_speed": 620.0,
	&"dash_duration": 0.18,
	&"dash_cooldown": 1.6,
	&"character_radius": 18.0,
	&"pickup_radius": 34.0,
	&"throw_speed_max": 900.0,
	&"pass_power": 0.75,
	&"hit_power": 1.0,
	&"pass_bend_degrees": 32.0,
	&"pass_clearance": 46.0,
	&"pass_turn_rate": 4.5,
	&"pass_catch_radius": 30.0,
	&"pass_max_time": 3.0,
	&"build_zone_radius": 90.0,
	&"throw_collision_grace": 0.25,
	&"carry_offset": 22.0,
	&"throw_radius": 260.0,
	&"max_throw_range": 340.0,
	&"min_throw_power": 0.2,
	&"guard_ring_width": 70.0,
	&"guard_stun_seconds": 1.0,
	&"guard_block_cooldown": 4.0,
}

## Team index. Two teams exist, 0 and 1.
@export var team: int = 0
## Current role. Setting it after the node is ready rebuilds the visual.
var role: Role = Role.ATTACKER:
	set(value):
		role = value
		if is_node_ready():
			_rebuild_visual()
## False after [method die].
var alive: bool = true
## Sandal in the hands, or null.
var carried: Sandal = null
## Desired move direction. A controller writes it, length 0.0 to 1.0.
var move_intent: Vector2 = Vector2.ZERO
## Number source. Set before the node enters the tree.
var tuning: Tuning
## Art source. When null the node loads [constant ACTIVE_SKIN_PATH].
var visual_set: VisualSet
## Set by the world. Needed for pass assist and for placing sandals.
var arena: Arena
## Set by the world. Needed for placing sandals.
var stack: Stack
## False blocks picking up. The round manager can switch it off.
var pickup_enabled: bool = true
## True while the body must stand still and cannot dash. The round manager sets it during the match start countdown.
var frozen: bool = false
## Live visual child.
var visual: EntityVisual
## Angle the character faces, in radians.
var facing_angle: float = 0.0
## Seconds left of the invulnerable dash window.
var dash_time_left: float = 0.0
## Seconds until the next dash is allowed.
var dash_cooldown_left: float = 0.0
## Centre of the ring this body is held on. Only used while [member ring_radius] is above zero.
var ring_centre: Vector2 = Vector2.ZERO
## Radius of the ring this body is held on. Zero means free movement. The body then moves along
## the ring only, so it can never step closer to [member ring_centre] or farther from it.
## The body moves by the part of [member move_intent] that points along the ring.
var ring_radius: float = 0.0
## Speed along the ring in pixels per second.
var ring_speed: float = 0.0
## True when the body circles the ring on its own at [member ring_speed]. The body then ignores
## the rest of [member move_intent], and a push left or right only picks [member ring_direction].
var ring_auto: bool = false
## Spin direction of an automatic ring, 1.0 is clockwise on screen and -1.0 is counter-clockwise.
var ring_direction: float = 1.0

## Seconds left of the stun after a guard block. The body cannot move meanwhile.
var guard_stun_left: float = 0.0
## Seconds until this body can block again.
var guard_cooldown_left: float = 0.0

## Distance the blocker slides when a sandal ricochets off it.
const BLOCK_NUDGE: float = 6.0

var _dash_direction: Vector2 = Vector2.RIGHT
var _visual_state: StringName = &""
var _flying_passes: Array[Dictionary] = []

@onready var _body_shape: CollisionShape2D = $CollisionShape2D
@onready var _pickup_area: Area2D = $PickupArea
@onready var _pickup_shape: CollisionShape2D = $PickupArea/CollisionShape2D


## Team the human plays on. A character in the group [constant HUMAN_GROUP] decides it, and
## [member Tuning.human_team] answers while no human character exists.
static func human_team(tree: SceneTree, tuning: Tuning) -> int:
	var human: Node = tree.get_first_node_in_group(HUMAN_GROUP)
	if human is Character:
		return (human as Character).team
	var value: Variant = tuning.get(&"human_team") if tuning != null else null
	return int(value) if value != null else 0


## Colour of [param team] seen from the human's side: friendly blue for the human's team,
## enemy red for the other team. A role or a round never changes it.
static func color_for_team(team: int, tree: SceneTree, tuning: Tuning) -> Color:
	var key: StringName = &"friendly_color" if team == human_team(tree, tuning) else &"enemy_color"
	return tuned_color(key, tuning)


## Colour of a sandal nobody holds.
static func neutral_sandal_color(tuning: Tuning) -> Color:
	return tuned_color(&"neutral_sandal_color", tuning)


## Reads a colour from [param tuning] and falls back to [constant COLOR_DEFAULTS].
static func tuned_color(key: StringName, tuning: Tuning) -> Color:
	var value: Variant = tuning.get(key) if tuning != null else null
	if value is Color:
		return value
	return COLOR_DEFAULTS[key]


func _ready() -> void:
	var body_circle: CircleShape2D = CircleShape2D.new()
	body_circle.radius = _tuned(&"character_radius")
	_body_shape.shape = body_circle
	var pickup_circle: CircleShape2D = CircleShape2D.new()
	pickup_circle.radius = _tuned(&"pickup_radius")
	_pickup_shape.shape = pickup_circle
	if visual_set == null:
		visual_set = _load_active_visual_set()
	_rebuild_visual()


func _physics_process(delta: float) -> void:
	if not alive:
		return
	dash_time_left = maxf(dash_time_left - delta, 0.0)
	dash_cooldown_left = maxf(dash_cooldown_left - delta, 0.0)
	guard_stun_left = maxf(guard_stun_left - delta, 0.0)
	guard_cooldown_left = maxf(guard_cooldown_left - delta, 0.0)
	if frozen or guard_stun_left > 0.0:
		velocity = Vector2.ZERO
	else:
		_apply_movement()
	_steer_passes(delta)
	_handle_nearby_sandals()
	_update_carried()
	_update_zone_drop()
	_update_visual_state()


## Holds this body on a ring around [param centre]. Pass a radius of zero to move freely again.
## [param speed] is the speed along the ring in pixels per second. With [param auto] the body
## circles the ring by itself and the controller only picks the direction.
func hold_on_ring(centre: Vector2, radius: float, speed: float, auto: bool = false) -> void:
	ring_centre = centre
	ring_radius = radius
	ring_speed = speed
	ring_auto = auto


## Sets team, role and number sources in one call. Call before adding the node to the tree.
func configure(new_team: int, new_role: Role, new_tuning: Tuning, new_visual_set: VisualSet = null) -> void:
	team = new_team
	role = new_role
	tuning = new_tuning
	visual_set = new_visual_set


## True while the dash window is open and hits do not count.
func is_invulnerable() -> bool:
	return dash_time_left > 0.0


## True when [method dash] would start a dash.
func can_dash() -> bool:
	return alive and not frozen and dash_cooldown_left <= 0.0 and dash_time_left <= 0.0


## True while this attacker stands in the guard ring with free hands and can absorb one hit.
## The builder and a carrier are never covered.
func can_block() -> bool:
	if not alive or role != Role.ATTACKER or guard_cooldown_left > 0.0 or is_invulnerable():
		return false
	if carried != null or is_building() or arena == null:
		return false
	var distance: float = global_position.distance_to(arena.centre_spot)
	var inner: float = _tuned(&"build_zone_radius")
	return distance >= inner and distance <= inner + _tuned(&"guard_ring_width")


## Radius of the body shape in pixels.
func get_body_radius() -> float:
	return _tuned(&"character_radius")


## Absorbs a hit: stuns this body, starts the cooldown and slides it away along [param push].
func block(push: Vector2) -> void:
	guard_stun_left = _tuned(&"guard_stun_seconds")
	guard_cooldown_left = _tuned(&"guard_block_cooldown")
	velocity = Vector2.ZERO
	if push != Vector2.ZERO:
		move_and_collide(push.normalized() * BLOCK_NUDGE)
	AudioRef.play(&"hit_block")
	FxRef.burst(&"block", global_position)


## Share of the dash cooldown still left, 0.0 (ready) to 1.0 (just used).
func dash_cooldown_ratio() -> float:
	return clampf(dash_cooldown_left / _tuned(&"dash_cooldown"), 0.0, 1.0)


## Throws the carried sandal in [param direction]. An attacker throws a fixed range: the sandal
## flies [member Tuning.throw_radius] from this body and stops, and [param power] is ignored.
## A defender throws at [param power] from 0.0 to 1.0. Returns false when nothing was thrown.
func throw_sandal(direction: Vector2, power: float) -> bool:
	if not alive or carried == null:
		return false
	var throw_direction: Vector2 = _direction_or_facing(direction)
	var sandal: Sandal = _release_carried()
	var hand_offset: float = _tuned(&"character_radius") + 12.0
	sandal.place_inside(global_position + throw_direction * hand_offset)
	_ignore_sandal_briefly(sandal)
	if role == Role.ATTACKER:
		sandal.launch_ranged(throw_direction, _tuned(&"throw_radius") - hand_offset)
	else:
		sandal.launch(throw_direction, clampf(power, 0.0, 1.0))
	_face(throw_direction.angle())
	_play_visual(&"throw")
	_feedback_throw()
	threw.emit(sandal)
	return true


## Throws the carried sandal along [param direction] by hand. [param power] from 0.0 to 1.0 sets both the
## distance, [member Tuning.max_throw_range] at full power, and the speed. The sandal does not home and
## stops where the range ends. Works for either role. Returns false when nothing was thrown.
func throw_manual(direction: Vector2, power: float) -> bool:
	if not alive or carried == null:
		return false
	var clamped: float = clampf(power, 0.0, 1.0)
	var throw_direction: Vector2 = _direction_or_facing(direction)
	var sandal: Sandal = _release_carried()
	var hand_offset: float = _tuned(&"character_radius") + 12.0
	sandal.place_inside(global_position + throw_direction * hand_offset)
	_ignore_sandal_briefly(sandal)
	var range_left: float = _tuned(&"max_throw_range") * clamped - hand_offset
	sandal.launch_ranged(throw_direction, range_left, maxf(clamped, _tuned(&"min_throw_power")))
	_face(throw_direction.angle())
	_play_visual(&"throw")
	_feedback_throw()
	threw.emit(sandal)
	return true


## Throws the carried sandal at the foe [param target], aimed at the point where the foe will be.
## The power is fixed at [member Tuning.hit_power], so no gesture sets it. Returns false when nothing was thrown.
func hit(target: Character) -> bool:
	if not alive or carried == null or target == null or not target.alive or target == self:
		return false
	var power: float = _tuned(&"hit_power")
	return throw_sandal(lead_direction(target, power), power)


## Passes the carried sandal to [param target]. The sandal bends around an attacker in the way
## and then steers toward the target. Returns false when nothing was passed.
func pass_to(target: Character) -> bool:
	if not alive or carried == null or target == null or not target.alive or target == self:
		return false
	var pass_direction: Vector2 = _bent_pass_direction(target)
	var sandal: Sandal = _release_carried()
	sandal.place_inside(global_position + pass_direction * (_tuned(&"character_radius") + 12.0))
	_ignore_sandal_briefly(sandal)
	sandal.launch(pass_direction, _tuned(&"pass_power"))
	_flying_passes.append({"sandal": sandal, "target": target, "time": 0.0})
	_face(pass_direction.angle())
	_play_visual(&"throw")
	AudioRef.play(&"pass")
	passed.emit(target)
	return true


## Starts a dash toward the move intent. Returns false while on cooldown.
func dash() -> bool:
	if not can_dash():
		return false
	_dash_direction = _direction_or_facing(move_intent)
	dash_time_left = _tuned(&"dash_duration")
	dash_cooldown_left = _tuned(&"dash_cooldown")
	_play_visual(&"dash")
	AudioRef.play(&"dash")
	FxRef.burst(&"dash", global_position)
	dashed.emit()
	return true


## Makes this character mati. There is no respawn. Ignored while invulnerable.
func die() -> void:
	if not alive:
		return
	if is_invulnerable():
		_play_visual(&"hit")
		return
	alive = false
	stop_building()
	move_intent = Vector2.ZERO
	velocity = Vector2.ZERO
	var dropped: Sandal = _release_carried_or_null()
	if dropped != null:
		dropped.place_inside(global_position)
		if not dropped.is_pass_sandal:
			dropped.owner_team = Sandal.NO_OWNER
	_flying_passes.clear()
	_body_shape.set_deferred("disabled", true)
	_pickup_shape.set_deferred("disabled", true)
	_replace_visual(&"tombstone")
	_play_visual(&"die")
	AudioRef.play(&"death")
	FxRef.burst(&"death", global_position, _team_color())
	died.emit()


## Takes [param sandal] into the hands. Returns false when the hands are full or the sandal is held.
func pick_up(sandal: Sandal) -> bool:
	if not alive or carried != null or sandal == null or not is_instance_valid(sandal):
		return false
	# A frozen sandal is already held or standing in the pyramid. Taking it would give it two holders.
	if sandal.freeze:
		return false
	carried = sandal
	sandal.owner_team = team
	sandal.freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC
	sandal.freeze = true
	sandal.linear_velocity = Vector2.ZERO
	sandal.angular_velocity = 0.0
	sandal.in_flight = false
	sandal.add_collision_exception_with(self)
	_update_carried()
	AudioRef.play(&"catch" if sandal.is_pass_sandal else &"pickup")
	FxRef.burst(&"pickup", global_position)
	return true


## Where to throw so a sandal at [param power] meets a moving [param target].
func lead_direction(target: Character, power: float) -> Vector2:
	var to_target: Vector2 = target.global_position - global_position
	var sandal_speed: float = _tuned(&"throw_speed_max") * clampf(power, 0.05, 1.0)
	var target_velocity: Vector2 = target.velocity
	var a: float = target_velocity.dot(target_velocity) - sandal_speed * sandal_speed
	var b: float = 2.0 * to_target.dot(target_velocity)
	var c: float = to_target.dot(to_target)
	var travel_time: float = -1.0
	if absf(a) < 0.0001:
		if b < 0.0:
			travel_time = -c / b
	else:
		var discriminant: float = b * b - 4.0 * a * c
		if discriminant >= 0.0:
			var root: float = sqrt(discriminant)
			var first: float = (-b - root) / (2.0 * a)
			var second: float = (-b + root) / (2.0 * a)
			var positives: Array[float] = []
			if first > 0.0:
				positives.append(first)
			if second > 0.0:
				positives.append(second)
			if not positives.is_empty():
				travel_time = positives.min()
	if travel_time <= 0.0:
		return to_target.normalized()
	return (to_target + target_velocity * travel_time).normalized()


func _feedback_throw() -> void:
	AudioRef.play(&"throw")
	FxRef.burst(&"throw", global_position)


func _tuned(key: StringName) -> float:
	var fallback: float = TUNING_DEFAULTS[key]
	if tuning == null:
		return fallback
	var value: Variant = tuning.get(key)
	if value == null:
		return fallback
	return float(value)


func _direction_or_facing(direction: Vector2) -> Vector2:
	if direction.length_squared() < 0.0001:
		return Vector2.from_angle(facing_angle)
	return direction.normalized()


func _face(angle: float) -> void:
	facing_angle = angle
	if visual != null:
		visual.set_facing(angle)


func _play_visual(state: StringName) -> void:
	if visual != null:
		visual.play(state)


func _team_color() -> Color:
	return color_for_team(team, get_tree(), tuning)


func _rebuild_visual() -> void:
	_replace_visual(&"attacker" if role == Role.ATTACKER else &"defender")


func _replace_visual(slot: StringName) -> void:
	if visual != null:
		remove_child(visual)
		visual.queue_free()
		visual = null
	if visual_set != null:
		visual = visual_set.make(slot)
	if visual == null:
		var fallback: PackedScene = load(FALLBACK_VISUALS[slot]) as PackedScene
		visual = fallback.instantiate() as EntityVisual
	add_child(visual)
	visual.set_team_color(_team_color())
	visual.set_facing(facing_angle)
	_visual_state = &""


func _load_active_visual_set() -> VisualSet:
	if SettingsRef.view() == SettingsRef.VIEW_DEPTH:
		return SkinRef.get_visual_set()
	if not ResourceLoader.exists(ACTIVE_SKIN_PATH):
		return null
	var loaded: Resource = load(ACTIVE_SKIN_PATH)
	if loaded is SkinRef:
		return (loaded as SkinRef).visual_set
	return loaded as VisualSet


func _apply_movement() -> void:
	if is_invulnerable():
		velocity = _dash_direction * _tuned(&"dash_speed")
	else:
		var speed: float = _tuned(&"move_speed")
		if carried != null:
			speed *= _tuned(&"carry_speed_multiplier")
		velocity = move_intent.limit_length(1.0) * speed
	if ring_radius > 0.0:
		velocity = _ring_velocity()
	move_and_slide()
	if ring_radius > 0.0:
		_snap_to_ring()
	if velocity.length_squared() > 1.0:
		_face(velocity.angle())


func _ring_velocity() -> Vector2:
	var outward: Vector2 = global_position - ring_centre
	if outward.length_squared() < 0.0001:
		return Vector2.ZERO
	var tangent: Vector2 = outward.rotated(PI * 0.5).normalized()
	if ring_auto:
		if absf(move_intent.x) > RING_DIRECTION_DEADZONE:
			ring_direction = signf(move_intent.x)
		return tangent * ring_direction * ring_speed
	if is_invulnerable():
		return tangent * _dash_direction.dot(tangent) * _tuned(&"dash_speed")
	var carry_factor: float = _tuned(&"carry_speed_multiplier") if carried != null else 1.0
	return tangent * clampf(move_intent.dot(tangent), -1.0, 1.0) * ring_speed * carry_factor


func _snap_to_ring() -> void:
	var outward: Vector2 = global_position - ring_centre
	if outward.length_squared() < 0.0001:
		return
	global_position = ring_centre + outward.normalized() * ring_radius


func _update_visual_state() -> void:
	var state: StringName = &"idle"
	if is_invulnerable():
		state = &"dash"
	elif carried != null:
		state = &"carry"
	elif velocity.length_squared() > 1.0:
		state = &"run"
	if state != _visual_state:
		_visual_state = state
		_play_visual(state)


func _update_carried() -> void:
	if carried == null or not is_instance_valid(carried):
		carried = null
		return
	carried.place_inside(global_position + Vector2.from_angle(facing_angle) * _tuned(&"carry_offset"))


func _release_carried_or_null() -> Sandal:
	if carried == null:
		return null
	return _release_carried()


func _release_carried() -> Sandal:
	var sandal: Sandal = carried
	carried = null
	sandal.freeze = false
	sandal.remove_collision_exception_with(self)
	return sandal


func _ignore_sandal_briefly(sandal: Sandal) -> void:
	sandal.add_collision_exception_with(self)
	get_tree().create_timer(_tuned(&"throw_collision_grace")).timeout.connect(_clear_sandal_exception.bind(sandal))


func _clear_sandal_exception(sandal: Variant) -> void:
	if is_instance_valid(sandal):
		(sandal as Sandal).remove_collision_exception_with(self)


func _enemy_team() -> int:
	return 1 - team


func _bent_pass_direction(target: Character) -> Vector2:
	var straight: Vector2 = (target.global_position - global_position).normalized()
	if arena == null:
		return straight
	var distance_to_target: float = global_position.distance_to(target.global_position)
	var clearance: float = _tuned(&"pass_clearance")
	var blocker: Character = null
	var blocker_gap: float = clearance
	for foe: Variant in arena.get_characters(_enemy_team()):
		var other: Character = foe as Character
		if other == null or not other.alive:
			continue
		var offset: Vector2 = other.global_position - global_position
		var along: float = offset.dot(straight)
		if along <= 0.0 or along >= distance_to_target:
			continue
		var gap: float = absf(offset.cross(straight))
		if gap < blocker_gap:
			blocker_gap = gap
			blocker = other
	if blocker == null:
		return straight
	var side: float = signf((blocker.global_position - global_position).cross(straight))
	if side == 0.0:
		side = 1.0
	return straight.rotated(side * deg_to_rad(_tuned(&"pass_bend_degrees")))


func _steer_passes(delta: float) -> void:
	var still_flying: Array[Dictionary] = []
	for entry: Dictionary in _flying_passes:
		var sandal_ref: Variant = entry["sandal"]
		var target_ref: Variant = entry["target"]
		entry["time"] = float(entry["time"]) + delta
		if not is_instance_valid(sandal_ref) or not is_instance_valid(target_ref):
			continue
		var sandal: Sandal = sandal_ref as Sandal
		var target: Character = target_ref as Character
		if float(entry["time"]) > _tuned(&"pass_max_time") or not target.alive:
			continue
		if sandal.global_position.distance_to(target.global_position) <= _tuned(&"pass_catch_radius"):
			target.pick_up(sandal)
			continue
		var speed: float = sandal.linear_velocity.length()
		if speed > 1.0:
			var heading: Vector2 = sandal.linear_velocity / speed
			var wanted: Vector2 = (target.global_position - sandal.global_position).normalized()
			var max_turn: float = _tuned(&"pass_turn_rate") * delta
			var turn: float = clampf(heading.angle_to(wanted), -max_turn, max_turn)
			sandal.linear_velocity = heading.rotated(turn) * speed
		still_flying.append(entry)
	_flying_passes = still_flying


func _handle_nearby_sandals() -> void:
	if not pickup_enabled:
		return
	for body: Node2D in _pickup_area.get_overlapping_bodies():
		var sandal: Sandal = body as Sandal
		if sandal == null or sandal == carried or sandal.in_flight or sandal.freeze:
			continue
		if role == Role.DEFENDER:
			if sandal.is_pass_sandal:
				if carried == null:
					pick_up(sandal)
					return
		elif carried == null and not sandal.is_pass_sandal and not _is_delivered(sandal):
			pick_up(sandal)
			return


## True when [param sandal] already lies in the build zone of a down pyramid. Attackers leave it
## there, so a delivered sandal is never carried out again.
func _is_delivered(sandal: Sandal) -> bool:
	return stack != null and stack.is_down and stack.is_in_zone(sandal.global_position)


## An attacker that carries a stack sandal into the build zone drops it there at once. The drop
## needs no input, so a human and a bot deliver the same way, one sandal at a time.
func _update_zone_drop() -> void:
	if carried == null or role != Role.ATTACKER or stack == null or not stack.is_down or carried.is_pass_sandal:
		return
	if not stack.is_in_zone(global_position):
		return
	var dropped: Sandal = _release_carried()
	dropped.place_inside(global_position)
	dropped.owner_team = Sandal.NO_OWNER
	_ignore_sandal_briefly(dropped)
	AudioRef.play(&"place")


## Puts the carried sandal on the ground at [param world_position]. A human who stands still would
## pick it up again at once, so the round manager drops it inside the build zone instead.
func drop_carried(world_position: Vector2) -> void:
	if carried == null:
		return
	var dropped: Sandal = _release_carried()
	dropped.place_inside(world_position)
	dropped.owner_team = Sandal.NO_OWNER
	_ignore_sandal_briefly(dropped)


## Starts a build at the pyramid. Returns false unless all three sandals are in the zone, nobody
## carries one and this attacker stands in the zone. The builder moves and can be hit as usual.
func start_building() -> bool:
	if not alive or role != Role.ATTACKER or stack == null or carried != null:
		return false
	return stack.begin_build(self)


## Stops this character's build. Placed sandals stay placed.
func stop_building() -> void:
	if stack != null and stack.builder == self:
		stack.end_build(self)


## True while this character builds.
func is_building() -> bool:
	return stack != null and stack.builder == self


## Places the next sandal of the build. Returns false when this character does not build.
func complete_build_step() -> bool:
	if not is_building():
		return false
	return stack.place_sandal()
