class_name ThrowScheme
extends Node2D
## Shared part of both throw schemes: targets, the lock, the world preview and the fire call.
##
## A scheme never moves the character and never changes throw power. It picks a target, draws
## where the sandal will go, and calls [method Character.throw_sandal], [method Character.pass_to]
## or [method Character.hit]. Bots never use a scheme. They call the character directly.
## The preview is drawn in the world, so it follows the camera. It never draws text.

## Emitted when the lock moves to another target. [param target] is null for the stack.
signal lock_changed(target: Character)
## Emitted after a throw fired.
signal fired
## Emitted when the player cancelled a throw before it fired.
signal cancelled

## What a lock points at.
enum TargetKind {
	STACK, ## The stack in the middle. Attackers always lock it.
	FRIEND, ## A teammate. Firing passes.
	FOE, ## An enemy. Firing hits.
	NONE, ## Nothing to throw at.
}

## Line width of the preview in world pixels.
const LINE_WIDTH: float = 5.0
## Radius of the ring drawn on the target.
const RING_RADIUS: float = 30.0
## Segments of a bent pass path.
const PATH_STEPS: int = 18

## The character this scheme fires for. Set by the controller.
var character: Character
## Tuning values for the lock and the preview.
var tuning: Tuning
## True when the preview is visible. The scheme turns it on while the player aims.
var previewing: bool = false:
	set(value):
		if previewing != value:
			previewing = value
			queue_redraw()
## The locked target, or null while the lock is on the stack or on nothing.
var locked: Character = null
## What the lock points at now.
var kind: TargetKind = TargetKind.NONE


func _ready() -> void:
	z_index = 20
	if tuning == null:
		tuning = Tuning.load_default()


func _process(_delta: float) -> void:
	if previewing:
		queue_redraw()


func _draw() -> void:
	begin_ground_draw()
	if not previewing or character == null or not is_instance_valid(character):
		return
	if character.carried == null or kind == TargetKind.NONE:
		return
	if not draws_target_preview():
		return
	var origin: Vector2 = to_local(character.global_position)
	var tint: Color = preview_color()
	var aim_point: Vector2 = _aim_point()
	if kind == TargetKind.FRIEND and locked != null:
		_draw_pass_path(origin, to_local(locked.global_position), tint)
	else:
		draw_dashed_line(origin, to_local(aim_point), tint, LINE_WIDTH, 14.0)
	_draw_target_ring(to_local(_ring_centre()), tint)
	if kind == TargetKind.FOE and locked != null:
		_draw_lead_marker(to_local(aim_point), tint)
	if is_lane_blocked():
		_draw_blocked_cross(to_local(character.global_position.lerp(aim_point, 0.5)))


## Makes the next draw calls take ground points and show them on the floor of the active view. Call it first in a draw.
func begin_ground_draw() -> void:
	draw_set_transform_matrix(ViewProjection.overlay_transform(get_viewport()))


## Canvas position, in this node's draw space, that shows the ground point [param point] on the screen.
func screen_to_canvas_point(point: Vector2) -> Vector2:
	var viewport: Viewport = get_viewport()
	return viewport.get_canvas_transform().affine_inverse() * ViewProjection.to_screen(viewport, point)


## Builds the list of characters the lock can move to. Attackers only ever lock the stack,
## so their list is empty. A defender gets living teammates and living foes, never itself.
func candidates() -> Array[Character]:
	var found: Array[Character] = []
	if character == null or not is_instance_valid(character) or character.arena == null:
		return found
	if character.role == Character.Role.ATTACKER:
		return found
	for team: int in 2:
		for entry: Variant in character.arena.get_characters(team):
			var other: Character = entry as Character
			if other != null and other != character and other.alive:
				found.append(other)
	return found


## The best lock before the player touches anything. An attacker locks the stack. A defender
## locks the foe that carries a sandal nearest to the stack spot, then the nearest foe, then
## the nearest teammate. Returns null when a defender has nobody to throw at.
func default_target() -> Character:
	var foes: Array[Character] = []
	var mates: Array[Character] = []
	for other: Character in candidates():
		if other.team == character.team:
			mates.append(other)
		else:
			foes.append(other)
	var best: Character = null
	var best_distance: float = INF
	for foe: Character in foes:
		if foe.carried == null:
			continue
		var distance: float = foe.global_position.distance_to(character.arena.centre_spot)
		if distance < best_distance:
			best_distance = distance
			best = foe
	if best != null:
		return best
	best = _nearest(foes)
	if best != null:
		return best
	return _nearest(mates)


