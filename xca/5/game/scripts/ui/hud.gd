class_name Hud
extends CanvasLayer
## Icon-only match HUD with screen shake and a topple flash.
##
## Finds [code]RoundManager[/code], [code]Stack[/code] and [code]Character[/code]
## nodes by script class name, so it works in any scene order.
## It flashes and shakes on its own when the stack signals [code]toppled[/code].
## Other code can call [method flash_topple] or [method shake] through the
## [code]"hud"[/code] group.

## Group every HUD joins. Use [code]get_tree().call_group("hud", "shake")[/code].
const GROUP_HUD: StringName = &"hud"
## Group of the character the human steers.
const GROUP_HUMAN: StringName = &"human_controlled"
## Size of the icon in the middle of the stack ring, in viewport pixels.
const RING_ICON_PX: int = 64
## Smallest icon size in viewport pixels, used on large screens.
const MIN_ICON_PX: int = 40
## Gap in viewport pixels between the pip groups of the two teams.
const SCORE_GROUP_GAP: int = 28
## Largest icon size in viewport pixels.
const MAX_ICON_PX: int = 96
## Icon size on the physical screen in CSS pixels. It matches the 44 px touch target size.
const TOUCH_TARGET_CSS_PX: float = 44.0
## Coin and trophy size in viewport pixels.
const CENTER_ICON_PX: int = 112
## Countdown digit size in viewport pixels. White on a dark outline keeps the digit above 4.5:1 on any ground.
const COUNT_FONT_PX: int = 200
## Icons are drawn at this multiple of their size so phones stay sharp.
const RASTER_SCALE: int = 2
## Minimum gap between a HUD element and the screen edge, in viewport pixels.
const EDGE_MARGIN: float = 16.0
## Round wins needed to win the match.
const WIN_SCORE: int = 3
## Sandals in the stack.
const STACK_SIZE: int = 3
## Radius of the stack progress ring.
const RING_RADIUS: float = 72.0
## Radius of the ring around the human-controlled character.
const MARKER_RADIUS: float = 30.0
## Seconds between searches for missing nodes.
const POLL_INTERVAL: float = 0.25
## Seconds the coin spins.
const COIN_SPIN_TIME: float = 1.2
## Tint of an unfilled icon. It reads 3:1 on the bar so an empty pip is still visible.
const DIM_COLOR: Color = Color(1.0, 1.0, 1.0, 0.42)
## Teams in a match.
const TEAM_COUNT: int = 2
## Dark edge under the marker ring, so it separates from a red or blue body.
const MARKER_EDGE_COLOR: Color = Color(0.06, 0.09, 0.16)
## Phase names in contract order. Used when the round manager has no readable enum.
const DEFAULT_PHASES: Array[String] = ["COIN_FLIP", "TOPPLE", "SCATTER", "ROUND_END", "MATCH_END"]

## Textures for every HUD element. Swap this resource to reskin the HUD.
@export var icons: HudIconSet

var _round_manager: Node
var _stack: Node
var _human: Node2D
var _characters: Array[Node] = []
var _phase_names: Dictionary = {}
var _phase_name: String = ""
var _scores: Array[int] = [0, 0]
var _match_over: bool = false
var _throws_max: int = 0
var _poll_left: float = 0.0
var _icon_cache: Dictionary = {}
var _icon_px: int = MIN_ICON_PX
var _shake_tween: Tween
var _shake_camera: Camera2D
var _shake_camera_offset: Vector2 = Vector2.ZERO
var _shake_canvas_transform: Transform2D = Transform2D.IDENTITY
var _center_tween: Tween
var _shown_throws_max: int = -1
var _shown_throws_left: int = -1
var _shown_mati_total: int = -1
var _shown_mati_dead: int = -1
var _shown_scores: Array[int] = [-1, -1]
var _shown_role: String = ""
var _shown_human_team: int = -1
var _shown_throws_team: int = -1
var _tuning: Tuning
var _margin: MarginContainer
var _overlay: Overlay
var _score_rows: Array[HBoxContainer] = []
var _role_icon: TextureRect
var _throws_row: HBoxContainer
var _mati_row: HBoxContainer
var _center_icon: TextureRect
var _count_label: Label
var _count_tween: Tween
var _ring_icon: TextureRect
var _flash: ColorRect


