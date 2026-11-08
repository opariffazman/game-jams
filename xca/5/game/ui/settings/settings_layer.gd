class_name SettingsLayer
extends CanvasLayer
## Gear button and icon-only settings panel.
##
## The gear sits at the top right, clear of the arena border and of the restart ring. The panel holds two
## large scheme tiles with the active one ringed, a haptics toggle, a sound toggle, and a flat or depth view choice
## that applies at the next round start. It pauses the game tree while open,
## because a round running behind a thumb-sized panel would cost the player a life. The layer keeps
## processing while paused. Escape opens and closes it on desktop.
## Every target is at least 56 CSS pixels. It never draws text.

## Emitted when the panel opens or closes.
signal panel_toggled(open: bool)

## Tile diameter in CSS pixels. WCAG 2.5.8 needs 24 and this layer uses more than twice that.
const TILE_DIAMETER_CSS_PX: float = 76.0
## Smallest hit radius for any target in viewport pixels.
const MIN_RADIUS: float = 28.0
## Height of a camera slider touch target in CSS pixels.
const SLIDER_HIT_CSS_PX: float = 48.0
## Length of a camera slider track in CSS pixels.
const SLIDER_TRACK_CSS_PX: float = 180.0
## Pitch step and zoom step of one arrow key press.
const KEY_PITCH_STEP: float = 2.0
const KEY_ZOOM_STEP: float = 0.05
## Gap between tiles in CSS pixels.
const TILE_GAP_CSS_PX: float = 24.0
## Height of the HUD top row in CSS pixels.
const HUD_ROW_CSS_PX: float = 44.0
## Gap below the HUD row in CSS pixels.
const ROW_GAP_CSS_PX: float = 8.0
## Gap between the gear and the arena border in CSS pixels.
const BORDER_GAP_CSS_PX: float = 10.0

## Settings gear icon.
@export var gear_icon: Texture2D = preload("res://assets/icons/settings_cog.svg")
## Scheme D tile icon.
@export var lock_icon: Texture2D = preload("res://assets/icons/scheme_lock.svg")
## Scheme A tile icon.
@export var aim_icon: Texture2D = preload("res://assets/icons/scheme_aim.svg")
## Haptics tile icon.
@export var haptics_icon: Texture2D = preload("res://assets/icons/haptics_phone.svg")
## Sound on tile icon.
@export var sound_on_icon: Texture2D = preload("res://assets/icons/sound_on.svg")
## Sound off tile icon.
@export var sound_off_icon: Texture2D = preload("res://assets/icons/sound_off.svg")
## Flat view tile icon.
@export var view_flat_icon: Texture2D = preload("res://assets/icons/view_2d.svg")
## Depth view tile icon.
@export var view_depth_icon: Texture2D = preload("res://assets/icons/view_3d.svg")
## Camera angle slider icon.
@export var camera_angle_icon: Texture2D = preload("res://assets/icons/camera_angle.svg")
## Camera zoom slider icon.
@export var camera_zoom_icon: Texture2D = preload("res://assets/icons/camera_zoom.svg")
## Camera reset button icon.
@export var camera_reset_icon: Texture2D = preload("res://assets/icons/camera_reset.svg")
## Fullscreen button icon while the page is windowed.
@export var fullscreen_enter_icon: Texture2D = preload("res://assets/icons/fullscreen_expand.svg")
## Fullscreen button icon while the page is fullscreen.
@export var fullscreen_exit_icon: Texture2D = preload("res://assets/icons/fullscreen_contract.svg")
## Close icon.
@export var close_icon: Texture2D = preload("res://assets/icons/throw_cancel.svg")
## Ring and icon colour. Reads above 4.5:1 on the dim backdrop.
@export var ink_color: Color = Color(0.96, 0.96, 0.96, 1.0)
## Ring colour of the active choice.
@export var active_color: Color = Color(0.25, 0.75, 1.0, 1.0)
## Colour over the game while the panel is open.
@export var scrim_color: Color = Color(0.04, 0.06, 0.1, 0.9)
## Colour over the game in the depth view. It is light, so the field shows while the camera sliders move.
@export var depth_scrim_color: Color = Color(0.04, 0.06, 0.1, 0.55)
## Fill behind each target.
@export var backdrop_color: Color = Color(0.06, 0.09, 0.16, 0.9)

## True while the panel shows.
var open: bool = false

var _canvas: Control


