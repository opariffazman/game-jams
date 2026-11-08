class_name HeroSelect
extends Control
## Picks a hero standing at the campfire. There is no card: the heroes themselves are the buttons.
##
## Each hero gets only an icon pill under the feet with its two weapons, so a child who cannot read yet still sees what each hero carries.
## A hand flicks left or right to move the highlight around the circle and holds an open palm to confirm. No camera is ever required.
## A tap highlights a hero and a second tap confirms. Mouse hover and the arrow keys only highlight, so a stray move never picks. Enter picks the highlighted hero.

## Emitted when the cursor or the keys move onto a hero, so the scene can preview that hero.
signal hovered(id: StringName)
## Emitted once when a hero is picked.
signal chosen(id: StringName)

## Seconds an open palm must stay up to confirm the highlighted hero.
const PALM_HOLD_SECONDS: float = 1.0
## Seconds after opening in which a palm cannot confirm. A palm held from the previous screen must also drop once before it counts.
const POSE_GRACE_SECONDS: float = 0.8
const PLATE_PADDING: Vector2 = Vector2(18.0, 6.0)
const PLATE_FONT_SIZE: int = 26
const PLATE_GAP: float = 6.0
const HINT_ICON: float = 44.0
const HINT_GAP: float = 18.0
## Smallest pick area in layout pixels. The layout scale keeps this above 48 CSS pixels.
const MIN_TARGET: Vector2 = Vector2(64.0, 110.0)
const TARGET_PADDING: float = 14.0
const ICON_SIZE: float = 52.0
const PILL_PADDING: float = 8.0
const PILL_GAP: float = 8.0
const DIVIDER_WIDTH: float = 3.0
const SCREEN_MARGIN: float = 8.0
const PILL_SEPARATION_PASSES: int = 12
## Space kept free below the pills for the control buttons, in pixels. The scene sets it.
const BOTTOM_MARGIN: float = 100.0
const RING_RADIUS: float = 46.0
const RING_WIDTH: float = 10.0
const PROGRESS_COLOR: Color = Color(0.4, 1.0, 0.4)
const FOCUS_COLOR: Color = Color(1.0, 1.0, 1.0)
const IDLE_BORDER_WIDTH: int = 3
const ACTIVE_BORDER_WIDTH: int = 6

## Hand input that moves the highlight by flick and confirms by palm hold.
@export var body_input: BodyInput

var bottom_reserve: float = BOTTOM_MARGIN
var compact: bool = false
## Pick areas of the heroes in this control's pixels, set by the scene every frame from the camp camera.
var targets: Dictionary[StringName, Rect2] = {}:
	set(value):
		targets = value
		_order_by_x()
		_place_pills()
## Id of the highlighted hero, or empty.
var hover_id: StringName = &""
## Share of the palm hold that has filled, from 0 to 1.
var palm_progress: float = 0.0
## Id of the picked hero, or empty.
var chosen_id: StringName = &""

var _mouse_id: StringName = &""
## The hero a tap, a key or a flick highlighted. A second tap on it confirms. Hover alone never sets it.
var _selected_id: StringName = &""
var _ordered: Array[StringName] = []
var _pills: Dictionary[StringName, Rect2] = {}
var _palm_seconds: float = 0.0
var _open_seconds: float = 0.0
var _palm_released: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	if body_input != null:
		body_input.flick_horizontal.connect(_on_flick)


func _process(delta: float) -> void:
	if not visible:
		return
	_open_seconds += delta
	var previous: StringName = hover_id
	if _mouse_id != &"":
		hover_id = _mouse_id
	if _camera_on() and hover_id == &"" and not _ordered.is_empty():
		_select(_ordered[0])
	if hover_id != previous and hover_id != &"":
		hovered.emit(hover_id)
	_hold_palm(delta)
	queue_redraw()


## Whether the hand controls are live: camera on and no browser error.
func is_camera_on() -> bool:
	return _camera_on()


func _camera_on() -> bool:
	return body_input != null and body_input.magic and body_input.camera_error.is_empty()