func _ready() -> void:
	layer = 10
	if icons == null:
		push_error("Hud has no HudIconSet. Assign one to the icons property.")
		icons = HudIconSet.new()
	add_to_group(GROUP_HUD)
	_tuning = Tuning.load_default()
	_icon_px = _compute_icon_px()
	_build_ui()
	_apply_safe_area()
	get_viewport().size_changed.connect(_apply_safe_area)
	get_viewport().size_changed.connect(_on_viewport_resized)
	_discover()


func _process(delta: float) -> void:
	_poll_left -= delta
	if _poll_left <= 0.0:
		_poll_left = POLL_INTERVAL
		_discover()
	_refresh_human()
	_refresh_role()
	_refresh_scores()
	_refresh_throws()
	_refresh_mati()
	_refresh_overlay()


## Flashes the screen white and shakes it. Called when the stack topples.
func flash_topple() -> void:
	_flash.modulate.a = 0.55
	create_tween().tween_property(_flash, "modulate:a", 0.0, 0.3)
	shake(14.0, 0.35)


## Shakes the world for [param duration] seconds. [param strength] is in viewport pixels.
func shake(strength: float = 10.0, duration: float = 0.25) -> void:
	if _shake_tween != null and _shake_tween.is_valid():
		_shake_tween.kill()
		_restore_view()
	var viewport: Viewport = get_viewport()
	_shake_camera = viewport.get_camera_2d()
	if _shake_camera != null:
		_shake_camera_offset = _shake_camera.offset
	else:
		_shake_canvas_transform = viewport.canvas_transform
	_shake_tween = create_tween()
	_shake_tween.tween_method(_apply_shake.bind(strength), 1.0, 0.0, duration)
	_shake_tween.finished.connect(_restore_view)


func _build_ui() -> void:
	_overlay = Overlay.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)

	_margin = MarginContainer.new()
	_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_margin)

	var bar: HBoxContainer = HBoxContainer.new()
	bar.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_margin.add_child(bar)

	var left: HBoxContainer = _make_holder(BoxContainer.ALIGNMENT_BEGIN)
	var score_box: HBoxContainer = HBoxContainer.new()
	score_box.add_theme_constant_override("separation", SCORE_GROUP_GAP)
	score_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(score_box)
	for team: int in TEAM_COUNT:
		var row: HBoxContainer = HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for pip_index: int in WIN_SCORE:
			row.add_child(_make_icon_rect(icons.score_pip, _icon_px, DIM_COLOR))
		score_box.add_child(row)
		_score_rows.append(row)
	bar.add_child(left)

	var centre: HBoxContainer = HBoxContainer.new()
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_role_icon = _make_icon_rect(icons.role_attack, _icon_px, _team_color(_human_team()))
	centre.add_child(_role_icon)
	_throws_row = HBoxContainer.new()
	_throws_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.add_child(_throws_row)
	bar.add_child(centre)

	var right: HBoxContainer = _make_holder(BoxContainer.ALIGNMENT_END)
	_mati_row = HBoxContainer.new()
	_mati_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(_mati_row)
	bar.add_child(right)

	var centre_box: CenterContainer = CenterContainer.new()
	centre_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre_box)
	_ring_icon = _make_icon_rect(icons.stack_ring, RING_ICON_PX, DIM_COLOR)
	_ring_icon.visible = false
	centre_box.add_child(_ring_icon)
	_center_icon = _make_icon_rect(icons.coin_flip, CENTER_ICON_PX, Color.WHITE)
	_center_icon.pivot_offset = Vector2(CENTER_ICON_PX, CENTER_ICON_PX) * 0.5
	_center_icon.visible = false
	centre_box.add_child(_center_icon)
	_count_label = Label.new()
	_count_label.add_theme_font_size_override("font_size", COUNT_FONT_PX)
	_count_label.add_theme_color_override("font_color", Color.WHITE)
	_count_label.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.08))
	_count_label.add_theme_constant_override("outline_size", COUNT_FONT_PX / 6)
	_count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_count_label.pivot_offset = Vector2(COUNT_FONT_PX, COUNT_FONT_PX) * 0.35
	_count_label.visible = false
	centre_box.add_child(_count_label)

	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color.WHITE
	_flash.modulate.a = 0.0
	add_child(_flash)


