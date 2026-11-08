class_name StickFigure
extends Node2D
## Stick-figure silhouette drawn in code. A pose is a set of line endpoints.

## Body poses.
enum Pose {
	STAND, ## arms down
	AIM, ## one arm points along [member aim_angle]
	FALL, ## lying flat
}

## Silhouette color.
@export var color: Color = Color.WHITE

## Direction of the aiming arm, in radians.
var aim_angle: float = -PI * 0.5

var _pose: Pose = Pose.STAND


## Switches pose and redraws.
func set_pose(new_pose: Pose) -> void:
	_pose = new_pose
	queue_redraw()


## Points the aiming arm and redraws when the angle changed.
func aim_at(angle: float) -> void:
	if is_equal_approx(angle, aim_angle):
		return
	aim_angle = angle
	queue_redraw()


func _draw() -> void:
	var line := func(a: Vector2, b: Vector2) -> void:
		draw_line(a, b, color, 4.0, true)
	if _pose == Pose.FALL:
		draw_circle(Vector2(-34.0, -7.0), 9.0, color)
		line.call(Vector2(-25.0, -5.0), Vector2(3.0, -5.0))
		line.call(Vector2(3.0, -5.0), Vector2(26.0, -15.0))
		line.call(Vector2(3.0, -5.0), Vector2(28.0, 2.0))
		line.call(Vector2(-18.0, -5.0), Vector2(-30.0, -25.0))
		line.call(Vector2(-14.0, -5.0), Vector2(-2.0, 9.0))
		return
	draw_circle(Vector2(0.0, -46.0), 9.0, color)
	line.call(Vector2(0.0, -37.0), Vector2(0.0, -14.0))
	line.call(Vector2(0.0, -14.0), Vector2(-10.0, 12.0))
	line.call(Vector2(0.0, -14.0), Vector2(10.0, 12.0))
	var shoulder := Vector2(0.0, -32.0)
	if _pose == Pose.AIM:
		var dir := Vector2.from_angle(aim_angle)
		line.call(shoulder, shoulder + dir * 24.0)
		line.call(shoulder, shoulder + dir.rotated(0.9) * 14.0)
	else:
		line.call(shoulder, Vector2(-13.0, -14.0))
		line.call(shoulder, Vector2(13.0, -14.0))
