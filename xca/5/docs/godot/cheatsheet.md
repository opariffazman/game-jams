# Godot 4.6 jam cheat sheet

Target: GamePix web game, Godot 4.6.3, GDScript, `gl_compatibility`, single-thread web export.
Landscape only. Touch first. Top-down team arena with AI bots.

Style source: `/home/ariff/repo/skills/godot-gdscript-style/SKILL.md` and its `references/` files. This sheet follows it and never overrides it.

## Test status

- Tested with Godot 4.6.3 stable in a scratch project under `/tmp`. Command: `godot --headless --path <project> --check-only --script <file>`.
- Parse check passed with zero errors for all 13 scripts: joystick, throw control, arena, sandal, bot, player, three tuning resources, `GameFeel`, camera shake, squash, tap-to-start.
- The scratch project registered `GameFeel` as an autoload and imported every `class_name`, so cross-script types resolved.
- A deliberately broken script printed `Parse Error` and `Failed to load script`. The check can detect errors.
- Exit code on a parse error is unconfirmed. Check the output text for `Parse Error`.
- Not tested: runtime behavior, scenes, touch on a device, navigation baking, web export.
- Unconfirmed: `create_timer` argument order. It parsed, so the signature is valid.
- Doc claims carry a source URL. A claim without a URL is marked "unconfirmed".

## 1. Project layout and naming

```
project.godot
autoload/        game_feel.gd, audio_bus.gd
scenes/          arena/, units/, ui/
scripts/         mirrors scenes/ when a script is shared
resources/       tuning/*.tres
assets/          art/, audio/, fonts/
```

Rules from the style skill (`references/naming-and-order.md`):

| Item | Style | Example |
|---|---|---|
| File | snake_case | `virtual_joystick.gd` |
| Class | PascalCase | `class_name VirtualJoystick` |
| Node | PascalCase | `$NavigationAgent2D` |
| Function, variable | snake_case | `func launch()` |
| Signal | snake_case, past tense | `signal sandal_thrown` |
| Constant | CONSTANT_CASE | `const KNOB_RADIUS` |
| Enum | PascalCase, members CONSTANT_CASE | `enum State { CHASE }` |

Script member order: signal, enum, const, `@export var`, `var`, `@onready var`, virtual functions (`_init`, `_ready`, `_process`, `_physics_process`), custom functions.

- Write a `##` doc comment on every class, export, signal, enum, const, and public function.
- Type every var, parameter, and return value.
- Never modify `.uid`, `.import`, `.godot/`, or lock files.
- Keep one scene per file. Name the scene file after its root node in snake_case.

## 2. Scene and node composition

- Build each unit as a scene with one script on the root. Examples: `Player`, `Bot`, `Sandal`.
- Compose with child nodes, not deep inheritance. A bot is a `CharacterBody2D` plus a `NavigationAgent2D`.
- Give each scene one job. The arena wires scenes together. Units never know the arena.
- Use `@export var x: PackedScene` for spawnable scenes. Never hardcode `res://` paths in logic.
- Use `@export var node: Type` for sibling wiring. It shows in the inspector and survives renames.
- Use groups for broad queries. This sheet uses `brawlers` and `sandals`.
- Put tuning values in Resources (section 9). Never bury numbers in scripts.
- Set collision layers once and document them:

| Layer | Name | Used by |
|---|---|---|
| 1 | walls | `StaticBody2D` arena walls |
| 2 | brawlers | `Player`, `Bot` |
| 3 | sandals | `Sandal` `Area2D` |

`Sandal` mask: layers 1 and 2. `Brawler` mask: layer 1.

## 3. Signals versus direct calls

| Direction | Use |
|---|---|
| Child to parent, or unit to arena | Signal. Past-tense name. |
| Parent to child | Direct call on a typed reference. |
| Sibling to sibling | Parent connects them. Siblings never reach each other. |
| Anything to many listeners (score, UI) | Signal on an autoload or the arena. |

- Connect with `signal.connect(callable)`. Never use the string form from Godot 3.
- Emit with `signal.emit(args)`.
- Never call `get_node("../..")` to climb the tree. Pass a reference or connect a signal.
- Use `call_deferred` or `CONNECT_DEFERRED` when a signal handler changes the physics state or frees nodes.
  Source: https://docs.godotengine.org/en/4.6/classes/class_navigationagent2d.html (navigation calls inside signals can recurse).

## 4. Autoload rules

