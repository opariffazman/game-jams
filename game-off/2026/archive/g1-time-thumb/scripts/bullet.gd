class_name Bullet
extends Node2D
## A slow round with a short [Line2D] trail that points back along its path.

## Velocity in pixels per world second.
var velocity: Vector2 = Vector2.ZERO

## True for amber gunman bullets, false for cyan hero bullets.
var hostile: bool = true

var _color: Color = Color.WHITE


## Sets position, velocity, and color. Call before adding to the tree.
func setup(start: Vector2, new_velocity: Vector2, new_color: Color, is_hostile: bool) -> void:
	position = start
	velocity = new_velocity
	_color = new_color
	hostile = is_hostile
	var trail := Line2D.new()
	trail.width = 4.0
	trail.default_color = _color
	trail.gradient = Gradient.new()
	trail.gradient.set_color(0, Color(_color, 0.0))
	trail.gradient.set_color(1, _color)
	trail.points = PackedVector2Array([-velocity.normalized() * clampf(velocity.length() * 0.1, 14.0, 44.0), Vector2.ZERO])
	add_child(trail)


## Moves the bullet by one world-time step.
func step(world_dt: float) -> void:
	position += velocity * world_dt


func _draw() -> void:
	draw_circle(Vector2.ZERO, 5.0, _color)
	draw_arc(Vector2.ZERO, 8.0, 0.0, TAU, 20, Color(_color, 0.35), 2.0, true)
