class_name RestartButton
extends Control
## Round icon button at the top right that restarts the match after a hold.
##
## A ring fills while a finger or the R key is held, so a stray tap cannot reset the match.
## The hold uses real time, so slow-motion and hit stop do not stretch it.

## Emitted when the hold completes.
signal confirmed

## Touch target diameter in CSS pixels. The 44 px minimum is met on every screen size.
const DIAMETER_CSS_PX: float = 52.0
## Smallest radius in viewport pixels, so the button stays usable on large screens.
const MIN_RADIUS: float = 22.0
## A held finger that moves farther than this many radii from the centre cancels the hold.
const CANCEL_RATIO: float = 1.6
## Fill behind the icon.
const BACKDROP_COLOR: Color = Color(0.06, 0.09, 0.16, 0.5)
## Height of the HUD top row in CSS pixels. The button sits below it so it never covers the mati tombstones.
const HUD_ROW_CSS_PX: float = 44.0
## Gap between the HUD top row and the button in CSS pixels.
const ROW_GAP_CSS_PX: float = 8.0
## Gap between the ring and the arena border in CSS pixels.
const ARENA_GAP_CSS_PX: float = 10.0

## Seconds the finger or the key must stay down.
@export_range(0.3, 3.0, 0.1, "suffix:s") var hold_time: float = 0.8
## Icon drawn on the button.
@export var icon: Texture2D = preload("res://assets/icons/restart_rotate.svg")
## Ring and icon colour while idle. Contrast on the arena floor is above 4.5:1.
@export var idle_color: Color = Color(1.0, 1.0, 1.0, 0.8)
## Colour of the filling ring.
@export var progress_color: Color = Color(1.0, 0.9, 0.55, 1.0)

## Share of the hold done, 0.0 to 1.0.
var progress: float = 0.0:
	set(value):
		if not is_equal_approx(progress, value):
			progress = value
			queue_redraw()
## Finger index that owns the press, or -1.
var finger_index: int = -1

var _radius: float = MIN_RADIUS
var _centre: Vector2 = Vector2.ZERO
var _touch_active: bool = false
var _key_active: bool = false
var _latched: bool = false
var _hold_started_msec: int = -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	get_viewport().size_changed.connect(layout)
	layout()


func _process(_delta: float) -> void:
	if not _touch_active and not _key_active:
		_latched = false
	var holding: bool = (_touch_active or _key_active) and not _latched and is_visible_in_tree()
	if not holding:
		_hold_started_msec = -1
		progress = 0.0
		return
	var now: int = Time.get_ticks_msec()
	if _hold_started_msec < 0:
		_hold_started_msec = now
	if _hold_started_msec == now:
		AudioRef.play(&"restart_hold")
	progress = clampf(float(now - _hold_started_msec) / (hold_time * 1000.0), 0.0, 1.0)
	if progress >= 1.0:
		_latched = true
		_hold_started_msec = -1
		progress = 0.0
		AudioRef.play(&"restart_confirm")
		confirmed.emit()


func _input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key != null:
		# Key events set the flag in both directions, so a release while hidden never leaves it stuck.
		if key.physical_keycode == KEY_R and not key.echo:
			_key_active = key.pressed and is_visible_in_tree()
		return
	if not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event
		if touch.pressed and finger_index == -1 and _centre.distance_to(touch.position) <= _radius:
			finger_index = touch.index
			_touch_active = true
			get_viewport().set_input_as_handled()
		elif not touch.pressed and touch.index == finger_index:
			finger_index = -1
			_touch_active = false
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event
		if drag.index == finger_index:
			if _centre.distance_to(drag.position) > _radius * CANCEL_RATIO:
				_touch_active = false
			get_viewport().set_input_as_handled()


func _draw() -> void:
	var stroke: float = maxf(4.0, _radius * 0.09)
	var tint: Color = idle_color.lerp(progress_color, progress)
	draw_circle(_centre, _radius, BACKDROP_COLOR)
	draw_arc(_centre, _radius, 0.0, TAU, 48, tint, stroke)
	if icon != null:
		var box: Rect2 = Rect2(_centre - Vector2.ONE * _radius * 0.55, Vector2.ONE * _radius * 1.1)
		draw_texture_rect(icon, box, false, tint)
	if progress > 0.0:
		draw_arc(_centre, _radius - stroke * 1.8, -PI * 0.5, -PI * 0.5 + TAU * progress, 48, progress_color, stroke * 1.5)


## Places the button in the top right corner, inside the safe area and below the HUD top row.
func layout() -> void:
	var viewport: Viewport = get_viewport()
	var per_css: float = RestartUiScale.pixels_per_css(viewport)
	_radius = maxf(DIAMETER_CSS_PX * 0.5 * per_css, MIN_RADIUS)
	var insets: Vector4 = RestartUiScale.edge_insets(viewport)
	var screen_size: Vector2 = viewport.get_visible_rect().size
	var row_bottom: float = insets.y + (HUD_ROW_CSS_PX + ROW_GAP_CSS_PX) * per_css
	# One column with the settings gear: the gear on top, this ring below, both inside the arena border.
	var gap: float = ARENA_GAP_CSS_PX * per_css
	var gear_radius: float = maxf(RestartUiScale.GEAR_DIAMETER_CSS_PX * 0.5 * per_css, SettingsLayer.MIN_RADIUS)
	var column: Dictionary = RestartUiScale.top_right_column(viewport, gear_radius, _radius, gap, row_bottom)
	_centre = column["restart"]
	queue_redraw()


## Centre of the round hit area in viewport pixels.
func hit_centre() -> Vector2:
	return _centre


## Radius of the round hit area in viewport pixels.
func hit_radius() -> float:
	return _radius