- Keep autoloads to three or fewer. Suggested: `GameFeel` (hit stop), `AudioBus`, `Game` (score, match state).
- An autoload holds global services only. It never holds per-unit state.
- Never give an autoload script a `class_name` that equals its autoload name. The name clashes.
- Autoloads never call into scenes by path. Scenes call autoloads.
- Reset autoload state in a `reset()` function when a match restarts. `change_scene_to_file` keeps autoloads alive.

## 5. Input for mobile multitouch

Source: https://docs.godotengine.org/en/4.6/classes/class_inputeventscreentouch.html
Source: https://docs.godotengine.org/en/4.6/tutorials/inputs/input_examples.html

- `InputEventScreenTouch.index` is the finger id. One index equals one finger.
- `InputEventScreenDrag.index` matches the touch that started the drag.
- Rule: one finger per control. Each control stores its own `_finger_index`, default `-1`.
- Claim a finger on `pressed` only when the control is free and the touch lands in its rect.
- Ignore every `ScreenDrag` and release whose index differs from the stored one.
- Release on `pressed == false` for the stored index. Also release on `NOTIFICATION_APPLICATION_FOCUS_OUT`. The browser can drop the release event when the tab hides.
- Handle events in `_input`, not `_gui_input`. A drag that leaves the control rect must still reach it.
- Call `get_viewport().set_input_as_handled()` after a claim so a second control never claims the same finger.
- Split the screen: left half joystick, right half throw. Never overlap the two rects.
- Test touch on desktop: enable "Emulate Touch From Mouse" in Project Settings, Input Devices, Pointing.
  Source: https://docs.godotengine.org/en/4.6/tutorials/inputs/input_examples.html
- Keep a keyboard fallback (`Input.get_vector`) so desktop players can move. Define actions `move_left`, `move_right`, `move_up`, `move_down`.
- Emulated mouse events from touch can double-fire if you handle both touch and mouse. Handle touch only in the controls. Unconfirmed: exact default of the emulate-mouse-from-touch setting.
- Positions in `_input` are viewport coordinates. The examples assume no `Camera2D` transform on the UI. Put UI under a `CanvasLayer`.

## 6. Virtual joystick and drag-to-throw

### 6.1 Floating joystick

The stick appears where the left thumb lands. It outputs a vector of length 0 to 1.

File: `scripts/ui/virtual_joystick.gd`

```gdscript
class_name VirtualJoystick
extends Control
## Floating on-screen joystick that claims one finger.
##
## Size this [Control] to the left half of the screen. The stick appears
## where the thumb lands and outputs [member direction] with length 0 to 1.

## Emitted when [member direction] changes. Length is 0 to 1.
signal direction_changed(direction: Vector2)

## Color of the outer ring.
const BASE_COLOR: Color = Color(1.0, 1.0, 1.0, 0.25)
## Color of the knob.
const KNOB_COLOR: Color = Color(1.0, 1.0, 1.0, 0.6)
## Knob radius in pixels.
const KNOB_RADIUS: float = 36.0
## Value of [member _finger_index] when no finger is claimed.
const NO_FINGER: int = -1

## Maximum knob travel in pixels.
@export var radius: float = 90.0
## Fraction of [member radius] near the center that outputs zero.
@export_range(0.0, 0.5, 0.01) var dead_zone: float = 0.15

## Current stick output. Length is 0 to 1.
var direction: Vector2 = Vector2.ZERO

var _finger_index: int = NO_FINGER
var _origin: Vector2 = Vector2.ZERO
var _knob_offset: Vector2 = Vector2.ZERO


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event as InputEventScreenTouch
		if touch.pressed:
			_try_claim(touch)
		elif touch.index == _finger_index:
			_release()
	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event as InputEventScreenDrag
		if drag.index == _finger_index:
			_move_knob(drag.position)
			get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _finger_index != NO_FINGER:
		_release()


func _draw() -> void:
	if _finger_index == NO_FINGER:
		return
	var local_origin: Vector2 = _origin - global_position
	draw_circle(local_origin, radius, BASE_COLOR)
	draw_circle(local_origin + _knob_offset, KNOB_RADIUS, KNOB_COLOR)


func _try_claim(touch: InputEventScreenTouch) -> void:
	if _finger_index != NO_FINGER:
		return
	if not get_global_rect().has_point(touch.position):
		return
	_finger_index = touch.index
	_origin = touch.position
	_move_knob(touch.position)
	get_viewport().set_input_as_handled()


func _move_knob(finger_position: Vector2) -> void:
	_knob_offset = (finger_position - _origin).limit_length(radius)
	var strength: float = _knob_offset.length() / radius
	var next_direction: Vector2 = Vector2.ZERO
	if strength >= dead_zone:
		var scaled: float = remap(strength, dead_zone, 1.0, 0.0, 1.0)
		next_direction = _knob_offset.normalized() * scaled
	_set_direction(next_direction)
	queue_redraw()


func _release() -> void:
	_finger_index = NO_FINGER
	_knob_offset = Vector2.ZERO
	_set_direction(Vector2.ZERO)
	queue_redraw()


func _set_direction(next_direction: Vector2) -> void:
	if next_direction == direction:
		return
	direction = next_direction
	direction_changed.emit(direction)
```