## Sets the lock to the default for the controlled character. Call when a throw starts
## or when the character changes.
func reset_lock() -> void:
	if character == null or not is_instance_valid(character):
		_set_lock(null, TargetKind.NONE)
		return
	if character.role == Character.Role.ATTACKER:
		_set_lock(null, TargetKind.STACK)
		return
	var target: Character = default_target()
	_set_lock(target, _kind_of(target))


## Moves the lock to the candidate nearest to [param bearing] inside [member Tuning.lock_cone_degrees].
## A new target must beat the current one by [member Tuning.lock_hysteresis_degrees]. With no
## candidate in the cone the lock stays. Returns true when the lock moved.
func steer_lock(bearing: Vector2) -> bool:
	if character == null or character.role == Character.Role.ATTACKER or bearing.length() < 0.01:
		return false
	var cone: float = deg_to_rad(tuning.lock_cone_degrees)
	var margin: float = deg_to_rad(tuning.lock_hysteresis_degrees)
	var best: Character = null
	var best_angle: float = cone
	for other: Character in candidates():
		var angle: float = absf(bearing.angle_to(other.global_position - character.global_position))
		if angle < best_angle:
			best_angle = angle
			best = other
	if best == null or best == locked:
		return false
	if locked != null and is_instance_valid(locked) and locked.alive:
		var current_angle: float = absf(bearing.angle_to(locked.global_position - character.global_position))
		if best_angle > current_angle - margin:
			return false
	_set_lock(best, _kind_of(best))
	return true


## Throws at the current lock. Returns true when a sandal left the hand.
func fire() -> bool:
	if character == null or not is_instance_valid(character) or not character.alive or character.carried == null:
		return false
	var thrown: bool = false
	match kind:
		TargetKind.STACK:
			thrown = character.throw_sandal(_stack_direction(), 1.0)
		TargetKind.FRIEND:
			thrown = locked != null and character.pass_to(locked)
		TargetKind.FOE:
			thrown = locked != null and character.hit(locked)
	if thrown:
		SettingsRef.vibrate(tuning.haptic_fire_ms)
		fired.emit()
	return thrown


## Fires along [param direction] with no target, for the aim stick on a stack-less line.
## An attacker throws a fixed range. A defender with no target in the cone passes nothing and returns false.
func fire_along(direction: Vector2) -> bool:
	if character == null or not character.alive or character.carried == null or direction.length() < 0.01:
		return false
	if character.role != Character.Role.ATTACKER:
		return false
	var thrown: bool = character.throw_sandal(direction.normalized(), 1.0)
	if thrown:
		SettingsRef.vibrate(tuning.haptic_fire_ms)
		fired.emit()
	return thrown


## Drops the lock and the preview without throwing.
func cancel() -> void:
	previewing = false
	cancelled.emit()


## Colour of the preview: friend blue, foe red, sand for the stack.
func preview_color() -> Color:
	match kind:
		TargetKind.FRIEND:
			return tuning.friendly_color
		TargetKind.FOE:
			return tuning.enemy_color
	return tuning.preview_stack_color


## True when a foe stands close to the straight line to the target, so the throw may be stopped.
## A pass bends around the foe, so a blocked pass lane is only a warning.
func is_lane_blocked() -> bool:
	if character == null or character.arena == null or kind == TargetKind.NONE:
		return false
	var from: Vector2 = character.global_position
	var to: Vector2 = _aim_point()
	var line: Vector2 = to - from
	var length: float = line.length()
	if length < 1.0:
		return false
	var direction: Vector2 = line / length
	var clearance: float = tuning.character_radius + tuning.sandal_radius
	for entry: Variant in character.arena.get_characters(1 - character.team):
		var foe: Character = entry as Character
		if foe == null or not foe.alive or foe == locked:
			continue
		var offset: Vector2 = foe.global_position - from
		var along: float = offset.dot(direction)
		if along <= 0.0 or along >= length:
			continue
		if absf(offset.cross(direction)) < clearance:
			return true
	return false


## True when the base preview (line, target ring, lead marker) should draw. A scheme that aims freely
## turns it off for the throws where the aim, and not a target, sets the direction.
func draws_target_preview() -> bool:
	return true