func _make_holder(alignment: BoxContainer.AlignmentMode) -> HBoxContainer:
	var holder: HBoxContainer = HBoxContainer.new()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.alignment = alignment
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return holder


func _make_icon_rect(texture: Texture2D, size_px: int, tint: Color) -> TextureRect:
	var rect: TextureRect = TextureRect.new()
	rect.texture = _icon(texture, size_px)
	rect.custom_minimum_size = Vector2(size_px, size_px)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.modulate = tint
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


# The source SVGs import at 512 px. Downscaling them on the GPU shimmers, so each size is rasterised once here.
func _icon(source: Texture2D, size_px: int) -> Texture2D:
	if source == null:
		push_error("HudIconSet has an empty slot.")
		return null
	var key: String = "%d_%d" % [source.get_instance_id(), size_px]
	if _icon_cache.has(key):
		return _icon_cache[key]
	var image: Image = source.get_image()
	if image.is_compressed():
		image.decompress()
	image.fix_alpha_edges()
	var raster_px: int = size_px * RASTER_SCALE
	image.resize(raster_px, raster_px, Image.INTERPOLATE_LANCZOS)
	var texture: ImageTexture = ImageTexture.create_from_image(image)
	_icon_cache[key] = texture
	return texture


# The viewport is scaled to the window, so a phone shows 720 viewport pixels in about 390 CSS pixels.
func _compute_icon_px() -> int:
	var visible_height: float = get_viewport().get_visible_rect().size.y
	var css_height: float = float(DisplayServer.window_get_size().y)
	if OS.has_feature("web"):
		var inner: Variant = JavaScriptBridge.eval("window.innerHeight")
		if inner is float and inner > 0.0:
			css_height = inner
	if css_height <= 0.0:
		return MIN_ICON_PX
	return clampi(ceili(TOUCH_TARGET_CSS_PX * visible_height / css_height), MIN_ICON_PX, MAX_ICON_PX)


func _on_viewport_resized() -> void:
	var new_icon_px: int = _compute_icon_px()
	if new_icon_px == _icon_px:
		return
	_icon_px = new_icon_px
	for child: Node in get_children():
		child.queue_free()
		remove_child(child)
	_score_rows.clear()
	_shown_throws_max = -1
	_shown_throws_left = -1
	_shown_throws_team = -1
	_shown_mati_total = -1
	_shown_mati_dead = -1
	_shown_scores = [-1, -1]
	_shown_role = ""
	_shown_human_team = -1
	_build_ui()
	_apply_safe_area()


func _apply_safe_area() -> void:
	var inset: Vector4 = Vector4.ZERO
	if OS.has_feature("mobile") or OS.has_feature("web"):
		var safe: Rect2i = DisplayServer.get_display_safe_area()
		var screen: Vector2i = DisplayServer.screen_get_size()
		var window: Vector2i = DisplayServer.window_get_size()
		if safe.has_area() and window.y > 0 and screen.y > 0:
			var scale: float = get_viewport().get_visible_rect().size.y / float(window.y)
			inset = Vector4(
				safe.position.x,
				safe.position.y,
				screen.x - safe.end.x,
				screen.y - safe.end.y
			) * scale
	_margin.add_theme_constant_override("margin_left", ceili(maxf(EDGE_MARGIN, inset.x)))
	_margin.add_theme_constant_override("margin_top", ceili(maxf(EDGE_MARGIN, inset.y)))
	_margin.add_theme_constant_override("margin_right", ceili(maxf(EDGE_MARGIN, inset.z)))
	_margin.add_theme_constant_override("margin_bottom", ceili(maxf(EDGE_MARGIN, inset.w)))