### 6.2 Slingshot drag-to-throw

The right thumb presses, pulls back, and releases. The throw goes opposite the pull. Power is pull length over `max_pull`.

File: `scripts/ui/throw_control.gd`

```gdscript
class_name ThrowControl
extends Control
## Slingshot control on the right half of the screen.
##
## Press to anchor, drag back to aim, release to throw opposite the pull.
## Releasing a pull shorter than [member min_pull] cancels the throw.

## Emitted while dragging. [param power] is 0 to 1.
signal aim_changed(direction: Vector2, power: float)
## Emitted on release of a valid pull. [param power] is 0 to 1.
signal thrown(direction: Vector2, power: float)
## Emitted when a pull ends without a throw.
signal aim_cancelled

## Color of the pull line.
const LINE_COLOR: Color = Color(1.0, 0.85, 0.3, 0.8)
## Width of the pull line in pixels.
const LINE_WIDTH: float = 6.0
## Value of [member _finger_index] when no finger is claimed.
const NO_FINGER: int = -1

## Pull length in pixels that gives full power.
@export var max_pull: float = 160.0
## Pull length in pixels below which a release cancels the throw.
@export var min_pull: float = 24.0

var _finger_index: int = NO_FINGER
var _anchor: Vector2 = Vector2.ZERO
var _pull: Vector2 = Vector2.ZERO


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event as InputEventScreenTouch
		if touch.pressed:
			_try_claim(touch)
		elif touch.index == _finger_index:
			_finish()
	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event as InputEventScreenDrag
		if drag.index == _finger_index:
			_update_pull(drag.position)
			get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _finger_index != NO_FINGER:
		_reset()
		aim_cancelled.emit()


func _draw() -> void:
	if _finger_index == NO_FINGER:
		return
	var local_anchor: Vector2 = _anchor - global_position
	draw_line(local_anchor, local_anchor + _pull, LINE_COLOR, LINE_WIDTH)
	draw_circle(local_anchor + _pull, LINE_WIDTH, LINE_COLOR)


func _try_claim(touch: InputEventScreenTouch) -> void:
	if _finger_index != NO_FINGER:
		return
	if not get_global_rect().has_point(touch.position):
		return
	_finger_index = touch.index
	_anchor = touch.position
	_pull = Vector2.ZERO
	get_viewport().set_input_as_handled()


func _update_pull(finger_position: Vector2) -> void:
	_pull = (finger_position - _anchor).limit_length(max_pull)
	aim_changed.emit(_throw_direction(), _power())
	queue_redraw()


func _finish() -> void:
	var valid: bool = _pull.length() >= min_pull
	var direction: Vector2 = _throw_direction()
	var power: float = _power()
	_reset()
	if valid:
		thrown.emit(direction, power)
	else:
		aim_cancelled.emit()


func _reset() -> void:
	_finger_index = NO_FINGER
	_pull = Vector2.ZERO
	queue_redraw()


func _throw_direction() -> Vector2:
	return -_pull.normalized()


func _power() -> float:
	return clampf(_pull.length() / max_pull, 0.0, 1.0)
```

Wire both in the arena. Never let the controls know the player.

File: `scripts/arena/arena.gd`

```gdscript
class_name Arena
extends Node2D
## Wires input controls to the player and spawns sandals.

## Scene spawned for every throw.
@export var sandal_scene: PackedScene
## Left-half movement control.
@export var joystick: VirtualJoystick
## Right-half throw control.
@export var throw_control: ThrowControl
## Human-controlled unit.
@export var player: Player
## Parent node for spawned sandals.
@export var projectiles: Node2D


func _ready() -> void:
	joystick.direction_changed.connect(player.set_move_input)
	throw_control.thrown.connect(player.throw)
	player.sandal_thrown.connect(_on_sandal_thrown)
	for node: Node in get_tree().get_nodes_in_group(&"brawlers"):
		if node is Bot:
			(node as Bot).sandal_thrown.connect(_on_sandal_thrown)


func _on_sandal_thrown(origin: Vector2, direction: Vector2, power: float, team: int) -> void:
	var sandal: Sandal = sandal_scene.instantiate() as Sandal
	projectiles.add_child(sandal)
	sandal.global_position = origin
	sandal.launch(direction, power, team)
```