## Where the sandal is aimed: the stack spot, a teammate, or the lead point of a foe.
func _aim_point() -> Vector2:
	match kind:
		TargetKind.FRIEND:
			return locked.global_position if locked != null else character.global_position
		TargetKind.FOE:
			if locked != null:
				var lead: Vector2 = character.lead_direction(locked, tuning.hit_power)
				var distance: float = character.global_position.distance_to(locked.global_position)
				return character.global_position + lead * distance
			return character.global_position
	return character.arena.centre_spot if character.arena != null else character.global_position


func _ring_centre() -> Vector2:
	if locked != null and (kind == TargetKind.FRIEND or kind == TargetKind.FOE):
		return locked.global_position
	return character.arena.centre_spot if character.arena != null else character.global_position


func _stack_direction() -> Vector2:
	var centre: Vector2 = character.arena.centre_spot if character.arena != null else Vector2.ZERO
	return (centre - character.global_position).normalized()


func _nearest(group: Array[Character]) -> Character:
	var best: Character = null
	var best_distance: float = INF
	for other: Character in group:
		var distance: float = other.global_position.distance_to(character.global_position)
		if distance < best_distance:
			best_distance = distance
			best = other
	return best


func _kind_of(target: Character) -> TargetKind:
	if target == null:
		return TargetKind.NONE
	return TargetKind.FRIEND if target.team == character.team else TargetKind.FOE


func _set_lock(target: Character, new_kind: TargetKind) -> void:
	var changed: bool = target != locked or new_kind != kind
	locked = target
	kind = new_kind
	if changed:
		lock_changed.emit(target)
		SettingsRef.vibrate(tuning.haptic_lock_ms)
		queue_redraw()


func _draw_target_ring(centre: Vector2, tint: Color) -> void:
	draw_arc(centre, RING_RADIUS, 0.0, TAU, 40, tint, LINE_WIDTH)
	draw_arc(centre, RING_RADIUS + 8.0, 0.0, TAU, 40, Color(tint, 0.45), 2.0)


func _draw_lead_marker(point: Vector2, tint: Color) -> void:
	var arm: float = 12.0
	draw_line(point + Vector2(-arm, 0.0), point + Vector2(arm, 0.0), tint, 3.0)
	draw_line(point + Vector2(0.0, -arm), point + Vector2(0.0, arm), tint, 3.0)
	draw_arc(point, 7.0, 0.0, TAU, 20, tint, 3.0)


func _draw_blocked_cross(centre: Vector2) -> void:
	var arm: float = 12.0
	var tint: Color = Color(1.0, 1.0, 1.0, 0.95)
	draw_circle(centre, arm + 5.0, Color(0.06, 0.09, 0.16, 0.85))
	draw_line(centre + Vector2(-arm, -arm) * 0.7, centre + Vector2(arm, arm) * 0.7, tint, 4.0)
	draw_line(centre + Vector2(-arm, arm) * 0.7, centre + Vector2(arm, -arm) * 0.7, tint, 4.0)


func _draw_pass_path(origin: Vector2, target: Vector2, tint: Color) -> void:
	var bend: Vector2 = Vector2.ZERO
	var world_origin: Vector2 = character.global_position
	var world_target: Vector2 = to_global(target)
	var straight: Vector2 = (world_target - world_origin)
	var length: float = straight.length()
	if length > 1.0 and is_lane_blocked():
		var side: float = signf(straight.cross(_first_blocker_offset(world_origin, straight / length)))
		bend = straight.orthogonal().normalized() * length * 0.22 * (side if side != 0.0 else 1.0)
	var previous: Vector2 = origin
	for step: int in range(1, PATH_STEPS + 1):
		var t: float = float(step) / float(PATH_STEPS)
		var point: Vector2 = origin.lerp(target, t) + bend * sin(PI * t)
		if step % 2 == 1:
			draw_line(previous, point, tint, LINE_WIDTH)
		previous = point


func _first_blocker_offset(from: Vector2, direction: Vector2) -> Vector2:
	var clearance: float = tuning.character_radius + tuning.sandal_radius
	for entry: Variant in character.arena.get_characters(1 - character.team):
		var foe: Character = entry as Character
		if foe == null or not foe.alive or foe == locked:
			continue
		var offset: Vector2 = foe.global_position - from
		var along: float = offset.dot(direction)
		if along > 0.0 and absf(offset.cross(direction)) < clearance:
			return offset
	return direction.orthogonal()