## An open palm held for PALM_HOLD_SECONDS confirms. The palm must drop once after opening, so a palm kept up from the last screen never confirms.
func _hold_palm(delta: float) -> void:
	var palm: bool = _camera_on() and body_input.is_aiming(0) and body_input.current_pose == BodyInput.Pose.PALM
	if not palm:
		_palm_released = true
		_palm_seconds = 0.0
	elif _palm_released and _open_seconds >= POSE_GRACE_SECONDS and hover_id != &"" and chosen_id == &"":
		_palm_seconds += delta
	palm_progress = clampf(_palm_seconds / PALM_HOLD_SECONDS, 0.0, 1.0)
	if _palm_seconds >= PALM_HOLD_SECONDS:
		_palm_seconds = 0.0
		_choose(hover_id)


## A flick moves the highlight one hero around the circle, wrapping at the ends.
func _on_flick(direction: int) -> void:
	if visible and chosen_id == &"":
		_step(direction)


func _step(direction: int) -> void:
	if _ordered.is_empty():
		return
	var at: int = _ordered.find(hover_id)
	var next: int = (0 if direction > 0 else _ordered.size() - 1) if at < 0 else posmod(at + direction, _ordered.size())
	_mouse_id = &""
	_select(_ordered[next])


func _select(id: StringName) -> void:
	_selected_id = id
	hover_id = id
	hovered.emit(id)


## Shows the select layer.
func open() -> void:
	chosen_id = &""
	hover_id = &""
	_mouse_id = &""
	_selected_id = &""
	_palm_seconds = 0.0
	palm_progress = 0.0
	_open_seconds = 0.0
	_palm_released = false
	visible = true


func close() -> void:
	visible = false


## Returns the pick areas in this control's pixels, for tests.
func get_card_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for id: StringName in _ordered:
		rects.append(get_pick_rect(id))
	return rects


## Returns the area that picks a hero: the body, padded, plus the icon pill under it.
## Returns the weapon pill of one hero. It is the visible handle, so tests click it.
func get_pill_rect(id: StringName) -> Rect2:
	return _pill_rect(id)


func get_pick_rect(id: StringName) -> Rect2:
	var body: Rect2 = _body_rect(id)
	return body.merge(_pill_rect(id)).grow(TARGET_PADDING * 0.5)


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or chosen_id != &"" or not event is InputEventKey or not event.pressed or event.echo or _ordered.is_empty():
		return
	var key: int = (event as InputEventKey).physical_keycode
	if key == KEY_LEFT or key == KEY_A or key == KEY_RIGHT or key == KEY_D:
		_step(-1 if key == KEY_LEFT or key == KEY_A else 1)
		get_viewport().set_input_as_handled()
	elif key == KEY_ENTER or key == KEY_KP_ENTER or key == KEY_SPACE:
		if hover_id != &"":
			_choose(hover_id)
			get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse_id = _target_at((event as InputEventMouseMotion).position)
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var id: StringName = _target_at((event as InputEventMouseButton).position)
		if id == &"":
			return
		_mouse_id = id
		if id == _selected_id:
			_choose(id)
		else:
			_select(id)


func _choose(id: StringName) -> void:
	if chosen_id != &"" or id == &"":
		return
	chosen_id = id
	hover_id = id
	chosen.emit(id)


## Heroes sorted left to right on screen, so the arrow keys move the way the eye expects while the camera circles.
func _order_by_x() -> void:
	_ordered.clear()
	for id: StringName in targets:
		_ordered.append(id)
	_ordered.sort_custom(func(a: StringName, b: StringName) -> bool: return targets[a].get_center().x < targets[b].get_center().x)


func _body_rect(id: StringName) -> Rect2:
	var rect: Rect2 = targets.get(id, Rect2())
	var centre: Vector2 = rect.get_center()
	var grown: Vector2 = Vector2(maxf(rect.size.x, MIN_TARGET.x), maxf(rect.size.y, MIN_TARGET.y))
	return Rect2(centre - grown * 0.5, grown)


func _pill_size() -> Vector2:
	return Vector2(ICON_SIZE * 2.0 + PILL_PADDING * 3.0 + DIVIDER_WIDTH, ICON_SIZE + PILL_PADDING * 2.0)


func _pill_rect(id: StringName) -> Rect2:
	return _pills.get(id, Rect2(Vector2.ZERO, _pill_size()))