## 7. Physics for the thrown sandal

Decision: use a manual kinematic arc on an `Area2D`. Never use `RigidBody2D` for the thrown sandal.

Why:
- Top-down has no real gravity. A `RigidBody2D` needs `gravity_scale = 0` plus `linear_damp` to fake a stop.
  Source: https://docs.godotengine.org/en/4.6/classes/class_rigidbody2d.html
- A rigid body flight is hard to tune. Range depends on damp, mass, and impulse together.
- A fast rigid body can tunnel through thin walls. The manual arc checks overlaps every physics frame.
- Manual motion gives exact range: `range = max_speed * power * flight_time`. One number per feel goal.
- The fake height (a visual offset) gives the "lob" look. Hits only count below `hit_height`. Players can duck under high lobs by timing.
- Cost is one `Area2D` and a few lines per sandal. This is cheap for single-thread web.

Use `RigidBody2D` only for decor that reacts to hits, such as a bouncing crate. Unconfirmed: web physics cost at 50+ bodies.

File: `scripts/units/sandal.gd`

```gdscript
class_name Sandal
extends Area2D
## Thrown sandal with a manual top-down arc.
##
## Moves in a straight line. A fake height drives the visual lob and
## decides when the sandal can hit. Needs child nodes [code]Visual[/code]
## ([Node2D]) and a collision shape.

## Emitted when the sandal ends, by landing or by hitting something.
signal landed(landing_position: Vector2)

## Tuning resource for flight and hit values.
@export var tuning: ThrowTuning

## Team of the thrower. Sandals never hit this team.
var team: int = -1

var _velocity: Vector2 = Vector2.ZERO
var _elapsed: float = 0.0

@onready var _visual: Node2D = $Visual


func _ready() -> void:
	add_to_group(&"sandals")


func _physics_process(delta: float) -> void:
	_elapsed += delta
	var progress: float = clampf(_elapsed / tuning.flight_time, 0.0, 1.0)
	var height: float = sin(progress * PI) * tuning.arc_height
	_visual.position.y = -height
	position += _velocity * delta
	if height <= tuning.hit_height and _hit_something():
		_finish()
		return
	if progress >= 1.0:
		_finish()


## Starts the flight from the current position.
## [param direction] must be a unit vector. [param power] is 0 to 1.
func launch(direction: Vector2, power: float, thrower_team: int) -> void:
	team = thrower_team
	_velocity = direction * tuning.max_speed * power
	_visual.rotation = direction.angle()


func _hit_something() -> bool:
	for body: Node2D in get_overlapping_bodies():
		if body is StaticBody2D:
			return true
		if not body.has_method(&"take_hit"):
			continue
		if body.get(&"team") == team:
			continue
		body.call(&"take_hit", _velocity.normalized() * tuning.knockback)
		return true
	return false


func _finish() -> void:
	landed.emit(global_position)
	queue_free()
```

Add a `Visual` child (`Sprite2D` or `Node2D` with a sprite) and a shadow sprite that stays at height 0. The shadow sells the arc.

## 8. Simple state-machine AI for bots

Source: https://docs.godotengine.org/en/4.6/tutorials/navigation/navigation_using_navigationagents.html

NavigationAgent2D rules:
- The agent never moves its parent. Your script moves the body.
- Call `get_next_path_position()` once per `_physics_process` while the path runs.
- Check `is_navigation_finished()` first. Never call `get_next_path_position()` after the path ends. The bot jitters.
- Never call path functions inside agent signal handlers. Source: https://docs.godotengine.org/en/4.6/classes/class_navigationagent2d.html
- Set `target_position` on a timer (about every 0.3 s), not every frame.
- The arena needs a `NavigationRegion2D` with a baked polygon. Unconfirmed: bake steps in 4.6 for this project.

States: `CHASE` (close to throw range), `AIM` (stop, wait reaction time), `EVADE` (sidestep an incoming sandal). A throw ends `AIM` and returns to `CHASE`.

File: `scripts/units/bot.gd`

