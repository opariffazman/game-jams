class_name ViewProjection
extends RefCounted
## Maps between arena ground points and screen pixels for the active view.
##
## The flat view maps through the canvas transform alone. The depth view looks at the arena through a
## side-on tilted orthographic camera (Strikers style): yaw [constant YAW_DEGREES], pitch [member pitch_degrees]. An orthographic
## ground projection is affine, so one [Transform2D] describes it and the maths here matches the [Camera3D] of
## [World3DView] exactly. [World3DView] switches it on while it lives. Without it every function returns the flat answer.
##
## Input uses the direction functions, so thumb up on the screen always moves a character up on the screen.
## Overlays that draw on the ground use [method overlay_transform], so a circle shows as an ellipse on the floor.
## With yaw 0 the ground x axis stays horizontal on the screen and only the depth axis squashes by sin(pitch).

## Camera yaw around the vertical axis, degrees.
const YAW_DEGREES: float = 0.0
## Default camera pitch below the horizon, degrees.
const DEFAULT_PITCH_DEGREES: float = 42.0
## Pitch limits of the camera slider, degrees.
const MIN_PITCH_DEGREES: float = 25.0
const MAX_PITCH_DEGREES: float = 70.0
## Screen pixels per ground pixel at canvas zoom 1. The field plus the village fit the viewport at this value.
const DEFAULT_FIT: float = 1.0
## Zoom limits of the camera slider.
const MIN_FIT: float = 0.6
const MAX_FIT: float = 1.6
## Extra zoom while the build view is on.
const BUILD_ZOOM: float = 1.9

## Live camera pitch below the horizon, degrees. The settings panel moves it.
static var pitch_degrees: float = DEFAULT_PITCH_DEGREES
## Live screen pixels per ground pixel at canvas zoom 1. The settings panel moves it.
static var fit: float = DEFAULT_FIT
## True while a [World3DView] exists.
static var active: bool = false
## Build view blend from 0.0 (arena) to 1.0 (close on [member build_focus]).
static var build_blend: float = 0.0
## Ground point the camera moves to during the build view.
static var build_focus: Vector2 = Vector2.ZERO


## Rotation of the camera in the 3D world.
static func camera_basis() -> Basis:
	return Basis.from_euler(Vector3(-deg_to_rad(pitch_degrees), deg_to_rad(YAW_DEGREES), 0.0), EULER_ORDER_YXZ)


## Ground to screen pixels at zoom 1, with no origin. A 3D point (x, 0, z) is the arena point (x, z).
static func linear() -> Transform2D:
	var basis: Basis = camera_basis()
	return Transform2D(
		Vector2(basis.x.x, -basis.y.x) * fit,
		Vector2(basis.x.z, -basis.y.z) * fit,
		Vector2.ZERO
	)


## Height of a ground circle on the screen divided by its width. 1.0 in the flat view.
static func squash() -> float:
	return sin(deg_to_rad(pitch_degrees)) if active else 1.0


## Zoom of the active view: the canvas zoom, times the build view zoom.
static func zoom(viewport: Viewport) -> float:
	var canvas_zoom: float = maxf(viewport.get_canvas_transform().x.length(), 0.01)
	return canvas_zoom * lerpf(1.0, BUILD_ZOOM, build_blend) if active else canvas_zoom


## Ground point shown at the middle of the screen.
static func centre(viewport: Viewport) -> Vector2:
	var canvas: Transform2D = viewport.get_canvas_transform()
	var middle: Vector2 = canvas.affine_inverse() * (viewport.get_visible_rect().size * 0.5)
	return middle.lerp(build_focus, build_blend) if active else middle


## Ground to screen transform of the active view.
static func view(viewport: Viewport) -> Transform2D:
	if not active:
		return viewport.get_canvas_transform()
	var factor: float = zoom(viewport)
	var lin: Transform2D = linear()
	var scaled: Transform2D = Transform2D(lin.x * factor, lin.y * factor, Vector2.ZERO)
	return Transform2D(scaled.x, scaled.y, viewport.get_visible_rect().size * 0.5 - scaled * centre(viewport))


## Screen position of the ground point [param point].
static func to_screen(viewport: Viewport, point: Vector2) -> Vector2:
	return view(viewport) * point


## Ground point under the screen position [param screen].
static func to_world(viewport: Viewport, screen: Vector2) -> Vector2:
	return view(viewport).affine_inverse() * screen


## Ground direction for a screen direction. The length stays the same.
static func screen_dir_to_world(direction: Vector2) -> Vector2:
	if not active or direction == Vector2.ZERO:
		return direction
	return (linear().affine_inverse() * direction).normalized() * direction.length()


## Screen direction for a ground direction. The length stays the same.
static func world_dir_to_screen(direction: Vector2) -> Vector2:
	if not active or direction == Vector2.ZERO:
		return direction
	return (linear() * direction).normalized() * direction.length()


## Transform for a node that draws in ground coordinates under the canvas transform.
## Set it as the global transform of the node. Identity in the flat view.
static func overlay_transform(viewport: Viewport) -> Transform2D:
	if not active:
		return Transform2D.IDENTITY
	return viewport.get_canvas_transform().affine_inverse() * view(viewport)
