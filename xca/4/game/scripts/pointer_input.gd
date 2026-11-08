class_name PointerInput
extends PlayerInput
## Mouse and touch fallback: one aim slot that follows the pointer and fires while pressed.
##
## Touch events win over the mouse events Godot emulates from them, so a finger is never counted twice.

## Emitted when a press or touch starts, with the point (0 to 1). A tap shorter than a frame still reports here, where the held state would miss it.
signal pressed(point: Vector2)

## Emitted when a press ends as a swipe. Horizontal and vertical are -1 for left or up and 1 for right or down, 0 for none.
signal swiped(horizontal: int, vertical: int)

## Shortest drag that counts as a swipe, as a share of the screen height. Resolution independent.
const SWIPE_MIN_SHARE: float = 0.06
## Longest press in seconds that counts as a swipe. A slow drag is not a swipe, so aiming by drag never steers.
const SWIPE_MAX_SECONDS: float = 0.5

var _press_start: Vector2 = Vector2.ZERO
var _press_time_msec: int = 0
var _pressing: bool = false
var _swiped_this_press: bool = false
var _aim_point: Vector2 = Vector2(0.5, 0.5)
var _aiming: bool = false
var _firing: bool = false


func _unhandled_input(event: InputEvent) -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	_track_swipe(event, viewport_size)
	if event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION:
		_aim_point = event.position / viewport_size
		_aiming = true
		tracking_ok = true
		_swipe_while_dragging(event.position, viewport_size)
	elif event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_aim_point = event.position / viewport_size
			_aiming = true
			_firing = event.pressed
			tracking_ok = true
			if event.pressed:
				pressed.emit(_aim_point)
	elif event is InputEventScreenTouch:
		_aim_point = event.position / viewport_size
		_aiming = event.pressed
		_firing = event.pressed
		tracking_ok = true
		if event.pressed:
			pressed.emit(_aim_point)
	elif event is InputEventScreenDrag:
		_aim_point = event.position / viewport_size
		_swipe_while_dragging(event.position, viewport_size)


func get_slot_count() -> int:
	return 1


func is_aiming(_slot: int) -> bool:
	return _aiming


func get_aim_point(_slot: int) -> Vector2:
	return _aim_point


func is_firing(_slot: int) -> bool:
	return _firing


## Steers the moment a fast drag passes the swipe distance, so the hero reacts while the finger is still moving instead of after it lifts.
func _swipe_while_dragging(position: Vector2, viewport_size: Vector2) -> void:
	if not _pressing or _swiped_this_press:
		return
	var seconds: float = float(Time.get_ticks_msec() - _press_time_msec) / 1000.0
	if seconds > SWIPE_MAX_SECONDS:
		return
	var drag: Vector2 = (position - _press_start) / viewport_size.y
	if drag.length() < SWIPE_MIN_SHARE:
		return
	_swiped_this_press = true
	_emit_swipe(drag)


func _emit_swipe(drag: Vector2) -> void:
	if absf(drag.x) >= absf(drag.y):
		swiped.emit(1 if drag.x > 0.0 else -1, 0)
	else:
		swiped.emit(0, 1 if drag.y > 0.0 else -1)


## Turns a short, fast press-drag-release into one swipe. Touch wins over emulated mouse, so a finger counts once.
func _track_swipe(event: InputEvent, viewport_size: Vector2) -> void:
	var is_touch: bool = event is InputEventScreenTouch
	var is_mouse: bool = event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION and event.button_index == MOUSE_BUTTON_LEFT
	if not is_touch and not is_mouse:
		return
	if event.pressed:
		_press_start = event.position
		_press_time_msec = Time.get_ticks_msec()
		_pressing = true
		_swiped_this_press = false
		return
	if not _pressing:
		return
	_pressing = false
	if _swiped_this_press:
		return
	var seconds: float = float(Time.get_ticks_msec() - _press_time_msec) / 1000.0
	var drag: Vector2 = (event.position - _press_start) / viewport_size.y
	if seconds > SWIPE_MAX_SECONDS or drag.length() < SWIPE_MIN_SHARE:
		return
	_emit_swipe(drag)
