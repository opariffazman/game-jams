class_name EntityVisual
extends Node2D
## Base class for every art scene in a [VisualSet].
##
## Logic nodes talk to art only through this API. A visual that lacks an
## animation ignores the state. Art never changes hitboxes. Hitboxes come
## from [Tuning].

## Animation states a visual can play.
const STATES: Array[StringName] = [&"idle", &"run", &"carry", &"throw", &"dash", &"die", &"hit"]

## Tint the logic node asked for. [constant Color.WHITE] means "use the skin default".
var team_color: Color = Color.WHITE
## True after [method set_team_color] ran at least once.
var has_team_color: bool = false


## Plays [param state]. A visual without that animation ignores the call.
func play(_state: StringName) -> void:
	pass


## Rotates the art to face [param angle] in radians. 0 points along +x.
func set_facing(angle: float) -> void:
	rotation = angle


## Tints the art with [param color].
func set_team_color(color: Color) -> void:
	team_color = color
	has_team_color = true


## Tells the art how large the area is. Only the arena visual uses it.
func set_extent(_extent: Vector2) -> void:
	pass


## Tells the art where the throw ring and the orbit ring are, as radii around the arena centre.
## Only the arena visual uses it. A skin that draws no guides ignores it.
func set_guide_radii(_throw_radius: float, _orbit_radius: float) -> void:
	pass