```gdscript
class_name Bot
extends CharacterBody2D
## Bot with a three-state brain: chase, aim, evade.
##
## Needs a child [NavigationAgent2D]. Throws are emitted as a signal so the
## arena spawns the sandal. Add the node to group [code]brawlers[/code].

## Emitted when the bot throws. Same shape as [signal Player.sandal_thrown].
signal sandal_thrown(origin: Vector2, direction: Vector2, power: float, team: int)

## Bot behavior states.
enum State { CHASE, AIM, EVADE }

## Team id. Bots never target the same team.
@export var team: int = 1
## Movement values shared with the player.
@export var move_tuning: MoveTuning
## Throw values shared with the player.
@export var throw_tuning: ThrowTuning
## Bot-only AI values.
@export var bot_tuning: BotTuning

## Current state. Read-only outside this script.
var state: State = State.CHASE

var _target: Node2D
var _threat: Node2D
var _state_time_left: float = 0.0
var _repath_left: float = 0.0
var _cooldown_left: float = 0.0
var _evade_direction: Vector2 = Vector2.ZERO

@onready var _agent: NavigationAgent2D = $NavigationAgent2D


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	add_to_group(&"brawlers")


func _physics_process(delta: float) -> void:
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	_state_time_left -= delta
	_repath_left -= delta
	if _repath_left <= 0.0:
		_repath_left = bot_tuning.repath_interval
		_target = _find_target()
		if _target != null:
			_agent.target_position = _target.global_position
	if _target == null:
		_accelerate(Vector2.ZERO, delta)
	else:
		match state:
			State.CHASE:
				_tick_chase(delta)
			State.AIM:
				_tick_aim(delta)
			State.EVADE:
				_tick_evade(delta)
	move_and_slide()


## Applies a hit. [param knockback] is added to the velocity.
func take_hit(knockback: Vector2) -> void:
	velocity += knockback


func _tick_chase(delta: float) -> void:
	_threat = _find_threat()
	if _threat != null:
		_enter(State.EVADE)
		return
	var distance: float = global_position.distance_to(_target.global_position)
	if distance <= bot_tuning.throw_range and _cooldown_left <= 0.0:
		_enter(State.AIM)
		return
	if _agent.is_navigation_finished():
		_accelerate(Vector2.ZERO, delta)
		return
	var next_position: Vector2 = _agent.get_next_path_position()
	var heading: Vector2 = global_position.direction_to(next_position)
	_accelerate(heading * move_tuning.max_speed, delta)


func _tick_aim(delta: float) -> void:
	_accelerate(Vector2.ZERO, delta)
	if _state_time_left > 0.0:
		return
	_throw_at_target()
	_enter(State.CHASE)


func _tick_evade(delta: float) -> void:
	_accelerate(_evade_direction * move_tuning.max_speed, delta)
	if _state_time_left <= 0.0:
		_enter(State.CHASE)


func _enter(next_state: State) -> void:
	state = next_state
	match next_state:
		State.AIM:
			_state_time_left = bot_tuning.reaction_time
		State.EVADE:
			_state_time_left = bot_tuning.evade_time
			var away: Vector2 = _threat.global_position.direction_to(global_position)
			var side: float = 1.0 if randf() < 0.5 else -1.0
			_evade_direction = (away + away.orthogonal() * side).normalized()
		State.CHASE:
			_state_time_left = 0.0


func _throw_at_target() -> void:
	var to_target: Vector2 = _target.global_position - global_position
	var error: float = deg_to_rad(randf_range(-bot_tuning.aim_error_degrees, bot_tuning.aim_error_degrees))
	var direction: Vector2 = to_target.normalized().rotated(error)
	var full_range: float = throw_tuning.max_speed * throw_tuning.flight_time
	var power: float = clampf(to_target.length() / full_range, 0.2, 1.0)
	_cooldown_left = throw_tuning.cooldown
	sandal_thrown.emit(global_position, direction, power, team)


func _accelerate(desired_velocity: Vector2, delta: float) -> void:
	velocity = velocity.move_toward(desired_velocity, move_tuning.acceleration * delta)


func _find_target() -> Node2D:
	var best: Node2D = null
	var best_distance: float = INF
	for node: Node in get_tree().get_nodes_in_group(&"brawlers"):
		var other: Node2D = node as Node2D
		if other == null or other.get(&"team") == team:
			continue
		var distance: float = global_position.distance_squared_to(other.global_position)
		if distance < best_distance:
			best_distance = distance
			best = other
	return best


func _find_threat() -> Node2D:
	for node: Node in get_tree().get_nodes_in_group(&"sandals"):
		var sandal: Node2D = node as Node2D
		if sandal == null or sandal.get(&"team") == team:
			continue
		if global_position.distance_to(sandal.global_position) <= bot_tuning.dodge_radius:
			return sandal
	return null
```

