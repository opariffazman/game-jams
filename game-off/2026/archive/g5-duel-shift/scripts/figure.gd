class_name Figure
extends Node2D
## Stick-figure silhouette. A pose is a set of line endpoints around the hip at the origin.

## Pose point order: head, neck, hip, left hand, right hand, left foot, right foot.
const POSES: Dictionary = {
	&"stand": [Vector2(0, -82), Vector2(0, -64), Vector2(0, 0), Vector2(-30, -34), Vector2(30, -34), Vector2(-16, 56), Vector2(16, 56)],
	&"left": [Vector2(-16, -80), Vector2(-9, -62), Vector2(0, 0), Vector2(-42, -50), Vector2(24, -22), Vector2(-28, 54), Vector2(14, 56)],
	&"right": [Vector2(16, -80), Vector2(9, -62), Vector2(0, 0), Vector2(-24, -22), Vector2(42, -50), Vector2(-14, 56), Vector2(28, 54)],
	&"duck": [Vector2(0, -34), Vector2(0, -20), Vector2(0, 10), Vector2(-34, 4), Vector2(34, 4), Vector2(-36, 56), Vector2(36, 56)],
	&"lunge": [Vector2(12, -70), Vector2(5, -56), Vector2(0, 0), Vector2(-26, -20), Vector2(36, -88), Vector2(-36, 40), Vector2(32, 52)],
	&"stagger": [Vector2(-22, -72), Vector2(-12, -58), Vector2(0, 0), Vector2(-44, -70), Vector2(34, -20), Vector2(-24, 56), Vector2(22, 50)],
	&"charge": [Vector2(0, -82), Vector2(0, -64), Vector2(0, 0), Vector2(-36, -92), Vector2(36, -92), Vector2(-20, 56), Vector2(20, 56)],
	&"recoil": [Vector2(0, -74), Vector2(0, -60), Vector2(0, 0), Vector2(-44, -30), Vector2(44, -30), Vector2(-26, 54), Vector2(26, 54)],
	&"down": [Vector2(-74, 24), Vector2(-54, 18), Vector2(0, 10), Vector2(-62, 46), Vector2(-26, -12), Vector2(52, 34), Vector2(58, 10)],
}
## Head radius in pixels.
const HEAD_RADIUS: float = 14.0

## Line and head color.
var color: Color = Palette.CYAN
var _pose: StringName = &"stand"


## Switches to pose [param pose_name] in the same frame.
func set_pose(pose_name: StringName) -> void:
	_pose = pose_name
	queue_redraw()


func _draw() -> void:
	var pts: Array = POSES[_pose]
	var limbs: Array[Vector2] = [
		pts[1], pts[2], pts[1], pts[3], pts[1], pts[4], pts[2], pts[5], pts[2], pts[6], pts[0], pts[1],
	]
	for glow: bool in [true, false]:
		var tint: Color = Color(color, 0.22) if glow else color
		var width: float = 13.0 if glow else 6.0
		for i: int in range(0, limbs.size(), 2):
			draw_line(limbs[i], limbs[i + 1], tint, width, true)
		draw_circle(pts[0], HEAD_RADIUS * (1.5 if glow else 1.0), tint)
