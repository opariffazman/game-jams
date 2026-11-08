class_name PrimitiveVisual
extends EntityVisual
## Flat shape visual for the primitives skin: circle, square or tombstone icon.
##
## Size here is art only. Hitboxes come from [Tuning].

## Shape this visual draws.
enum Kind { CIRCLE, SQUARE, TOMBSTONE }

## Icon drawn for [constant Kind.TOMBSTONE].
const TOMBSTONE_ICON_PATH: String = "res://assets/icons/tombstone.svg"
## Outline colour that keeps shapes readable on any floor.
const OUTLINE_COLOR: Color = Color("0f1729")
## Colour of the small sandal marker shown while carrying.
const SANDAL_COLOR: Color = Color("f4d58d")

## Shape to draw.
@export var kind: Kind = Kind.CIRCLE
## Half size of the shape in pixels.
@export var half_size: float = 18.0

var _color: Color = Color.WHITE
var _carrying: bool = false
var _icon: Texture2D
var _pulse: Tween


func _ready() -> void:
	if kind == Kind.TOMBSTONE and ResourceLoader.exists(TOMBSTONE_ICON_PATH):
		_icon = load(TOMBSTONE_ICON_PATH) as Texture2D


func _draw() -> void:
	match kind:
		Kind.CIRCLE:
			draw_circle(Vector2.ZERO, half_size + 2.0, OUTLINE_COLOR)
			draw_circle(Vector2.ZERO, half_size, _color)
			_draw_facing_tick()
		Kind.SQUARE:
			var outer: Rect2 = Rect2(Vector2.ONE * -(half_size + 2.0), Vector2.ONE * (half_size + 2.0) * 2.0)
			var inner: Rect2 = Rect2(Vector2.ONE * -half_size, Vector2.ONE * half_size * 2.0)
			draw_rect(outer, OUTLINE_COLOR)
			draw_rect(inner, _color)
			_draw_facing_tick()
		Kind.TOMBSTONE:
			var box: Rect2 = Rect2(Vector2.ONE * -half_size * 1.2, Vector2.ONE * half_size * 2.4)
			if _icon != null:
				draw_texture_rect(_icon, box, false, _color)
			else:
				draw_rect(box, _color)
	if _carrying:
		draw_circle(Vector2(0.0, -half_size - 6.0), half_size * 0.3, SANDAL_COLOR)


## Reacts to [param state]. Unknown states are ignored.
func play(state: StringName) -> void:
	_carrying = state == &"carry"
	match state:
		&"throw":
			_punch(Vector2(1.3, 0.8))
		&"dash":
			_punch(Vector2(1.5, 0.7))
		&"hit":
			_punch(Vector2(1.2, 1.2))
	queue_redraw()


## Turns the shape toward [param angle] in radians. A tombstone never turns.
func set_facing(angle: float) -> void:
	if kind != Kind.TOMBSTONE:
		rotation = angle


## Tints the shape with [param color].
func set_team_color(color: Color) -> void:
	_color = color
	queue_redraw()


func _punch(peak: Vector2) -> void:
	if _pulse != null and _pulse.is_valid():
		_pulse.kill()
	scale = Vector2.ONE
	_pulse = create_tween()
	_pulse.tween_property(self, "scale", peak, 0.06)
	_pulse.tween_property(self, "scale", Vector2.ONE, 0.12)


func _draw_facing_tick() -> void:
	draw_line(Vector2(half_size * 0.3, 0.0), Vector2(half_size * 0.75, 0.0), OUTLINE_COLOR, 2.0)