Tuning tips:
- Raise `reaction_time` and `aim_error_degrees` for easy bots. Lower them for hard bots.
- Raise `dodge_radius` for hard bots. A bot that dodges everything is not fun, so add a dodge chance if needed.
- Three or four bots at 0.3 s repath is cheap. Unconfirmed: web cost at 10+ agents.

## 9. Data-driven tuning with Resources

Create one `Resource` script per tuning group. Save `.tres` files in `resources/tuning/`. Assign them in the inspector. Edit values in the inspector with no code change.

File: `scripts/tuning/move_tuning.gd`

```gdscript
class_name MoveTuning
extends Resource
## Movement values for a top-down unit.

## Top speed in pixels per second.
@export_range(50.0, 800.0, 5.0, "suffix:px/s") var max_speed: float = 260.0
## Acceleration in pixels per second squared. Also decays knockback.
@export_range(100.0, 8000.0, 50.0, "suffix:px/s2") var acceleration: float = 2400.0
```

File: `scripts/tuning/throw_tuning.gd`

```gdscript
class_name ThrowTuning
extends Resource
## Flight and hit values for a thrown sandal.

## Launch speed at full power in pixels per second.
@export_range(100.0, 1500.0, 10.0, "suffix:px/s") var max_speed: float = 700.0
## Time from launch to landing in seconds.
@export_range(0.2, 3.0, 0.05, "suffix:s") var flight_time: float = 0.8
## Peak visual height in pixels.
@export_range(0.0, 200.0, 1.0, "suffix:px") var arc_height: float = 60.0
## Sandal hits only while its height is at or below this value.
@export_range(0.0, 200.0, 1.0, "suffix:px") var hit_height: float = 40.0
## Knockback speed added on hit in pixels per second.
@export_range(0.0, 2000.0, 10.0, "suffix:px/s") var knockback: float = 450.0
## Seconds between throws.
@export_range(0.1, 5.0, 0.05, "suffix:s") var cooldown: float = 0.9
```

File: `scripts/tuning/bot_tuning.gd`

```gdscript
class_name BotTuning
extends Resource
## AI values for a bot. Make one resource per difficulty.

## Distance in pixels at which the bot starts to aim.
@export_range(100.0, 1200.0, 10.0, "suffix:px") var throw_range: float = 420.0
## Seconds the bot stands still before it throws.
@export_range(0.0, 2.0, 0.05, "suffix:s") var reaction_time: float = 0.45
## Maximum aim miss in degrees, either side.
@export_range(0.0, 45.0, 0.5, "suffix:deg") var aim_error_degrees: float = 12.0
## Distance in pixels at which an enemy sandal triggers a dodge.
@export_range(0.0, 600.0, 10.0, "suffix:px") var dodge_radius: float = 160.0
## Seconds spent sidestepping.
@export_range(0.1, 2.0, 0.05, "suffix:s") var evade_time: float = 0.35
## Seconds between target and path refreshes.
@export_range(0.05, 1.0, 0.05, "suffix:s") var repath_interval: float = 0.3
```

Player, the unit the joystick drives:

File: `scripts/units/player.gd`

```gdscript
class_name Player
extends CharacterBody2D
## Human-controlled unit. Moves with the joystick and throws on request.

## Emitted when the player throws a sandal.
signal sandal_thrown(origin: Vector2, direction: Vector2, power: float, team: int)

## Team id. Sandals never hit this team.
@export var team: int = 0
## Movement values.
@export var move_tuning: MoveTuning
## Throw values.
@export var throw_tuning: ThrowTuning

var _move_input: Vector2 = Vector2.ZERO
var _cooldown_left: float = 0.0


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	add_to_group(&"brawlers")


func _physics_process(delta: float) -> void:
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	var keyboard: Vector2 = Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	var input: Vector2 = _move_input if _move_input != Vector2.ZERO else keyboard
	velocity = velocity.move_toward(input * move_tuning.max_speed, move_tuning.acceleration * delta)
	move_and_slide()


## Stores the joystick vector. Connect to [signal VirtualJoystick.direction_changed].
func set_move_input(direction: Vector2) -> void:
	_move_input = direction


## Throws a sandal unless the cooldown runs. Connect to [signal ThrowControl.thrown].
func throw(direction: Vector2, power: float) -> void:
	if _cooldown_left > 0.0:
		return
	_cooldown_left = throw_tuning.cooldown
	sandal_thrown.emit(global_position, direction, power, team)


## Applies a hit. [param knockback] is added to the velocity.
func take_hit(knockback: Vector2) -> void:
	velocity += knockback
```