## Puts each pill under its hero, then pushes overlapping pills apart sideways, so a hero behind another keeps a readable pill.
func _place_pills() -> void:
	_pills.clear()
	var pill: Vector2 = _pill_size()
	var max_left: float = maxf(size.x - pill.x - SCREEN_MARGIN, SCREEN_MARGIN)
	for id: StringName in _ordered:
		var body: Rect2 = _body_rect(id)
		var top: float = minf(body.end.y + PILL_GAP, maxf(size.y - maxf(bottom_reserve, BOTTOM_MARGIN) - pill.y, SCREEN_MARGIN))
		_pills[id] = Rect2(Vector2(clampf(body.get_center().x - pill.x * 0.5, SCREEN_MARGIN, max_left), top), pill)
	var stack_vertically: bool = size.x < (pill.x + PILL_GAP) * _ordered.size() + SCREEN_MARGIN * 2.0
	var max_top: float = maxf(size.y - maxf(bottom_reserve, BOTTOM_MARGIN) - pill.y, SCREEN_MARGIN)
	for pass_index: int in PILL_SEPARATION_PASSES:
		var moved: bool = false
		for first: int in _ordered.size():
			for second: int in range(first + 1, _ordered.size()):
				var a: Rect2 = _pills[_ordered[first]]
				var b: Rect2 = _pills[_ordered[second]]
				if not a.grow(-1.0).intersects(b.grow(-1.0)):
					continue
				if stack_vertically:
					var lift: float = (minf(a.end.y, b.end.y) - maxf(a.position.y, b.position.y) + PILL_GAP) * 0.5
					var upper: float = 1.0 if a.get_center().y <= b.get_center().y else -1.0
					a.position.y = clampf(a.position.y - lift * upper, SCREEN_MARGIN, max_top)
					b.position.y = clampf(b.position.y + lift * upper, SCREEN_MARGIN, max_top)
					_pills[_ordered[first]] = a
					_pills[_ordered[second]] = b
					moved = true
					continue
				var push: float = (minf(a.end.x, b.end.x) - maxf(a.position.x, b.position.x) + PILL_GAP) * 0.5
				var direction: float = 1.0 if a.get_center().x <= b.get_center().x else -1.0
				a.position.x = clampf(a.position.x - push * direction, SCREEN_MARGIN, max_left)
				b.position.x = clampf(b.position.x + push * direction, SCREEN_MARGIN, max_left)
				_pills[_ordered[first]] = a
				_pills[_ordered[second]] = b
				moved = true
		if not moved:
			break


## The hero whose pick area holds the point. A pill draws over the bodies, so it wins. Between bodies, the nearest hero centre wins.
func _target_at(point: Vector2) -> StringName:
	for id: StringName in _ordered:
		if _pill_rect(id).has_point(point):
			return id
	var best: StringName = &""
	var best_distance: float = INF
	for id: StringName in _ordered:
		if not get_pick_rect(id).has_point(point):
			continue
		var distance: float = point.distance_squared_to(_body_rect(id).get_center())
		if distance < best_distance:
			best_distance = distance
			best = id
	return best


func _draw() -> void:
	for id: StringName in _ordered:
		_draw_hero(id)
	if hover_id != &"" and _pills.has(hover_id):
		_draw_plate(hover_id)
	if _camera_on():
		_draw_hint()