func _ready() -> void:
	layer = 11
	process_mode = Node.PROCESS_MODE_ALWAYS
	_canvas = SettingsCanvas.new()
	_canvas.layer_owner = self
	add_child(_canvas)
	SettingsRef.on_scheme_changed(func(_scheme: int) -> void: _canvas.queue_redraw())
	SettingsRef.on_view_changed(func(_view: int) -> void: _canvas.queue_redraw())
	SettingsRef.on_haptics_changed(func(_enabled: bool) -> void: _canvas.queue_redraw())
	SettingsRef.on_camera_changed(func(_pitch: float, _zoom: float) -> void: _canvas.queue_redraw())
	SettingsRef.on_sound_changed(func(_enabled: bool) -> void: _canvas.queue_redraw())


func _unhandled_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_ESCAPE:
		toggle()
		get_viewport().set_input_as_handled()
		return
	if key != null and key.pressed and open and SettingsRef.view() == SettingsRef.VIEW_DEPTH:
		var pitch: float = SettingsRef.camera_pitch()
		var zoom: float = SettingsRef.camera_zoom()
		match key.physical_keycode:
			KEY_UP:
				pitch += KEY_PITCH_STEP
			KEY_DOWN:
				pitch -= KEY_PITCH_STEP
			KEY_RIGHT:
				zoom += KEY_ZOOM_STEP
			KEY_LEFT:
				zoom -= KEY_ZOOM_STEP
			_:
				return
		SettingsRef.set_camera(pitch, zoom)
		get_viewport().set_input_as_handled()


## Opens or closes the panel.
func toggle() -> void:
	set_open(not open)


## Opens or closes the panel and pauses or resumes the round.
func set_open(value: bool) -> void:
	if open == value:
		return
	open = value
	get_tree().paused = open
	_canvas.release_all()
	_canvas.queue_redraw()
	panel_toggled.emit(open)


## Centre and radius of the gear in viewport pixels.
func gear_hit() -> Dictionary:
	return _canvas.gear_hit()


## Touch rectangle of a camera slider, by name: camera_pitch or camera_zoom. Empty unless the depth view is chosen.
func slider_rect(slider: StringName) -> Rect2:
	return _canvas.slider_rect(slider)


## Centre and radius of the fullscreen button in viewport pixels.
func fullscreen_hit() -> Dictionary:
	return _canvas.fullscreen_hit()


## Centre and radius of a tile, by name: scheme_lock, scheme_aim, haptics, sound, view_flat, view_depth, close, camera_reset.
func tile_hit(tile: StringName) -> Dictionary:
	return _canvas.tile_hit(tile)