Notes:
- `move_and_slide()` includes the timestep. Never multiply `velocity` by `delta`.
  Source: https://docs.godotengine.org/en/4.6/tutorials/physics/using_character_body_2d.html
- `MOTION_MODE_FLOATING` is the top-down mode. Source: same URL.
- Edit a running game: Remote tab in the scene dock changes node values live. Unconfirmed: live edits of shared Resource files.
- A `.tres` edited on disk while the game runs does not reload. Restart the run. Unconfirmed.
- Keep a debug panel with `HSlider` nodes bound to the resources for phone tuning.

## 10. Game feel

### Hit stop

File: `autoload/game_feel.gd`. Register as autoload `GameFeel`.

```gdscript
extends Node
## Autoload. Freezes time for a few frames to sell a hit.

## Default freeze length in real seconds.
const DEFAULT_DURATION: float = 0.06
## Default time scale during the freeze.
const DEFAULT_TIME_SCALE: float = 0.05

var _active: bool = false


## Slows the game for [param duration] real seconds. Overlapping calls are ignored.
func hit_stop(duration: float = DEFAULT_DURATION, time_scale: float = DEFAULT_TIME_SCALE) -> void:
	if _active:
		return
	_active = true
	Engine.time_scale = time_scale
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1.0
	_active = false
```

The fourth argument of `create_timer` ignores time scale. Without it the timer never ends. Unconfirmed: argument order in 4.6, check `SceneTree.create_timer` in the class ref.

### Screen shake

File: `scripts/arena/camera_shake.gd`

```gdscript
class_name CameraShake
extends Camera2D
## Camera with trauma-based shake. Call [method add_trauma] on a hit.

## Maximum offset in pixels at full trauma.
@export var max_offset: float = 18.0
## Trauma lost per second.
@export var decay: float = 2.5

var _trauma: float = 0.0


func _process(delta: float) -> void:
	_trauma = maxf(_trauma - decay * delta, 0.0)
	var shake: float = _trauma * _trauma
	offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * max_offset * shake


## Adds shake. [param amount] is 0 to 1. Total trauma caps at 1.
func add_trauma(amount: float) -> void:
	_trauma = minf(_trauma + amount, 1.0)
```

### Squash

File: `scripts/fx/squash.gd`

```gdscript
class_name Squash
extends RefCounted
## Static helper for a squash-and-stretch punch.


## Snaps [param target] flat and springs it back to normal scale.
static func punch(target: Node2D, amount: float = 0.3, duration: float = 0.2) -> void:
	target.scale = Vector2(1.0 + amount, 1.0 - amount)
	var tween: Tween = target.create_tween()
	tween.tween_property(target, "scale", Vector2.ONE, duration) \
			.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
```

Typical hit: `GameFeel.hit_stop()`, `camera.add_trauma(0.4)`, `Squash.punch(victim_sprite)`.
Add a 1-frame white flash by setting `modulate` above 1.0 in `gl_compatibility`. Unconfirmed: HDR modulate look on web.

## 11. Web export gotchas

| Topic | Rule | Source |
|---|---|---|
| Threads | Export with Thread Support off. It is the default since 4.3 and works with web publishers. | https://docs.godotengine.org/en/4.6/tutorials/export/exporting_for_web.html |
| Threads on | Needs COOP and COEP headers and a secure context. The project never runs without them. | same |
| Thread API | No `Thread` use in single-thread export. Never call `WorkerThreadPool` for gameplay. | same |
| Audio autoplay | Browsers block audio until a user gesture. Show a tap-to-start screen. | same |
| Audio playback | Web export plays audio as samples by default since 4.3. Bus effects are not implemented for samples. | same |
| Renderer | `gl_compatibility` uses WebGL 2.0 on web. | https://docs.godotengine.org/en/4.6/tutorials/performance/pipeline_compilations.html |
| Shader stutter | Preload by showing each material, shader, and particle for one frame at load. No ubershaders in Compatibility. | same |
| Fullscreen | Browsers need a user gesture. Call it from an input handler. Unconfirmed in docs. | none |
| OS calls | `OS.execute` and `OS.create_process` do not work in a browser. Unconfirmed in docs. | none |
| Saving | Use `user://` files or `JavaScriptBridge` localStorage. Unconfirmed: persistence on GamePix. | none |
| File size | Keep the `.wasm` and `.pck` small. Unconfirmed: GamePix size limit. Check the GamePix rules page. | none |
| Mobile Safari | Test on a real iPhone. Single-thread export is the reliable path on iOS. | exporting_for_web.html |