## The name plate sits under the pill, or above the head when the pill leaves no room.
func _plate_rect(id: StringName) -> Rect2:
	var width: float = UiKit.font().get_string_size(String(HeroTable.get_spec(id)["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, PLATE_FONT_SIZE).x + PLATE_PADDING.x * 2.0
	var height: float = PLATE_FONT_SIZE + PLATE_PADDING.y * 2.0
	var pill: Rect2 = _pill_rect(id)
	var left: float = clampf(pill.get_center().x - width * 0.5, SCREEN_MARGIN, maxf(size.x - width - SCREEN_MARGIN, SCREEN_MARGIN))
	var below: float = pill.end.y + PLATE_GAP
	if below + height <= size.y - bottom_reserve:
		return Rect2(left, below, width, height)
	return Rect2(left, maxf(_body_rect(id).position.y - height - PLATE_GAP, SCREEN_MARGIN), width, height)


## Draws a pill. The body stays clear, because the 3D scene shows the highlight as a ground ring and the plate comes later.
func _draw_hero(id: StringName) -> void:
	var active: bool = id == hover_id
	var spec: Dictionary = HeroTable.get_spec(id)
	var accent: Color = Color(spec["accent"])
	var pill: Rect2 = _pill_rect(id)
	var border: Color = FOCUS_COLOR if active else accent
	draw_style_box(UiKit.brush(UiKit.PANEL_SOLID if not active else Color(0.18, 0.1, 0.32), border, 0.0, hash(id) % 7, false), pill)
	var loadout: Array[StringName] = HeroTable.loadout(id)
	for slot: int in loadout.size():
		var weapon: Dictionary = HeroTable.weapon_by_id(loadout[slot])
		var left: float = pill.position.x + PILL_PADDING + slot * (ICON_SIZE + PILL_PADDING + DIVIDER_WIDTH)
		draw_texture_rect(UiKit.icon(String(weapon["id"])), Rect2(left, pill.position.y + PILL_PADDING, ICON_SIZE, ICON_SIZE), false, Color(weapon["accent"]))
	draw_rect(Rect2(pill.position.x + pill.size.x * 0.5 - DIVIDER_WIDTH * 0.5, pill.position.y + PILL_PADDING, DIVIDER_WIDTH, ICON_SIZE), Color(1, 1, 1, 0.35))


## Drawn after every pill, so a neighbour never covers the name. The label has a dark outline instead of a streaky fill, which keeps it readable on the fire glow.
func _draw_plate(id: StringName) -> void:
	var plate: Rect2 = _plate_rect(id)
	draw_style_box(UiKit.brush(Color(0.12, 0.06, 0.24, 0.9), FOCUS_COLOR, 0.0, hash(id) % 5, false), plate)
	var font: Font = UiKit.font()
	var text: String = String(HeroTable.get_spec(id)["name"])
	var at := Vector2(plate.get_center().x - font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, PLATE_FONT_SIZE).x * 0.5, plate.position.y + PLATE_PADDING.y + font.get_ascent(PLATE_FONT_SIZE))
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, PLATE_FONT_SIZE, 8, Color(0.05, 0.02, 0.12))
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, PLATE_FONT_SIZE, FOCUS_COLOR)
	if palm_progress > 0.0 and chosen_id == &"":
		var ring_centre := Vector2(plate.end.x + RING_RADIUS * 0.6 + 12.0, plate.get_center().y)
		draw_arc(ring_centre, RING_RADIUS * 0.6, 0.0, TAU, 40, Color(0.0, 0.0, 0.0, 0.7), RING_WIDTH + 4.0)
		draw_arc(ring_centre, RING_RADIUS * 0.6, -PI * 0.5, -PI * 0.5 + TAU * palm_progress, 40, PROGRESS_COLOR, RING_WIDTH)
	if id == chosen_id:
		draw_texture_rect(UiKit.icon("check"), Rect2(plate.end.x + 8.0, plate.position.y - 4.0, 44.0, 44.0), false, PROGRESS_COLOR)


## Two wordless gesture icons at the top: flick arrows and an open palm. They show only while the camera is on.
func _draw_hint() -> void:
	var group_width: float = HINT_ICON * 3.0 + HINT_GAP * 2.0
	var top: float = SCREEN_MARGIN + 4.0
	var left: float = size.x * 0.5 - group_width * 0.5
	draw_style_box(UiKit.brush(Color(0.05, 0.02, 0.12, 0.5), Color(1, 1, 1, 0.0), 0.0, 3, false), Rect2(left - 14.0, top - 8.0, group_width + 28.0, HINT_ICON + 16.0))
	var mid: float = top + HINT_ICON * 0.5
	for index: int in 2:
		var side: float = -1.0 if index == 0 else 1.0
		var cx: float = left + HINT_ICON * 0.5 + index * (HINT_ICON + HINT_GAP)
		draw_colored_polygon(PackedVector2Array([
			Vector2(cx + side * HINT_ICON * 0.4, mid),
			Vector2(cx - side * HINT_ICON * 0.2, mid - HINT_ICON * 0.38),
			Vector2(cx - side * HINT_ICON * 0.2, mid + HINT_ICON * 0.38)]), FOCUS_COLOR)
	var palm_centre := Vector2(left + HINT_ICON * 2.5 + HINT_GAP * 2.0, mid + HINT_ICON * 0.12)
	draw_circle(palm_centre, HINT_ICON * 0.26, FOCUS_COLOR)
	for finger: int in 5:
		var angle: float = deg_to_rad(-90.0 + (finger - 2) * 24.0)
		var direction := Vector2(cos(angle), sin(angle))
		draw_line(palm_centre + direction * HINT_ICON * 0.2, palm_centre + direction * HINT_ICON * 0.5, FOCUS_COLOR, 5.0, true)
