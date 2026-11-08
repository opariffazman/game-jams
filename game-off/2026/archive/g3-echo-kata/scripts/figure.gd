class_name Figure
extends RefCounted
## A stick-figure silhouette: hero, ghost or dummy, drawn from line endpoints.

## Number of trail samples kept, one per tick.
const TRAIL_LEN: int = 28

## Body center in world space.
var pos: Vector2 = Vector2.ZERO
## 1.0 faces right, -1.0 faces left.
var facing: float = 1.0
## Strike pose weight, 1.0 right after a strike and decays to 0.0.
var strike_time: float = 0.0
## Trail of past tick positions.
var trail: PackedVector2Array = PackedVector2Array()
var color: Color
var marks: int
var dotted: bool
var ghost: bool
var _run_phase: float = 0.0
var _speed: float = 0.0
var _last_sample: Vector2 = Vector2.ZERO


func _init(p_color: Color, p_marks: int, p_dotted: bool, p_ghost: bool) -> void:
	color = p_color
	marks = p_marks
	dotted = p_dotted
	ghost = p_ghost


## Put the figure at [param p] and forget its trail.
func reset(p: Vector2) -> void:
	pos = p
	_last_sample = p
	_speed = 0.0
	trail.clear()
	strike_time = 0.0


## Move the figure to [param p] and turn toward the move.
func move_to(p: Vector2) -> void:
	if absf(p.x - pos.x) > 0.4:
		facing = signf(p.x - pos.x)
	pos = p


## Record one tick of trail and run-cycle state.
func sample() -> void:
	var step: float = pos.distance_to(_last_sample)
	_run_phase += step * 0.35
	_speed = lerpf(_speed, step, 0.3)
	_last_sample = pos
	trail.append(pos)
	if trail.size() > TRAIL_LEN:
		trail.remove_at(0)


## Start the strike pose.
func strike() -> void:
	strike_time = 1.0


## Advance the strike pose decay by [param delta] seconds.
func animate(delta: float) -> void:
	strike_time = maxf(0.0, strike_time - delta * 6.0)


## Draw trail, body and track marks onto [param canvas].
func draw(canvas: CanvasItem) -> void:
	_draw_trail(canvas)
	var swing: float = sin(_run_phase) * 8.0 * clampf(_speed / 2.0, 0.0, 1.0)
	var width: float = 3.0 if ghost else 4.0
	Figure.draw_pose(canvas, pos, color, width, facing, swing, strike_time, 0.0, not ghost)
	for i: int in marks:
		var dot: Vector2 = pos + Vector2((i - (marks - 1) * 0.5) * 10.0, -52.0)
		canvas.draw_circle(dot, 2.5, color)


## Draw one pose. [param fall] runs 0.0 to 1.0 and tips the body over toward [param facing].
static func draw_pose(canvas: CanvasItem, p: Vector2, color: Color, width: float, facing: float,
		swing: float, strike: float, fall: float, filled: bool) -> void:
	var hand_r: Vector2 = Vector2(12.0 * facing + swing, -8.0)
	var hand_l: Vector2 = Vector2(-12.0 * facing - swing, -8.0)
	if strike > 0.0:
		hand_r = Vector2(facing * (14.0 + 24.0 * strike), -18.0)
		hand_l = Vector2(-facing * 10.0, -10.0)
	var pivot: Vector2 = Vector2(0.0, 20.0)
	var angle: float = fall * PI * 0.5 * facing
	var hop: Vector2 = Vector2(0.0, -10.0 * sin(PI * fall))
	var head: Vector2 = _tip(Vector2(0.0, -30.0), pivot, angle, p + hop)
	var neck: Vector2 = _tip(Vector2(0.0, -22.0), pivot, angle, p + hop)
	var shoulder: Vector2 = _tip(Vector2(0.0, -18.0), pivot, angle, p + hop)
	var hip: Vector2 = _tip(Vector2.ZERO, pivot, angle, p + hop)
	var foot_l: Vector2 = _tip(Vector2(-7.0 - swing, 20.0 - maxf(0.0, swing) * 0.3), pivot, angle, p + hop)
	var foot_r: Vector2 = _tip(Vector2(7.0 + swing, 20.0 - maxf(0.0, -swing) * 0.3), pivot, angle, p + hop)
	canvas.draw_line(neck, hip, color, width, true)
	canvas.draw_line(shoulder, _tip(hand_r, pivot, angle, p + hop), color, width, true)
	canvas.draw_line(shoulder, _tip(hand_l, pivot, angle, p + hop), color, width, true)
	canvas.draw_line(hip, foot_l, color, width, true)
	canvas.draw_line(hip, foot_r, color, width, true)
	if filled:
		canvas.draw_circle(head, 8.0, color)
	else:
		canvas.draw_arc(head, 7.0, 0.0, TAU, 20, color, 2.5, true)


static func _tip(local: Vector2, pivot: Vector2, angle: float, origin: Vector2) -> Vector2:
	return origin + pivot + (local - pivot).rotated(angle)


func _draw_trail(canvas: CanvasItem) -> void:
	var count: int = trail.size()
	for i: int in range(1, count):
		var fade: float = float(i) / count
		var tint: Color = Color(color, fade * 0.55)
		if dotted:
			if i % 3 == 0:
				canvas.draw_circle(trail[i], 2.5, tint)
		else:
			canvas.draw_line(trail[i - 1], trail[i], tint, 2.5, true)
