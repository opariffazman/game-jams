class_name Stage
extends Node2D
## Top half: the stick-figure hero, the dummy enemy, smear arcs, bullet trail and particles.

## Hero poses. Lane poses follow [enum Kata.Lane] plus one.
enum Pose { IDLE, PUNCH, KICK, SHOOT, STUMBLE, FINISHER }

## Hero hip position at rest.
const HERO_HIP: Vector2 = Vector2(150, 255)
## Dummy feet position.
const DUMMY_FEET: Vector2 = Vector2(300, 307)
const HOLD_TIMES: PackedFloat32Array = [0.0, 0.1, 0.12, 0.1, 0.3, 0.3]
const LIFTS: PackedFloat32Array = [0.0, 0.0, 0.0, 0.0, 0.0, -24.0]
const RETURN_TIME: float = 0.12
const SMEAR_TIME: float = 0.16
const DUMMY_TIME: float = 0.32

## Points per pose, hip is the origin: head, neck, l_elbow, l_hand, r_elbow, r_hand, l_knee, l_foot, r_knee, r_foot.
static var poses: Array[PackedVector2Array] = [
	PackedVector2Array([Vector2(2, -68), Vector2(0, -50), Vector2(4, -34), Vector2(18, -46), Vector2(14, -32), Vector2(28, -44), Vector2(-12, 26), Vector2(-22, 52), Vector2(16, 24), Vector2(30, 52)]),
	PackedVector2Array([Vector2(16, -64), Vector2(8, -48), Vector2(4, -38), Vector2(14, -46), Vector2(34, -46), Vector2(70, -48), Vector2(-18, 24), Vector2(-34, 52), Vector2(22, 22), Vector2(38, 52)]),
	PackedVector2Array([Vector2(-14, -66), Vector2(-8, -49), Vector2(-22, -40), Vector2(-36, -30), Vector2(-4, -34), Vector2(-18, -22), Vector2(-6, 26), Vector2(-8, 54), Vector2(32, -8), Vector2(70, -14)]),
	PackedVector2Array([Vector2(10, -66), Vector2(4, -49), Vector2(24, -42), Vector2(46, -50), Vector2(30, -48), Vector2(54, -52), Vector2(-12, 24), Vector2(-26, 52), Vector2(14, 26), Vector2(26, 52)]),
	PackedVector2Array([Vector2(-20, -58), Vector2(-12, -46), Vector2(-30, -60), Vector2(-44, -78), Vector2(-2, -62), Vector2(-14, -84), Vector2(-14, 24), Vector2(-28, 50), Vector2(8, 28), Vector2(12, 54)]),
	PackedVector2Array([Vector2(20, -60), Vector2(12, -44), Vector2(-18, -52), Vector2(-44, -60), Vector2(44, -48), Vector2(80, -52), Vector2(-18, 16), Vector2(-40, 38), Vector2(36, -4), Vector2(78, -26)]),
]

## Song time in beats. Drives the idle bob.
var beat_phase: float = 0.0

var _pose: int = Pose.IDLE
var _pose_time: float = 10.0
var _smear: float = 0.0
var _dummy_t: float = 0.0
var _dummy_big: bool = false
var _small_burst: CPUParticles2D
var _big_burst: CPUParticles2D


func _ready() -> void:
	_small_burst = _make_burst(14, 220.0, 5.0)
	_big_burst = _make_burst(40, 340.0, 6.0)


## Plays the pose for [param lane] at once. A finisher swaps in the big pose.
func perform(lane: int, finisher: bool) -> void:
	_pose = Pose.FINISHER if finisher else lane + 1
	_pose_time = 0.0
	_smear = SMEAR_TIME
	_dummy_t = DUMMY_TIME
	_dummy_big = finisher
	var burst: CPUParticles2D = _big_burst if finisher else _small_burst
	burst.color = Kata.AMBER if finisher else Kata.lane_colors[lane]
	burst.restart()
	queue_redraw()


## Makes the hero stumble. Called on a miss.
func stumble() -> void:
	_pose = Pose.STUMBLE
	_pose_time = 0.0
	_smear = 0.0
	queue_redraw()


## Returns the hero to idle and stands the dummy up.
func reset() -> void:
	_pose = Pose.IDLE
	_pose_time = 10.0
	_smear = 0.0
	_dummy_t = 0.0
	queue_redraw()


## Advances animation timers. The main script skips this call during hit stop.
func advance(delta: float) -> void:
	_pose_time += delta
	_smear = maxf(0.0, _smear - delta)
	_dummy_t = maxf(0.0, _dummy_t - delta)
	queue_redraw()


func _draw() -> void:
	draw_line(Vector2(20, DUMMY_FEET.y + 4.0), Vector2(520, DUMMY_FEET.y + 4.0), Color(Kata.INK, 0.15), 2.0)
	_draw_dummy()
	_draw_hero()


