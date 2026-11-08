class_name Figure
extends Node2D
## Stick-figure silhouette drawn from line endpoints. Origin is the body center.

## Visible poses.
enum Pose { STAND, AIM, FALL }

## Silhouette color.
var color: Color = Color.WHITE
## Current pose.
var pose: Pose = Pose.STAND:
	set(value):
		pose = value
		queue_redraw()
## Unit direction the gun arm points along in [constant Pose.AIM].
var aim_dir: Vector2 = Vector2.UP
## Small index label above the head. Empty hides it.
var tag: String = "":
	set(value):
		tag = value
		queue_redraw()
## [enum RoomState.Kind] drawn: a shield gets an arc, a knife gets a blade instead of a gun.
var kind: int = RoomState.Kind.PISTOL
## [enum RoomState.Facing] of a shield.
var facing: int = RoomState.Facing.UP
## Horizontal mirror for the fall pose, 1.0 or -1.0.
var fall_side: float = 1.0


func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(fall_side if pose == Pose.FALL else 1.0, 1.0))
	match pose:
		Pose.STAND:
			_draw_body(Vector2(0, -22), Vector2(0, -14), Vector2(0, 6))
			_line(Vector2(0, -10), Vector2(-11, 2))
			_line(Vector2(0, -10), Vector2(11, 2))
		Pose.AIM:
			_draw_body(Vector2(0, -22), Vector2(0, -14), Vector2(0, 6))
			var shoulder: Vector2 = Vector2(0, -10)
			var arm: Vector2 = aim_dir
			_line(shoulder, shoulder + arm * 20.0)
			if kind == RoomState.Kind.KNIFE:
				_draw_blade(shoulder + arm * 20.0, arm)
			else:
				_line(shoulder + arm * 20.0, shoulder + arm * 28.0, 5.0)
			_line(shoulder, shoulder + arm.rotated(0.5) * 12.0)
		Pose.FALL:
			draw_circle(Vector2(-26, 12), 8.0, color)
			_line(Vector2(-17, 12), Vector2(6, 12))
			_line(Vector2(6, 12), Vector2(22, 6))
			_line(Vector2(6, 12), Vector2(22, 16))
			_line(Vector2(-12, 12), Vector2(-18, 2))
			_line(Vector2(-4, 12), Vector2(-4, 1))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if kind == RoomState.Kind.SHIELD and pose != Pose.FALL:
		var angle: float = RoomState.facing_vector(facing).angle()
		draw_arc(Vector2(0, -6), 32.0, angle - PI / 3.0, angle + PI / 3.0, 14, Color("f6f6f8"), 9.0, true)
	if tag != "":
		draw_string(ThemeDB.fallback_font, Vector2(-5, -38), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("f6f6f8"))


func _draw_body(head: Vector2, neck: Vector2, hip: Vector2) -> void:
	draw_circle(head, 8.0, color)
	_line(neck, hip)
	_line(hip, Vector2(-8, 18))
	_line(hip, Vector2(8, 18))


func _draw_blade(base: Vector2, dir: Vector2) -> void:
	var side: Vector2 = dir.orthogonal() * 5.0
	draw_colored_polygon(PackedVector2Array([base + side, base - side, base + dir * 20.0]), Color("f6f6f8"))


func _line(a: Vector2, b: Vector2, width: float = 3.0) -> void:
	draw_line(a, b, color, width, true)
