class_name RestartUiScale
extends RefCounted
## Converts CSS pixels to viewport pixels and reads the safe area for the restart controls.
##
## The viewport is scaled to the window, so a phone shows 640 viewport pixels in about 390 CSS
## pixels. Touch targets are sized in CSS pixels, so their size on the phone does not depend on
## the stretch mode. The HUD keeps its own copy of this maths.

## Smallest gap between a control and the screen edge, in viewport pixels.
const EDGE_MARGIN: float = 16.0
## Settings gear diameter in CSS pixels. The restart ring sits below it, so both read it.
const GEAR_DIAMETER_CSS_PX: float = 48.0


## Viewport pixels that one CSS pixel covers on the physical screen.
static func pixels_per_css(viewport: Viewport) -> float:
	var visible_height: float = viewport.get_visible_rect().size.y
	var css_height: float = float(DisplayServer.window_get_size().y)
	if OS.has_feature("web"):
		var inner: Variant = JavaScriptBridge.eval("window.innerHeight")
		if inner is float and inner > 0.0:
			css_height = inner
	if css_height <= 0.0:
		return 1.0
	return visible_height / css_height


## Gap to each screen edge in viewport pixels as (left, top, right, bottom). It is never under [constant EDGE_MARGIN].
static func edge_insets(viewport: Viewport) -> Vector4:
	var inset: Vector4 = Vector4.ZERO
	if OS.has_feature("mobile") or OS.has_feature("web"):
		var safe: Rect2i = DisplayServer.get_display_safe_area()
		var screen: Vector2i = DisplayServer.screen_get_size()
		var window: Vector2i = DisplayServer.window_get_size()
		if safe.has_area() and window.y > 0 and screen.y > 0:
			var scale: float = viewport.get_visible_rect().size.y / float(window.y)
			inset = Vector4(
				safe.position.x,
				safe.position.y,
				screen.x - safe.end.x,
				screen.y - safe.end.y
			) * scale
	return Vector4(
		maxf(EDGE_MARGIN, inset.x),
		maxf(EDGE_MARGIN, inset.y),
		maxf(EDGE_MARGIN, inset.z),
		maxf(EDGE_MARGIN, inset.w)
	)


## Arena rectangle in viewport pixels.
static func arena_rect(viewport: Viewport) -> Rect2:
	var tuning: Tuning = Tuning.load_default()
	var transform: Transform2D = viewport.get_canvas_transform()
	var top_left: Vector2 = transform * (tuning.arena_centre - tuning.arena_half_extents)
	var bottom_right: Vector2 = transform * (tuning.arena_centre + tuning.arena_half_extents)
	return Rect2(top_left, bottom_right - top_left)


## X of the arena's right border in viewport pixels.
static func arena_right_edge(viewport: Viewport) -> float:
	return arena_rect(viewport).end.x


## Centres of the two top right controls, in one column at the screen corner.
## They anchor to the visible rect, because the canvas transform lags a window resize and moves with the camera zoom.
## The gear is on top and the restart ring is below it. Both stay clear of the border by [param gap]
## viewport pixels and clear of the HUD row by [param row_bottom]. Returns {"gear": Vector2, "restart": Vector2}.
static func top_right_column(viewport: Viewport, gear_radius: float, restart_radius: float, gap: float, row_bottom: float) -> Dictionary:
	var screen: Vector2 = viewport.get_visible_rect().size
	var insets: Vector4 = edge_insets(viewport)
	var right_limit: float = screen.x - maxf(insets.z, gap)
	var top_limit: float = row_bottom
	var gear_x: float = right_limit - gear_radius
	var restart_x: float = right_limit - restart_radius
	var gear_y: float = top_limit + gear_radius
	var restart_y: float = gear_y + gear_radius + gap + restart_radius
	return {"gear": Vector2(gear_x, gear_y), "restart": Vector2(restart_x, restart_y)}