func _discover() -> void:
	if not is_instance_valid(_round_manager):
		_round_manager = _find_node("RoundManager", &"hud_round_manager")
		if _round_manager != null:
			_connect_round_manager()
	if not is_instance_valid(_stack):
		_stack = _find_node("Stack", &"hud_stack")
		if _stack != null:
			_connect_stack()
	_characters.clear()
	_collect(get_tree().root, "Character", &"hud_character", _characters)


func _find_node(global_name: String, group_name: StringName) -> Node:
	var found: Array[Node] = []
	_collect(get_tree().root, global_name, group_name, found)
	return found[0] if not found.is_empty() else null


func _collect(node: Node, global_name: String, group_name: StringName, out: Array[Node]) -> void:
	if node != self and (node.is_in_group(group_name) or _script_class(node) == global_name):
		out.append(node)
	for child: Node in node.get_children():
		_collect(child, global_name, group_name, out)


func _script_class(node: Node) -> String:
	var script: Script = node.get_script()
	return script.get_global_name() if script != null else ""


func _connect_round_manager() -> void:
	_read_phase_names()
	if _round_manager.has_signal("phase_changed"):
		_round_manager.connect("phase_changed", _on_phase_changed)
	if _round_manager.has_signal("round_ended"):
		_round_manager.connect("round_ended", _on_round_ended)
	if _round_manager.has_signal("countdown_tick"):
		_round_manager.connect("countdown_tick", _on_countdown_tick)


func _connect_stack() -> void:
	if _stack.has_signal("toppled"):
		_stack.connect("toppled", flash_topple)


func _read_phase_names() -> void:
	_phase_names.clear()
	var script: Script = _round_manager.get_script()
	if script != null:
		for value: Variant in script.get_script_constant_map().values():
			if value is Dictionary and value.has("COIN_FLIP"):
				for key: Variant in value:
					_phase_names[value[key]] = String(key)
	if _phase_names.is_empty():
		for index: int in DEFAULT_PHASES.size():
			_phase_names[index] = DEFAULT_PHASES[index]