Tap-to-start gate. It unlocks audio, requests fullscreen, then loads the first scene.

File: `scripts/ui/tap_to_start.gd`

```gdscript
class_name TapToStart
extends Control
## First screen. Waits for a user gesture, then unlocks audio and goes fullscreen.

## Scene loaded after the first gesture.
@export_file("*.tscn") var next_scene: String

var _started: bool = false


func _input(event: InputEvent) -> void:
	if _started:
		return
	var is_gesture: bool = event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed
	is_gesture = is_gesture or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed)
	is_gesture = is_gesture or (event is InputEventKey and (event as InputEventKey).pressed)
	if not is_gesture:
		return
	_started = true
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	get_tree().change_scene_to_file(next_scene)
```

Play a short silent or UI sound in the first gesture too. Check that audio starts on iOS. Unconfirmed: whether Godot resumes the audio context on its own.

### Performance on web

Source: https://docs.godotengine.org/en/4.6/tutorials/performance/gpu_optimization.html

- 2D batches similar items into one draw call. Share one atlas texture and one material across sprites.
- Never give each sprite its own `ShaderMaterial` instance. It breaks the batch.
- Avoid heavy fragment shaders on full-screen rects. Mobile GPUs are slow at fill rate.
- Keep particles few. Prefer `CPUParticles2D` with low counts. Unconfirmed: web speed versus `GPUParticles2D`.
- Keep the arena small. Cull off-screen nodes by not spawning them.
- Preload all scenes at the start. Never `load()` inside gameplay.
- Check draw calls: `RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)` after two frames.
  Source: https://docs.godotengine.org/en/4.6/classes/class_renderingserver.html
- Use compressed audio (Ogg Vorbis) and short samples.
- Set `display/window/stretch/mode` to `canvas_items` and aspect to `expand` or `keep`. Unconfirmed: best choice for GamePix.

## 12. Debug on a phone over LAN

1. Export for Web into `build/web/`. Keep Thread Support off.
2. Serve the folder: `python3 -m http.server 8060 --bind 0.0.0.0 --directory build/web`.
3. Find the PC LAN address: `ip -4 addr show | grep inet`.
4. Open `http://<lan-ip>:8060/index.html` on the phone. Both devices must share the Wi-Fi.
5. Allow port 8060 in the PC firewall if the page does not load.
6. Android: enable USB debugging, open `chrome://inspect` on the PC for console and profiler. Unconfirmed: needs adb.
7. iOS: Safari, Develop menu on a Mac. Unconfirmed: no Mac in the project.
8. Add an on-screen label with FPS: `Engine.get_frames_per_second()`. Toggle it with a 3-finger tap.
9. Clear the browser cache when the build looks stale. Serve with `Cache-Control: no-store` if needed.
10. Single-thread export needs no secure context, so plain `http` works. Unconfirmed: check on the target phone.

## 13. Common 4.x mistakes

| Mistake | Fix |
|---|---|
| `yield(...)` | Use `await`. |
| `export var x` | Use `@export var x`. |
| `onready var n = $N` | Use `@onready var n: Node = $N`. |
| `connect("sig", self, "fn")` | Use `sig.connect(fn)`. |
| `move_and_slide(velocity)` | Set `velocity`, call `move_and_slide()`, never multiply by `delta`. |
| Untyped `var x = ...` | Type every var. The style skill requires it. |
| `Input.is_action_pressed` for touch | Handle `InputEventScreenTouch` and `InputEventScreenDrag` events. |
| Control eats touches | Set `mouse_filter` to `MOUSE_FILTER_IGNORE` on decor controls. |
| Sharing one finger | Store the finger index per control. |
| Setting `position` on a `RigidBody2D` | Use forces, impulses, or `_integrate_forces`. |
| Calling `queue_free()` then reading the node | Check `is_instance_valid(node)`. |
| Mutating physics inside a signal | Use `call_deferred`. |
| `get_node` in `_init` | Use `@onready` or `_ready`. |
| Editing a shared Resource at runtime | It changes every user. Call `duplicate()` first. |
| Bumping `Engine.time_scale` and never resetting | Reset in the same function. Guard re-entry. |
| `change_scene_to_file` in a physics callback | Use `call_deferred`. |
| Tweens on freed nodes | Create tweens with `node.create_tween()` so they bind to the node. |
| Untested on a phone | Test on a real device every 4 hours. |

Check each function name against the 4.6 class reference before use: https://docs.godotengine.org/en/4.6/classes/