## Draws the controls and reads touch. The layer owns the state.
class SettingsCanvas:
	extends Control

	var layer_owner: SettingsLayer
	var _finger: int = -1
	var _pressed: StringName = &""
	var _slider_finger: int = -1
	var _slider: StringName = &""
	var _fullscreen_available: bool = false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)
		process_mode = Node.PROCESS_MODE_ALWAYS
		get_viewport().size_changed.connect(queue_redraw)
		_fullscreen_available = FullscreenToggle.available()

	func _input(event: InputEvent) -> void:
		if _handle_slider(event):
			get_viewport().set_input_as_handled()
			return
		if event is InputEventScreenTouch:
			var touch: InputEventScreenTouch = event
			if touch.pressed and _finger == -1:
				var hit: StringName = _target_at(touch.position)
				if hit != &"":
					_finger = touch.index
					_pressed = hit
					queue_redraw()
					get_viewport().set_input_as_handled()
				elif layer_owner.open:
					get_viewport().set_input_as_handled()
			elif not touch.pressed and touch.index == _finger:
				var same: bool = _target_at(touch.position) == _pressed
				var chosen: StringName = _pressed
				release_all()
				if same:
					_activate(chosen)
				get_viewport().set_input_as_handled()
		elif event is InputEventScreenDrag and layer_owner.open:
			get_viewport().set_input_as_handled()

	func _handle_slider(event: InputEvent) -> bool:
		if not layer_owner.open:
			return false
		var touch: InputEventScreenTouch = event as InputEventScreenTouch
		if touch != null and touch.pressed and _slider_finger == -1:
			var hit: StringName = _slider_at(touch.position)
			if hit != &"":
				_slider_finger = touch.index
				_slider = hit
				_set_slider(touch.position.x, false)
				return true
		elif touch != null and not touch.pressed and touch.index == _slider_finger:
			_set_slider(touch.position.x, true)
			_slider_finger = -1
			_slider = &""
			queue_redraw()
			return true
		var drag: InputEventScreenDrag = event as InputEventScreenDrag
		if drag != null and drag.index == _slider_finger:
			_set_slider(drag.position.x, false)
			return true
		return false

	func _slider_at(point: Vector2) -> StringName:
		for id: StringName in [&"camera_pitch", &"camera_zoom"]:
			if slider_rect(id).has_point(point):
				return id
		return &""

	func _set_slider(x: float, persist: bool) -> void:
		var rect: Rect2 = slider_rect(_slider)
		var fraction: float = clampf((x - rect.position.x) / rect.size.x, 0.0, 1.0)
		var pitch: float = SettingsRef.camera_pitch()
		var zoom: float = SettingsRef.camera_zoom()
		if _slider == &"camera_pitch":
			pitch = lerpf(ViewProjection.MIN_PITCH_DEGREES, ViewProjection.MAX_PITCH_DEGREES, fraction)
		else:
			zoom = lerpf(ViewProjection.MIN_FIT, ViewProjection.MAX_FIT, fraction)
		SettingsRef.set_camera(pitch, zoom, persist)

	func slider_rect(slider: StringName) -> Rect2:
		var metrics: Dictionary = _metrics()
		var rects: Dictionary = metrics["sliders"]
		return rects.get(slider, Rect2())

	func release_all() -> void:
		_slider_finger = -1
		_slider = &""
		_finger = -1
		_pressed = &""
		queue_redraw()

	func gear_hit() -> Dictionary:
		var metrics: Dictionary = _metrics()
		return {"centre": metrics["gear_centre"], "radius": metrics["gear_radius"]}

	func fullscreen_hit() -> Dictionary:
		var metrics: Dictionary = _metrics()
		return {"centre": metrics["fullscreen_centre"], "radius": metrics["gear_radius"]}

	func tile_hit(tile: StringName) -> Dictionary:
		var metrics: Dictionary = _metrics()
		var centres: Dictionary = metrics["tiles"]
		return {"centre": centres.get(tile, Vector2.ZERO), "radius": metrics["tile_radius"]}

	func _draw() -> void:
		var metrics: Dictionary = _metrics()
		_draw_button(metrics["gear_centre"], metrics["gear_radius"], layer_owner.gear_icon, layer_owner.open, &"gear")
		if _fullscreen_available:
			var icon: Texture2D = layer_owner.fullscreen_exit_icon if FullscreenToggle.active() else layer_owner.fullscreen_enter_icon
			_draw_button(metrics["fullscreen_centre"], metrics["gear_radius"], icon, false, &"fullscreen")
		if not layer_owner.open:
			return
		var depth: bool = SettingsRef.view() == SettingsRef.VIEW_DEPTH
		draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), layer_owner.depth_scrim_color if depth else layer_owner.scrim_color)
		var radius: float = metrics["tile_radius"]
		var tiles: Dictionary = metrics["tiles"]
		_draw_button(tiles[&"scheme_lock"], radius, layer_owner.lock_icon, SettingsRef.scheme() == SettingsRef.SCHEME_LOCK_FIRE, &"scheme_lock")
		_draw_button(tiles[&"scheme_aim"], radius, layer_owner.aim_icon, SettingsRef.scheme() == SettingsRef.SCHEME_AIM_STICK, &"scheme_aim")
		_draw_button(tiles[&"haptics"], radius, layer_owner.haptics_icon, SettingsRef.haptics_enabled(), &"haptics")
		if not SettingsRef.haptics_enabled():
			var centre: Vector2 = tiles[&"haptics"]
			var arm: float = radius * 0.7
			draw_line(centre + Vector2(-arm, arm), centre + Vector2(arm, -arm), layer_owner.ink_color, maxf(5.0, radius * 0.1))
		_draw_button(tiles[&"sound"], radius, layer_owner.sound_on_icon if SettingsRef.sound_enabled() else layer_owner.sound_off_icon, SettingsRef.sound_enabled(), &"sound")
		_draw_button(tiles[&"view_flat"], radius, layer_owner.view_flat_icon, SettingsRef.view() == SettingsRef.VIEW_FLAT, &"view_flat")
		_draw_button(tiles[&"view_depth"], radius, layer_owner.view_depth_icon, SettingsRef.view() == SettingsRef.VIEW_DEPTH, &"view_depth")
		_draw_button(tiles[&"close"], radius * 0.8, layer_owner.close_icon, false, &"close")
		if depth:
			_draw_camera_controls(metrics)

	func _draw_camera_controls(metrics: Dictionary) -> void:
		var rects: Dictionary = metrics["sliders"]
		var tiles: Dictionary = metrics["tiles"]
		var icon_radius: float = metrics["slider_icon_radius"]
		var pitch_fraction: float = inverse_lerp(ViewProjection.MIN_PITCH_DEGREES, ViewProjection.MAX_PITCH_DEGREES, SettingsRef.camera_pitch())
		var zoom_fraction: float = inverse_lerp(ViewProjection.MIN_FIT, ViewProjection.MAX_FIT, SettingsRef.camera_zoom())
		_draw_slider(rects[&"camera_pitch"], pitch_fraction, layer_owner.camera_angle_icon, icon_radius, &"camera_pitch")
		_draw_slider(rects[&"camera_zoom"], zoom_fraction, layer_owner.camera_zoom_icon, icon_radius, &"camera_zoom")
		_draw_button(tiles[&"camera_reset"], icon_radius, layer_owner.camera_reset_icon, false, &"camera_reset")

	func _draw_slider(rect: Rect2, fraction: float, icon: Texture2D, icon_radius: float, id: StringName) -> void:
		var centre_y: float = rect.get_center().y
		var held: bool = _slider == id
		var pad: float = rect.size.y * 0.5
		var icon_centre: Vector2 = Vector2(rect.position.x - pad - icon_radius - 4.0, centre_y)
		_draw_button(icon_centre, icon_radius, icon, held, id)
		var thickness: float = maxf(6.0, rect.size.y * 0.14)
		draw_rect(Rect2(rect.position.x - pad, centre_y - pad * 0.8, rect.size.x + pad * 2.0, pad * 1.6), layer_owner.backdrop_color)
		draw_line(Vector2(rect.position.x, centre_y), Vector2(rect.end.x, centre_y), layer_owner.ink_color, thickness)
		var thumb: Vector2 = Vector2(rect.position.x + rect.size.x * fraction, centre_y)
		draw_line(Vector2(rect.position.x, centre_y), thumb, layer_owner.active_color, thickness)
		draw_circle(thumb, rect.size.y * 0.36, layer_owner.backdrop_color)
		draw_arc(thumb, rect.size.y * 0.36, 0.0, TAU, 40, layer_owner.active_color if held else layer_owner.ink_color, maxf(4.0, rect.size.y * 0.08))

	func _draw_button(centre: Vector2, radius: float, icon: Texture2D, active: bool, id: StringName) -> void:
		var ring: Color = layer_owner.active_color if active else layer_owner.ink_color
		var fill: Color = layer_owner.backdrop_color
		if _pressed == id:
			fill = Color(ring, 0.35)
		draw_circle(centre, radius, fill)
		var width: float = maxf(4.0, radius * 0.09) * (1.6 if active else 1.0)
		draw_arc(centre, radius, 0.0, TAU, 56, ring, width)
		if icon != null:
			var side: float = radius * 1.05
			draw_texture_rect(icon, Rect2(centre - Vector2.ONE * side * 0.5, Vector2.ONE * side), false, ring)

	func _target_at(position_on_screen: Vector2) -> StringName:
		var metrics: Dictionary = _metrics()
		if layer_owner.open:
			var tiles: Dictionary = metrics["tiles"]
			var radius: float = metrics["tile_radius"]
			for id: StringName in tiles:
				var reach: float = radius * 0.8 if id == &"close" else (float(metrics["slider_icon_radius"]) if id == &"camera_reset" else radius)
				if (tiles[id] as Vector2).distance_to(position_on_screen) <= reach:
					return id
		if (metrics["gear_centre"] as Vector2).distance_to(position_on_screen) <= float(metrics["gear_radius"]):
			return &"gear"
		if _fullscreen_available and (metrics["fullscreen_centre"] as Vector2).distance_to(position_on_screen) <= float(metrics["gear_radius"]):
			return &"fullscreen"
		return &""

	func _activate(id: StringName) -> void:
		match id:
			&"gear", &"close":
				AudioRef.play(&"ui_tap")
				layer_owner.toggle()
			&"fullscreen":
				AudioRef.play(&"ui_tap")
				FullscreenToggle.toggle()
				queue_redraw.call_deferred()
			&"scheme_lock":
				AudioRef.play(&"ui_tap")
				SettingsRef.set_scheme(SettingsRef.SCHEME_LOCK_FIRE)
			&"scheme_aim":
				AudioRef.play(&"ui_tap")
				SettingsRef.set_scheme(SettingsRef.SCHEME_AIM_STICK)
			&"view_flat":
				AudioRef.play(&"ui_tap")
				SettingsRef.set_view(SettingsRef.VIEW_FLAT)
			&"view_depth":
				AudioRef.play(&"ui_tap")
				SettingsRef.set_view(SettingsRef.VIEW_DEPTH)
			&"camera_reset":
				AudioRef.play(&"ui_tap")
				SettingsRef.reset_camera()
			&"haptics":
				AudioRef.play(&"ui_on" if not SettingsRef.haptics_enabled() else &"ui_off")
				SettingsRef.set_haptics(not SettingsRef.haptics_enabled())
			&"sound":
				if SettingsRef.sound_enabled():
					AudioRef.play(&"ui_off")
				SettingsRef.set_sound(not SettingsRef.sound_enabled())
				if SettingsRef.sound_enabled():
					AudioRef.play(&"ui_on")

	func _metrics() -> Dictionary:
		var viewport: Viewport = get_viewport()
		var per_css: float = RestartUiScale.pixels_per_css(viewport)
		var insets: Vector4 = RestartUiScale.edge_insets(viewport)
		var screen: Vector2 = viewport.get_visible_rect().size
		var gear_radius: float = maxf(RestartUiScale.GEAR_DIAMETER_CSS_PX * 0.5 * per_css, SettingsLayer.MIN_RADIUS)
		var restart_radius: float = maxf(RestartButton.DIAMETER_CSS_PX * 0.5 * per_css, RestartButton.MIN_RADIUS)
		var row_bottom: float = insets.y + (SettingsLayer.HUD_ROW_CSS_PX + SettingsLayer.ROW_GAP_CSS_PX) * per_css
		var column: Dictionary = RestartUiScale.top_right_column(viewport, gear_radius, restart_radius, SettingsLayer.BORDER_GAP_CSS_PX * per_css, row_bottom)
		var gear_centre: Vector2 = column["gear"]
		var tile_radius: float = maxf(SettingsLayer.TILE_DIAMETER_CSS_PX * 0.5 * per_css, SettingsLayer.MIN_RADIUS)
		var gap: float = SettingsLayer.TILE_GAP_CSS_PX * per_css
		var middle: Vector2 = screen * 0.5
		var step: float = tile_radius * 2.0 + gap
		var tiles: Dictionary = {
			&"scheme_lock": middle + Vector2(-step * 1.5, -tile_radius * 0.4),
			&"scheme_aim": middle + Vector2(-step * 0.5, -tile_radius * 0.4),
			&"haptics": middle + Vector2(step * 0.5, -tile_radius * 0.4),
			&"sound": middle + Vector2(step * 1.5, -tile_radius * 0.4),
			&"view_flat": middle + Vector2(-step, tile_radius * 2.1),
			&"view_depth": middle + Vector2(step, tile_radius * 2.1),
			&"close": middle + Vector2(0.0, tile_radius * 2.1),
		}
		var sliders: Dictionary = {}
		var icon_radius: float = maxf(SettingsLayer.SLIDER_HIT_CSS_PX * 0.5 * per_css, SettingsLayer.MIN_RADIUS)
		if SettingsRef.view() == SettingsRef.VIEW_DEPTH:
			# The row sits below the tile rows, so no existing tile moves and the field above stays in view.
			var tiles_bottom: float = middle.y + tile_radius * 2.1 + tile_radius
			var row_y: float = (tiles_bottom + screen.y) * 0.5
			var track: float = SettingsLayer.SLIDER_TRACK_CSS_PX * per_css
			var hit_height: float = SettingsLayer.SLIDER_HIT_CSS_PX * per_css
			var group_gap: float = icon_radius * 2.0
			var lead: float = icon_radius * 2.0 + hit_height * 0.5 + 4.0
			var total: float = (lead + track) * 2.0 + group_gap + icon_radius * 2.0
			var x: float = middle.x - total * 0.5 + lead
			sliders[&"camera_pitch"] = Rect2(x, row_y - hit_height * 0.5, track, hit_height)
			x += track + group_gap + lead
			sliders[&"camera_zoom"] = Rect2(x, row_y - hit_height * 0.5, track, hit_height)
			tiles[&"camera_reset"] = Vector2(x + track + group_gap + icon_radius, row_y)
		# The fullscreen button sits left of the gear, level with it, so the right column keeps its order.
		var fullscreen_centre: Vector2 = gear_centre - Vector2(gear_radius * 2.0 + SettingsLayer.BORDER_GAP_CSS_PX * per_css, 0.0)
		return {"fullscreen_centre": fullscreen_centre, "gear_centre": gear_centre, "gear_radius": gear_radius, "tile_radius": tile_radius, "tiles": tiles, "sliders": sliders, "slider_icon_radius": icon_radius}