func _blend_weight() -> float:
	var hold: float = HOLD_TIMES[_pose]
	if _pose_time <= hold:
		return 1.0
	return clampf(1.0 - (_pose_time - hold) / RETURN_TIME, 0.0, 1.0)


func _draw_hero() -> void:
	var weight: float = _blend_weight()
	var pts: PackedVector2Array = PackedVector2Array()
	for i in poses[0].size():
		pts.append(poses[0][i].lerp(poses[_pose][i], weight))
	var bob: float = absf(sin(PI * beat_phase)) * -4.0
	draw_set_transform(HERO_HIP + Vector2(0, bob + LIFTS[_pose] * weight))
	var ink: Color = Kata.INK
	var dim: Color = Color(ink, 0.65)
	draw_polyline(PackedVector2Array([pts[1], pts[2], pts[3]]), dim, 6.0, true)
	draw_polyline(PackedVector2Array([Vector2.ZERO, pts[6], pts[7]]), dim, 6.0, true)
	draw_polyline(PackedVector2Array([Vector2.ZERO, pts[8], pts[9]]), ink, 6.0, true)
	draw_line(Vector2.ZERO, pts[1], ink, 7.0, true)
	draw_polyline(PackedVector2Array([pts[1], pts[4], pts[5]]), ink, 6.0, true)
	draw_circle(pts[0], 13.0, ink)
	if _pose == Pose.SHOOT and weight > 0.0:
		draw_line(pts[5], pts[5] + Vector2(18, -2), Kata.AMBER, 6.0)
	_draw_smear(pts, bob)
	draw_set_transform(Vector2.ZERO)


func _draw_smear(pts: PackedVector2Array, bob: float) -> void:
	if _smear <= 0.0:
		return
	var life: float = _smear / SMEAR_TIME
	match _pose:
		Pose.PUNCH:
			draw_arc(Vector2(10, -48), 62.0, -0.7, 0.5, 16, Color(Kata.CYAN, life), 8.0, true)
		Pose.KICK:
			draw_arc(Vector2(0, -6), 74.0, -1.0, 0.1, 16, Color(Kata.MAGENTA, life), 8.0, true)
		Pose.SHOOT:
			var muzzle: Vector2 = pts[5] + Vector2(18, -2)
			var target: Vector2 = DUMMY_FEET + Vector2(0, -50) - HERO_HIP - Vector2(0, bob)
			var head: Vector2 = muzzle.lerp(target, 1.0 - life)
			var tail: Vector2 = muzzle.lerp(target, maxf(0.0, 1.0 - life - 0.4))
			draw_line(tail, head, Color(Kata.AMBER, 0.9), 4.0, true)
			draw_circle(muzzle, 9.0 * life, Color(Kata.INK, life))
		Pose.FINISHER:
			draw_arc(Vector2(10, -30), 96.0, -1.3, 1.3, 24, Color(Kata.INK, life), 8.0, true)
			draw_arc(Vector2(10, -30), 80.0, -1.2, 1.2, 24, Color(Kata.AMBER, life), 6.0, true)


func _draw_dummy() -> void:
	var progress: float = 1.0 - _dummy_t / DUMMY_TIME if _dummy_t > 0.0 else 1.0
	var swing: float = sin(PI * progress)
	var tilt: float = swing * (1.5 if _dummy_big else 0.7)
	draw_set_transform(DUMMY_FEET + Vector2(swing * (16.0 if _dummy_big else 8.0), 0), tilt)
	var color: Color = Kata.INK if progress < 0.25 else Kata.MAGENTA
	draw_circle(Vector2(0, -72), 13.0, color)
	draw_line(Vector2(0, -59), Vector2(0, -20), color, 6.0, true)
	draw_line(Vector2(-20, -50), Vector2(20, -50), color, 6.0, true)
	draw_line(Vector2(0, -20), Vector2(-14, 0), color, 6.0, true)
	draw_line(Vector2(0, -20), Vector2(14, 0), color, 6.0, true)
	draw_set_transform(Vector2.ZERO)


func _make_burst(amount: int, speed: float, size: float) -> CPUParticles2D:
	var burst: CPUParticles2D = CPUParticles2D.new()
	burst.position = DUMMY_FEET + Vector2(0, -52)
	burst.amount = amount
	burst.one_shot = true
	burst.emitting = false
	burst.explosiveness = 1.0
	burst.lifetime = 0.45
	burst.direction = Vector2(0.6, -1.0)
	burst.spread = 80.0
	burst.initial_velocity_min = speed * 0.5
	burst.initial_velocity_max = speed
	burst.gravity = Vector2(0, 700)
	burst.scale_amount_min = size * 0.6
	burst.scale_amount_max = size
	add_child(burst)
	return burst