func _on_countdown_tick(step: int) -> void:
	if _count_tween != null and _count_tween.is_valid():
		_count_tween.kill()
	if step <= 0:
		_count_label.visible = false
		return
	_center_icon.visible = false
	_count_label.text = str(step)
	_count_label.scale = Vector2.ONE * 1.6
	_count_label.modulate.a = 1.0
	_count_label.visible = true
	_count_tween = create_tween()
	_count_tween.tween_property(_count_label, "scale", Vector2.ONE, 0.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_phase_changed(phase: Variant) -> void:
	_phase_name = _phase_names.get(phase, "")
	_stop_center_tween()
	if _phase_name != "COIN_FLIP" and _count_label != null:
		_count_label.visible = false
	match _phase_name:
		"COIN_FLIP":
			if _match_over:
				_scores = [0, 0]
				_match_over = false
			_play_coin_flip()
		"TOPPLE":
			_throws_max = 0
			_center_icon.visible = false
		"MATCH_END":
			_show_trophy()
		_:
			_center_icon.visible = false


func _on_round_ended(winner_team: int) -> void:
	if winner_team < 0 or winner_team >= _scores.size():
		return
	_scores[winner_team] = mini(_scores[winner_team] + 1, WIN_SCORE)
	if _scores[winner_team] >= WIN_SCORE:
		_match_over = true


func _refresh_human() -> void:
	if is_instance_valid(_human):
		return
	_human = null
	for node: Node in get_tree().get_nodes_in_group(GROUP_HUMAN):
		if node is Node2D:
			_human = node
			return


func _human_team() -> int:
	if is_instance_valid(_human):
		var team: Variant = _human.get("team")
		if team is int:
			return clampi(team, 0, TEAM_COUNT - 1)
	return 0


func _attacking_team() -> int:
	if is_instance_valid(_round_manager):
		var team: Variant = _round_manager.get("attacking_team")
		if team is int:
			return clampi(team, 0, TEAM_COUNT - 1)
	return 0


## Colour of [param team] seen from the human's side.
func _team_color(team: int) -> Color:
	return Character.color_for_team(team, get_tree(), _tuning)


func _refresh_role() -> void:
	var human_team: int = _human_team()
	var role_name: String = "attack" if _attacking_team() == human_team else "defend"
	if role_name == _shown_role and human_team == _shown_human_team:
		return
	_shown_role = role_name
	_shown_human_team = human_team
	_role_icon.texture = _icon(icons.role_attack if role_name == "attack" else icons.role_defend, _icon_px)
	_role_icon.modulate = _team_color(human_team)


func _refresh_scores() -> void:
	if _scores == _shown_scores:
		return
	_shown_scores = _scores.duplicate()
	for team: int in _score_rows.size():
		var pips: Array[Node] = _score_rows[team].get_children()
		for pip_index: int in pips.size():
			var pip: TextureRect = pips[pip_index]
			pip.modulate = _team_color(team) if pip_index < _scores[team] else DIM_COLOR


func _refresh_throws() -> void:
	var throws_left: int = 0
	if is_instance_valid(_round_manager):
		var value: Variant = _round_manager.get("throws_left")
		if value is int:
			throws_left = value
	if _phase_name == "TOPPLE":
		_throws_max = maxi(_throws_max, throws_left)
	if _throws_max != _shown_throws_max:
		_shown_throws_max = _throws_max
		_shown_throws_left = -1
		for child: Node in _throws_row.get_children():
			child.queue_free()
		for index: int in _throws_max:
			_throws_row.add_child(_make_icon_rect(icons.throw_sandal, _icon_px, Color.WHITE))
	var throwing_team: int = _attacking_team()
	if throws_left == _shown_throws_left and throwing_team == _shown_throws_team:
		return
	_shown_throws_left = throws_left
	_shown_throws_team = throwing_team
	var sandals: Array[Node] = _throws_row.get_children()
	for index: int in sandals.size():
		var sandal: TextureRect = sandals[index]
		sandal.modulate = _team_color(throwing_team) if index < throws_left else DIM_COLOR


func _refresh_mati() -> void:
	var attacking: int = _attacking_team()
	var total: int = 0
	var dead: int = 0
	for character: Node in _characters:
		if not is_instance_valid(character) or character.get("team") != attacking:
			continue
		total += 1
		if character.get("alive") == false:
			dead += 1
	if total == _shown_mati_total and dead == _shown_mati_dead:
		return
	if total != _shown_mati_total:
		for child: Node in _mati_row.get_children():
			child.queue_free()
		for index: int in total:
			_mati_row.add_child(_make_icon_rect(icons.tombstone, _icon_px, DIM_COLOR))
	_shown_mati_total = total
	_shown_mati_dead = dead
	var stones: Array[Node] = _mati_row.get_children()
	for index: int in stones.size():
		var stone: TextureRect = stones[index]
		stone.modulate = _team_color(attacking) if index < dead else DIM_COLOR


func _refresh_overlay() -> void:
	var viewport: Viewport = get_viewport()
	var placed: int = 0
	if is_instance_valid(_stack):
		var value: Variant = _stack.get("placed_count")
		if value is int:
			placed = value
	_overlay.ring_visible = _phase_name == "SCATTER"
	_ring_icon.visible = _overlay.ring_visible
	_ring_icon.modulate = DIM_COLOR.lerp(_team_color(_attacking_team()), _overlay.ring_fill)
	_overlay.ring_fill = clampf(float(placed) / float(STACK_SIZE), 0.0, 1.0)
	_overlay.ring_center = viewport.get_visible_rect().size * 0.5
	_overlay.ring_color = _team_color(_attacking_team())
	_overlay.marker_visible = is_instance_valid(_human)
	if _overlay.marker_visible:
		_overlay.marker_position = ViewProjection.to_screen(viewport, _human.global_position)
		_overlay.marker_color = _team_color(_human_team())
	_overlay.pulse = fmod(Time.get_ticks_msec() / 1000.0, 1.0)
	_overlay.queue_redraw()


func _play_coin_flip() -> void:
	_center_icon.texture = _icon(icons.coin_flip, CENTER_ICON_PX)
	_center_icon.modulate = Color.WHITE
	_center_icon.scale = Vector2.ONE
	_center_icon.visible = true
	_center_tween = create_tween()
	_center_tween.tween_method(_spin_coin, 0.0, 1.0, COIN_SPIN_TIME)
	_center_tween.tween_callback(_land_coin)
	_center_tween.tween_interval(0.6)
	_center_tween.tween_property(_center_icon, "modulate:a", 0.0, 0.25)


func _spin_coin(progress: float) -> void:
	_center_icon.scale = Vector2(cos(progress * TAU * 4.0), 1.0 + 0.25 * sin(progress * PI))


func _land_coin() -> void:
	_center_icon.scale = Vector2.ONE
	_center_icon.modulate = _team_color(_attacking_team())


func _show_trophy() -> void:
	var winner: int = 0 if _scores[0] >= _scores[1] else 1
	_center_icon.texture = _icon(icons.match_trophy, CENTER_ICON_PX)
	_center_icon.modulate = _team_color(winner)
	_center_icon.scale = Vector2.ONE * 0.2
	_center_icon.visible = true
	_center_tween = create_tween()
	_center_tween.tween_property(_center_icon, "scale", Vector2.ONE, 0.45) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _stop_center_tween() -> void:
	if _center_tween != null and _center_tween.is_valid():
		_center_tween.kill()


func _apply_shake(amount: float, strength: float) -> void:
	var offset: Vector2 = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * strength * amount
	if is_instance_valid(_shake_camera):
		_shake_camera.offset = _shake_camera_offset + offset
	else:
		var transform: Transform2D = _shake_canvas_transform
		transform.origin += offset
		get_viewport().canvas_transform = transform


func _restore_view() -> void:
	if is_instance_valid(_shake_camera):
		_shake_camera.offset = _shake_camera_offset
	else:
		get_viewport().canvas_transform = _shake_canvas_transform


## Draws the stack progress ring and the marker around the human-controlled character.
class Overlay extends Control:
	## Share of the stack rebuilt, from 0 to 1.
	var ring_fill: float = 0.0
	## True while the ring shows.
	var ring_visible: bool = false
	## Screen position of the ring centre.
	var ring_center: Vector2 = Vector2.ZERO
	## Fill colour of the ring.
	var ring_color: Color = Color.WHITE
	## True while a human-controlled character exists.
	var marker_visible: bool = false
	## Screen position of the marker.
	var marker_position: Vector2 = Vector2.ZERO
	## Colour of the marker.
	var marker_color: Color = Color.WHITE
	## Marker pulse, looping from 0 to 1.
	var pulse: float = 0.0

	func _draw() -> void:
		if ring_visible:
			draw_arc(ring_center, Hud.RING_RADIUS, 0.0, TAU, 64, Hud.DIM_COLOR, 10.0, true)
			if ring_fill > 0.0:
				draw_arc(ring_center, Hud.RING_RADIUS, -PI * 0.5, -PI * 0.5 + TAU * ring_fill, 64, ring_color, 10.0, true)
		if marker_visible:
			var radius: float = Hud.MARKER_RADIUS + 4.0 * sin(pulse * TAU)
			# The marker lies on the floor, so the tilted view shows it as a flattened ellipse.
			draw_set_transform(marker_position, 0.0, Vector2(1.0, ViewProjection.squash()))
			draw_arc(Vector2.ZERO, radius, 0.0, TAU, 40, Hud.MARKER_EDGE_COLOR, 11.0, true)
			draw_arc(Vector2.ZERO, radius, 0.0, TAU, 40, Color.WHITE, 6.0, true)
			draw_arc(Vector2.ZERO, radius, 0.0, TAU, 40, marker_color, 3.0, true)
