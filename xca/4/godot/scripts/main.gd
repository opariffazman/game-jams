class_name Main
extends Node3D
## Rails prototype scene: wires input, course, waves, effects and the HUD together.

## Seconds the FPS benchmark averages over.
const BENCHMARK_SECONDS: float = 5.0
## Minimum button size in pixels for touch.
## Every this many chained kills play the milestone sound instead of the tick.
const COMBO_MILESTONE: int = 5
const BUTTON_MIN_SIZE: Vector2 = Vector2(150.0, 64.0)
## Starting 3D render scale, chosen from the Spike B tablet run.
const DEFAULT_3D_SCALE: float = 0.75
## Seconds between HUD text rebuilds.
const HUD_INTERVAL: float = 0.25
## HUD font size in pixels.
const HUD_FONT_SIZE: int = 20
## Message font size in pixels.
const MESSAGE_FONT_SIZE: int = 56
## Pixels the message sits above the screen centre, so it never covers the hero.
const MESSAGE_RISE: float = 120.0
## Seconds the picked hero poses before the ride starts.
const PICK_POSE_SECONDS: float = 1.5
## Seconds between the idle waves while the hero waits on the intro screens.
const GREET_INTERVAL: float = 6.0
## Where the intro camera sits and looks, in world metres with the hero at the origin, per screen. Index 0 is the camera, index 1 the look target. The hero stands in the part of the frame the prompts leave free.
const FRAME_INTRO: Array[Vector3] = [Vector3(0.0, 1.9, 5.2), Vector3(0.0, 1.55, 0.0)]
const FRAME_SELECT: Array[Vector3] = [Vector3(0.0, 2.6, 9.5), Vector3(0.0, 0.2, 0.0)]
## How fast the intro camera eases between screens.
const FRAME_FOLLOW_RATE: float = 4.0
const TITLE_FONT_SIZE: int = 100
const START_BUTTON_SIZE: Vector2 = Vector2(300.0, 72.0)
const START_BUTTON_GAP: float = 40.0
## Offset of the start buttons below the top edge in pixels, under the title.
const START_BUTTON_MARGIN: float = 20.0
## Pixels from the bottom edge to the camera notice, which sits above the start buttons.
const CAMERA_NOTICE_BOTTOM: float = 110.0
const CAMERA_NOTICE_BOTTOM_PORTRAIT: float = 190.0
const CAMERA_NOTICE_WIDTH: float = 300.0
const START_FONT_SIZE: int = 34
const START_ICON_SIZE: int = 52
const CONTROLS_MARGIN: float = 8.0
const CONTROLS_GAP: float = 4.0
## Height of the hologram preview in the page corner, in CSS pixels. Keep equal to the #holo height in web/inject.py.
const HOLOGRAM_CSS_HEIGHT: float = 105.0
const MENU_BUTTON_SIZE: Vector2 = Vector2(68.0, 68.0)

enum Flow { START, SELECT, PICKED, PLAY }

@onready var _audio: AudioBus = AudioBus.new()
@onready var _course: RailsCourse = $Course
@onready var _hero: RailsHero = $Hero
@onready var _pool: ZombiePool = $ZombiePool
@onready var _confetti: ConfettiPool = $Confetti
@onready var _director: RailsDirector = $Director
@onready var _shooter: Shooter = $Shooter
@onready var _juice: Juice = $Juice
@onready var _weapon_hud: WeaponHud = $Hud/WeaponHud
var _pickups: Pickups = Pickups.new()
@onready var _camera: Camera3D = $Camera3D
@onready var _body_input: BodyInput = $BodyInput
@onready var _pointer_input: PointerInput = $PointerInput
@onready var _reticle: AimReticle = $Hud/AimReticle
@onready var _hearts: HeartsDisplay = $Hud/Hearts
@onready var _message: Label = $Hud/Message
@onready var _hud_label: Label = $Hud/Info
@onready var _controls: GridContainer = $Hud/Controls
@onready var _start_overlay: Control = $Hud/StartOverlay

var _hero_select: HeroSelect
var _camp: CampScene = CampScene.new()
var _fog_before_camp: bool = true
var _hand_guide: HandGuide
var _station: ScrubStation
var _flow: Flow = Flow.START
var _frame: Array[Vector3] = FRAME_INTRO.duplicate()
var _intro_position: Vector3 = FRAME_INTRO[0]
var _intro_look: Vector3 = FRAME_INTRO[1]
var _greet_timer: float = 0.0
var _pick_timer: float = 0.0
var _picked_id: StringName = HeroTable.DEFAULT_ID
var _change_hero_button: Button
var _last_reticle: Vector2 = Vector2.ZERO
var _step_window: Array[float] = []
var _step_window_time: float = 0.0
var _was_magic: bool = false
var _debug_visible: bool = false
var _debug_only_buttons: Array[Button] = []
var _magic_button: Button
var _sound_button: Button
var _message_box: PanelContainer
var _message_icon: TextureRect
var _menu_button: Button
var _menu_open: bool = false
var _lanes_button: Button
var _steer_button: Button
var _start_buttons: BoxContainer
var _credits: CreditsScreen
var _game_over: GameOverScreen
var _run_zombies: int = 0
var _run_seconds: float = 0.0
var _run_weapon_seconds: Dictionary[StringName, float] = {}
var _run_base_shots: int = 0
var _run_base_hits: int = 0
var _run_base_pickups: int = 0
var _camera_notice: PanelContainer
var _start_title: TitleLogo
var _shake_button: Button
var _hud_timer: float = 0.0
var _benchmark_log: String = "-"
var _benchmark_running: bool = false
var _benchmark_elapsed: float = 0.0
var _benchmark_frames: int = 0


func _ready() -> void:
	var inputs: Array[PlayerInput] = [_body_input, _pointer_input]
	_pool.camera = _camera
	_director.course = _course
	_director.hero = _hero
	_director.pool = _pool
	_director.camera = _camera
	_shooter.pool = _pool
	_shooter.hero = _hero
	_shooter.director = _director
	_juice.pool = _pool
	_juice.director = _director
	_weapon_hud.shooter = _shooter
	add_child(_pickups)
	_pickups.director = _director
	_pickups.shooter = _shooter
	_pickups.collected.connect(_on_pickup_collected)
	_reticle.inputs = inputs
	add_child(_audio)
	_wire_audio()
	var hand_guide: HandGuide = HandGuide.new()
	hand_guide.body_input = _body_input
	_hand_guide = hand_guide
	$Hud.add_child(hand_guide)
	_hero_select = HeroSelect.new()
	_hero_select.body_input = _body_input
	_hero_select.hovered.connect(_on_hero_hovered)
	add_child(_camp)
	_hero_select.chosen.connect(_on_hero_chosen)
	$Hud.add_child(_hero_select)
	$Hud.move_child(_hero_select, _reticle.get_index())
	_build_station()
	$Hud.move_child(_start_overlay, -1)
	_pool.zombie_defeated.connect(_confetti.burst)
	_pool.zombie_defeated.connect(func(_at: Vector3) -> void: _run_zombies += 1)
	_director.game_over.connect(_on_game_over)
	_director.hearts_changed.connect(func(hearts: int) -> void: _hearts.hearts = hearts)
	_director.message_changed.connect(func(text: String) -> void:
		_message.text = text
		if not text.is_empty():
			_show_message_icon(text))
	_style_label(_hud_label, HUD_FONT_SIZE)
	_style_label(_message, MESSAGE_FONT_SIZE)
	_juice.combo_changed.connect(func(count: int) -> void: _weapon_hud.combo = count)
	_build_buttons()
	_restore_steer_mode()
	_body_input.palm_triggered.connect(func(_slot: int) -> void: _confirm_by_pose())
	_body_input.fist_triggered.connect(func(_slot: int) -> void: _confirm_by_pose())
	_body_input.flick_horizontal.connect(_on_steer_input)
	_body_input.flick_vertical.connect(_on_weapon_input)
	_pointer_input.swiped.connect(func(horizontal: int, vertical: int) -> void:
		if horizontal != 0:
			_on_steer_input(horizontal)
		if vertical != 0:
			_on_weapon_input(vertical))
	_hero.set_hero(_restore_hero_id())
	_build_credits()
	_build_game_over()
	_enter_flow(Flow.SELECT)
	get_viewport().msaa_3d = Viewport.MSAA_DISABLED
	get_viewport().scaling_3d_scale = DEFAULT_3D_SCALE


func _process(delta: float) -> void:
	_fit_layout()
	_body_input.audio_plays = _audio.total_plays()
	_body_input.audio_layers = _audio.layer_report()
	_update_flow(delta)
	_track_run_time(delta)
	if _pool.get_active_count() > 0 and _shooter.active:
		_audio.play_groan()
	var playing: bool = _flow == Flow.PLAY and _director.phase != RailsDirector.Phase.GAME_OVER
	_hud_label.visible = _debug_visible
	_menu_button.visible = playing
	_controls.visible = playing and _menu_open
	_hearts.visible = playing
	_weapon_hud.visible = playing
	_station.available = playing
	_message_box.visible = playing and not _message.text.is_empty()
	_reticle.visible = not playing
	_camera_notice.visible = _flow == Flow.SELECT and not _body_input.camera_error.is_empty()
	_steer_by_slide()
	if _body_input.magic != _was_magic:
		_was_magic = _body_input.magic
		_set_toggle(_magic_button, _was_magic, "palm", "times")
	if _benchmark_running:
		_advance_benchmark(delta)
	_measure_reticle_step(delta)
	_body_input.shots_fired = _shooter.shots_fired
	_body_input.shots_hit = _shooter.shots_hit
	_body_input.zombies_active = _pool.get_active_count()
	_body_input.assist_locked = false
	_body_input.reticle_point = _body_input.get_aim_point(0)
	# Rebuilding and re-laying-out the text every frame is costly on a tablet, and the numbers are unreadable at that rate anyway.
	_hud_timer -= delta
	if _hud_timer <= 0.0:
		_hud_timer = HUD_INTERVAL
		_hud_label.text = _hud_text(delta)
		_publish_pickup_state()
		_publish_ui_rects()
		_poll_test_command()


## Publishes every visible button rectangle in CSS pixels, so the portrait test can check target size and overlap.
func _publish_ui_rects() -> void:
	if not OS.has_feature("web"):
		return
	var to_css: Vector2 = Vector2(get_window().size) / Vector2(get_window().content_scale_size) / maxf(DisplayServer.screen_get_scale(), 1.0)
	var rects: Array = []
	var controls: Array[Node] = $Hud.find_children("*", "Button", true, false)
	for node: Node in controls:
		var button: Button = node as Button
		if button.is_visible_in_tree():
			var rect: Rect2 = button.get_global_rect()
			rects.append([button.text if not button.text.is_empty() else button.tooltip_text, rect.position.x * to_css.x, rect.position.y * to_css.y, rect.size.x * to_css.x, rect.size.y * to_css.y])
	if _camera_notice.is_visible_in_tree():
		var notice: Rect2 = _camera_notice.get_global_rect()
		rects.append(["CameraNotice", notice.position.x * to_css.x, notice.position.y * to_css.y, notice.size.x * to_css.x, notice.size.y * to_css.y])
	if _hero_select.visible:
		for id: StringName in HeroTable.HEROES.map(func(spec: Dictionary) -> StringName: return spec["id"]):
			if not _hero_select.targets.has(id):
				continue
			var card: Rect2 = _hero_select.get_pill_rect(id)
			rects.append(["card:%s" % id, card.position.x * to_css.x, card.position.y * to_css.y, card.size.x * to_css.x, card.size.y * to_css.y])
	JavaScriptBridge.eval("window.railsBridge.godotUiRects=%s" % JSON.stringify(rects))


## Records how far the drawn reticle moves per frame in pixels. Jerky aim shows as a high max against the mean.
func _measure_reticle_step(delta: float) -> void:
	if not _body_input.is_aiming(0):
		_step_window.clear()
		_last_reticle = Vector2.ZERO
		return
	var point: Vector2 = _body_input.get_aim_point(0) * get_viewport().get_visible_rect().size
	if _last_reticle != Vector2.ZERO:
		_step_window.append(point.distance_to(_last_reticle))
	_last_reticle = point
	_step_window_time += delta
	if _step_window_time < 1.0 or _step_window.is_empty():
		return
	_step_window_time = 0.0
	var total: float = 0.0
	for step_size: float in _step_window:
		total += step_size
	_body_input.step_max = _step_window.max()
	_body_input.step_mean = total / _step_window.size()
	_step_window.clear()


func _advance_benchmark(delta: float) -> void:
	_benchmark_elapsed += delta
	_benchmark_frames += 1
	if _benchmark_elapsed < BENCHMARK_SECONDS:
		return
	_benchmark_log = "%.1f fps avg / %ds, scale %.2f" % [
		_benchmark_frames / _benchmark_elapsed, int(BENCHMARK_SECONDS), get_viewport().scaling_3d_scale]
	_benchmark_running = false
	if OS.has_feature("web"):
		JavaScriptBridge.eval("console.log(%s)" % JSON.stringify("BENCH " + _benchmark_log))
	print("BENCH ", _benchmark_log)


func _hud_text(delta: float) -> String:
	var accuracy: String = "-" if _shooter.shots_fired == 0 else "%d%%" % (100 * _shooter.shots_hit / _shooter.shots_fired)
	return "FPS %d (%.0f ms)  Zombies %d/%d  Scale %.2f\n%s  Hero %s\nHands %d  Track %s  Shots %d  Hit %s  Flicks %d  Best chain %d\nBench: %s" % [
		Engine.get_frames_per_second(), delta * 1000.0, _pool.get_active_count(), _pool.get_capacity(),
		get_viewport().scaling_3d_scale, _director.get_status_text(), _hero.get_current_clip(),
		_body_input.hand_count, "yes" if _body_input.tracking_ok else "LOST", _shooter.shots_fired, accuracy, _body_input.flicks_received, _juice.best_combo,
		_benchmark_log + (" (running...)" if _benchmark_running else "")]


## Builds the calm station that follows each cleared wave. It pauses the run while the weapon is open.
func _build_station() -> void:
	_station = ScrubStation.new()
	_station.shooter = _shooter
	_station.hero = _hero
	_station.audio = _audio
	_station.body_input = _body_input
	_station.hud = $Hud
	add_child(_station)
	_station.build()
	_director.wave_cleared.connect(_station.offer)


## Moves between the intro screens: start, hero select, the pick pose, then play.
func _enter_flow(next: Flow) -> void:
	_flow = next
	_menu_open = false
	_body_input.flow = String(Flow.keys()[next]).to_lower()
	_start_overlay.visible = next == Flow.SELECT
	_hand_guide.panel_enabled = next == Flow.PLAY
	match next:
		Flow.START:
			_frame = FRAME_INTRO.duplicate()
			_shooter.active = false
			_hero_select.close()
			_close_camp()
		Flow.SELECT:
			_frame = FRAME_SELECT.duplicate()
			_shooter.active = false
			_open_camp()
			_hero_select.open()
		Flow.PICKED:
			_pick_timer = PICK_POSE_SECONDS
		Flow.PLAY:
			_hero_select.close()
			_close_camp()
	if next != Flow.PLAY:
		_greet_timer = 0.0
	_audio.set_scene(&"run" if next == Flow.PLAY else &"menu")


func _update_flow(delta: float) -> void:
	_body_input.hero_id = String(_hero.get_spec()["id"])
	_body_input.hearts = _director.hearts
	_body_input.lane = _director.lane
	_body_input.weapon_id = String(_shooter.get_weapon()["id"])
	_body_input.run_distance = _director.distance
	_body_input.combo = _juice.combo
	if _flow == Flow.PLAY:
		return
	_director.fit_camera()
	_hero.global_position = Vector3.ZERO
	_hero.rotation.y = 0.0
	var in_camp: bool = _camp.is_open()
	_hero.visible = not in_camp
	if in_camp:
		var screen: Vector2 = get_viewport().get_visible_rect().size
		_camp.update(delta, _camera, screen.y > screen.x)
		_hero_select.targets = _camp.screen_targets(_camera)
	else:
		var follow: float = 1.0 - exp(-FRAME_FOLLOW_RATE * delta)
		_intro_position = _intro_position.lerp(_frame[0], follow)
		_intro_look = _intro_look.lerp(_frame[1], follow)
		_camera.global_position = _intro_position
		_camera.look_at(_intro_look)
	_greet_timer -= delta
	if _greet_timer <= 0.0 and _flow != Flow.PICKED and not in_camp:
		_greet_timer = GREET_INTERVAL
		_hero.celebrate()
	if _flow == Flow.PICKED:
		_pick_timer -= delta
		if _pick_timer <= 0.0:
			_start_game()


## Shows the campfire with all heroes. The street hero hides, because the camp has its own models.
func _open_camp() -> void:
	var environment: Environment = $WorldEnvironment.environment
	_fog_before_camp = environment.fog_enabled
	environment.fog_enabled = false
	_camp.open()
	_hero.visible = false


func _close_camp() -> void:
	if not _camp.is_open():
		return
	_camp.close()
	var environment: Environment = $WorldEnvironment.environment
	environment.fog_enabled = _fog_before_camp
	_hero.visible = true


func _on_hero_hovered(id: StringName) -> void:
	_hero.set_hero(id)
	_camp.highlight(id)


func _on_hero_chosen(id: StringName) -> void:
	_unlock_from_tap()
	_camp.react(id, &"Yes")
	_picked_id = id
	if OS.has_feature("web"):
		JavaScriptBridge.eval("try{localStorage.setItem('railsHero','%s')}catch(e){}" % String(id))
	_hero.set_hero(id)
	_enter_flow(Flow.PICKED)


## Gives the hero its hearts and its starting loadout, then starts the run.
func _start_game() -> void:
	var spec: Dictionary = HeroTable.get_spec(_picked_id)
	_shooter.set_loadout(HeroTable.loadout(_picked_id))
	_shooter.grime.reset()
	_director.max_hearts = int(spec["hearts"])
	_hearts.max_hearts = int(spec["hearts"])
	_juice.reset()
	_reset_run_stats()
	_game_over.hide_screen()
	_enter_flow(Flow.PLAY)
	_shooter.active = true
	_director.restart()


## Opens the hero select again, for the Change hero button.
func _change_hero() -> void:
	_game_over.hide_screen()
	_director.stop()
	_pool.clear_all()
	_shooter.active = false
	_enter_flow(Flow.SELECT)


## Picks the layout size from the screen shape. Runs every frame, so a rotation mid-run only changes the layout.
func _fit_layout() -> void:
	var window_size: Vector2i = get_window().size
	# Browsers report the canvas in device pixels, but a finger and the 48 px target rule work in CSS pixels.
	var pixel_ratio: float = maxf(DisplayServer.screen_get_scale(), 1.0)
	var css_size: Vector2 = Vector2(window_size) / pixel_ratio
	# Layout pixels for a 64 px target stay at 48 CSS pixels at the lowest scale.
	var ui_scale: float = UiKit.scale_for(css_size) * pixel_ratio
	var layout: Vector2i = Vector2i((Vector2(window_size) / ui_scale).round())
	if get_window().content_scale_size != layout:
		get_window().content_scale_size = layout
	var widest: float = BUTTON_MIN_SIZE.x
	for child: Node in _controls.get_children():
		if child is Button and (child as Button).visible:
			widest = maxf(widest, (child as Button).get_combined_minimum_size().x)
	var columns: int = clampi(int((layout.x - CONTROLS_MARGIN * 2.0 + CONTROLS_GAP) / (widest + CONTROLS_GAP)), 1, 6)
	if _controls.columns != columns:
		_controls.columns = columns
	# The grid grows upward from the bottom edge, so its top edge is the real height the cards must stay above.
	_hero_select.bottom_reserve = _hero_select.size.y - _controls.global_position.y + CONTROLS_MARGIN
	_hero_select.compact = layout.x < layout.y
	_fit_start_screen(layout)
	# The camera preview sits in the page corner, so the menu button drops below it instead of under it.
	var layout_per_css_pixel: float = pixel_ratio / ui_scale
	_menu_button.offset_top = CONTROLS_MARGIN + (HOLOGRAM_CSS_HEIGHT + CONTROLS_MARGIN) * layout_per_css_pixel
	_menu_button.offset_bottom = _menu_button.offset_top + MENU_BUTTON_SIZE.y


## One small button opens the settings during the run, so they never cover the hero.
func _build_menu_button() -> void:
	_menu_button = UiKit.icon_button("cog", func() -> void: _menu_open = not _menu_open, "", "Menu", MENU_BUTTON_SIZE)
	_menu_button.anchor_left = 1.0
	_menu_button.anchor_right = 1.0
	_menu_button.offset_left = -MENU_BUTTON_SIZE.x - CONTROLS_MARGIN
	_menu_button.offset_right = -CONTROLS_MARGIN
	$Hud.add_child(_menu_button)


## Moves one lane. Ignored outside the run, so a flick on a menu never steers.
func _on_steer_input(direction: int) -> void:
	if _flow == Flow.PLAY and not _station.is_open():
		_director.step_lane(direction)


## Cycles the weapon inventory. Down is the next weapon and up is the previous one.
func _on_weapon_input(direction: int) -> void:
	if _flow == Flow.PLAY and not _station.is_open():
		_shooter.cycle_weapon(direction)
		_audio.play(&"ui_click")


## Slide mode puts the hero in the lane the hand points at.
func _steer_by_slide() -> void:
	if _flow != Flow.PLAY or _body_input.get_steer_mode() != BodyInput.SteerMode.SLIDE or not _body_input.magic:
		return
	_director.go_to_lane(BodyInput.slide_to_lane(_body_input.slide, _director.lane, _director.lane_count))


## Keyboard: A and D or left and right steer. W and S or up and down cycle weapons.
func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match (event as InputEventKey).physical_keycode:
		KEY_A, KEY_LEFT:
			_on_steer_input(-1)
		KEY_D, KEY_RIGHT:
			_on_steer_input(1)
		KEY_W, KEY_UP:
			_on_weapon_input(-1)
		KEY_S, KEY_DOWN:
			_on_weapon_input(1)


func _style_label(label: Label, font_size: int) -> void:
	label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.7))
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.add_theme_constant_override("shadow_outline_size", 3)
	if label == _hud_label:
		label.add_theme_stylebox_override("normal", UiKit.brush(Color(0.0, 0.0, 0.0, 0.75), UiKit.ORANGE, 8.0, 11, false))


func _build_buttons() -> void:
	_controls.theme = UiKit.theme()
	_magic_button = _add_button("palm", "Hands", _toggle_magic, "Magic hands")
	_sound_button = _add_button("sound_on", "", _toggle_mute, "Sound")
	_add_button("cog", "Debug", _toggle_debug, "Debug")
	_change_hero_button = _add_button("user", "Hero", _change_hero, "Change hero")
	_lanes_button = _add_button("move_lr", "3", _toggle_lanes, "Lanes")
	_steer_button = _add_button("move_lr", "Flick", _toggle_steer, "Steering")
	_shake_button = _add_button("zombie", "", _toggle_shake, "Screen shake")
	_add_button("", "Credits", _open_credits)
	_debug_only_buttons.append(_add_button("", "Recenter", _body_input.recenter))
	_debug_only_buttons.append(_add_button("", "Music: on", _toggle_music))
	_debug_only_buttons.append(_add_button("", "Sfx: on", _toggle_sfx))
	_debug_only_buttons.append(_add_button("", "Scale 1.0", func() -> void: get_viewport().scaling_3d_scale = 1.0))
	_debug_only_buttons.append(_add_button("", "Scale 0.75", func() -> void: get_viewport().scaling_3d_scale = 0.75))
	_debug_only_buttons.append(_add_button("", "Scale 0.6", func() -> void: get_viewport().scaling_3d_scale = 0.6))
	_debug_only_buttons.append(_add_button("", "Anim LOD", func() -> void: _pool.set_animation_lod(not _pool.animation_lod_enabled)))
	_debug_only_buttons.append(_add_button("", "Bench 5s", _start_benchmark))
	_debug_only_buttons.append(_add_button("", "Restart run", _director.restart))
	_apply_debug_visibility()
	_build_menu_button()
	_build_start_screen()
	_build_message_box()


## Wraps the message in a rounded panel with an icon, so "Go", "Horde" and "Try again" read without the words.
func _build_message_box() -> void:
	_message_box = PanelContainer.new()
	_message_box.theme = UiKit.theme()
	_message_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_message_box.set_anchors_preset(Control.PRESET_CENTER)
	_message_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_message_box.grow_vertical = Control.GROW_DIRECTION_BOTH
	_message_box.offset_top = -MESSAGE_RISE
	_message_box.offset_bottom = -MESSAGE_RISE
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_message_box.add_child(row)
	_message_icon = TextureRect.new()
	_message_icon.custom_minimum_size = Vector2.ONE * 64.0
	_message_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_message_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(_message_icon)
	_message.get_parent().remove_child(_message)
	_message.autowrap_mode = TextServer.AUTOWRAP_OFF
	_message.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_message)
	$Hud.add_child(_message_box)
	_message_box.visible = false


func _show_message_icon(text: String) -> void:
	var icon_name: String = "zombie" if text.begins_with("Horde") else "next"
	_message_icon.texture = UiKit.icon(icon_name)
	_message_icon.modulate = UiKit.GOLD


## Debug readouts and test buttons cover the scene on a tablet, so they stay collapsed until asked for.
func _toggle_debug() -> void:
	_debug_visible = not _debug_visible
	_apply_debug_visibility()


func _apply_debug_visibility() -> void:
	for button: Button in _debug_only_buttons:
		button.visible = _debug_visible
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.railsBridge.debugOn=%s;document.getElementById('panel').style.display='%s'" % [str(_debug_visible).to_lower(), "flex" if _debug_visible else "none"])


func _add_button(icon_name: String, label: String, action: Callable, tooltip: String = "") -> Button:
	var button: Button = UiKit.icon_button(icon_name, action, label, tooltip, BUTTON_MIN_SIZE if not label.is_empty() else Vector2(BUTTON_MIN_SIZE.y, BUTTON_MIN_SIZE.y))
	button.pressed.connect(_audio.play.bind(&"ui_click"))
	_controls.add_child(button)
	return button


## Shows a toggle state with the icon, never with colour alone. Off uses the cross icon.
func _set_toggle(button: Button, enabled: bool, on_icon: String, off_icon: String = "times") -> void:
	button.icon = UiKit.icon(on_icon if enabled else off_icon)


## Connects every game event to its sound. Sounds stay silent until the first tap on the start screen unlocks audio.
func _wire_audio() -> void:
	_shooter.shot_fired.connect(func(hits: int) -> void:
		var weapon_id: StringName = _shooter.get_weapon()["id"]
		var weapon: Dictionary = HeroTable.weapon_by_id(weapon_id)
		_audio.play(weapon["shot_sound"])
		if hits > 0:
			_audio.play(&"bat_hit" if bool(weapon["melee"]) else &"hit"))
	_shooter.weapon_changed.connect(func(_weapon: Dictionary) -> void: _audio.play(&"weapon_equip"))
	_director.lane_changed.connect(func(_lane: int) -> void: _audio.play(&"lane_change"))
	_director.hearts_changed.connect(func(hearts: int) -> void:
		if hearts == 0:
			_audio.play(&"run_over"))
	_juice.combo_changed.connect(func(count: int) -> void:
		if count > 0:
			_audio.play(&"combo_milestone" if count % COMBO_MILESTONE == 0 else &"combo_tick"))
	_body_input.flick_horizontal.connect(func(_direction: int) -> void: _audio.play(&"flick"))
	_body_input.flick_vertical.connect(func(_direction: int) -> void:
		_audio.play(&"flick")
		_audio.play(&"weapon_cycle"))
	_juice.kill_chained.connect(func(pitch_scale: float) -> void: _audio.play(&"poof", pitch_scale))
	_pool.zombie_hurt.connect(_audio.play.bind(&"zombie_hurt"))
	_director.heart_lost.connect(_audio.play.bind(&"hurt"))
	_director.wave_started.connect(_audio.play.bind(&"wave_start"))
	_director.wave_started.connect(_audio.set_tension.bind(true))
	_director.wave_cleared.connect(_audio.play.bind(&"wave_clear"))
	_director.wave_cleared.connect(_audio.set_tension.bind(false))
	_body_input.hand_seen_changed.connect(func(seen: bool) -> void: _audio.play(&"hand_found" if seen else &"hand_lost"))


## Changes the number of hidden lanes. The change applies on the next run.
func _toggle_lanes() -> void:
	_director.lane_count = 5 if _director.lane_count == 3 else 3
	_lanes_button.text = str(_director.lane_count)


## Switches between flick steering and slide steering, and tells the tracker.
func _toggle_steer() -> void:
	_apply_steer_mode(_body_input.get_steer_mode() == BodyInput.SteerMode.FLICK)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("localStorage.setItem('railsSteer','%s')" % ("slide" if _body_input.get_steer_mode() == BodyInput.SteerMode.SLIDE else "flick"))


func _apply_steer_mode(slide: bool) -> void:
	_body_input.set_steer_mode(BodyInput.SteerMode.SLIDE if slide else BodyInput.SteerMode.FLICK)
	_steer_button.text = "Slide" if slide else "Flick"
	_steer_button.icon = UiKit.icon("pointing" if slide else "move_lr")


## Falls back to the default hero when nothing valid is stored.
func _restore_hero_id() -> StringName:
	if not OS.has_feature("web"):
		return HeroTable.DEFAULT_ID
	var stored := StringName(str(JavaScriptBridge.eval("(function(){try{return localStorage.getItem('railsHero')||''}catch(e){return ''}})()", true)))
	return stored if HeroTable.get_spec(stored)["id"] == stored else HeroTable.DEFAULT_ID


## Restores the steering choice from the last visit, so a player never picks it twice.
func _restore_steer_mode() -> void:
	if OS.has_feature("web") and str(JavaScriptBridge.eval("localStorage.getItem('railsSteer')")) == "slide":
		_apply_steer_mode(true)


## Screen shake can be turned off for players who are sensitive to motion.
func _toggle_shake() -> void:
	_director.shake_enabled = not _director.shake_enabled
	_set_toggle(_shake_button, _director.shake_enabled, "zombie")


func _toggle_magic() -> void:
	_body_input.set_magic(not _body_input.magic)


func _toggle_mute() -> void:
	_audio.set_muted(not _audio.muted)
	_set_toggle(_sound_button, not _audio.muted, "sound_on", "sound_off")


func _toggle_music() -> void:
	_audio.set_volume(AudioBus.MUSIC_BUS, 0.0 if _audio.get_volume(AudioBus.MUSIC_BUS) > 0.0 else 1.0)
	_set_label(&"Music", _audio.get_volume(AudioBus.MUSIC_BUS) > 0.0)


func _toggle_sfx() -> void:
	_audio.set_volume(AudioBus.SFX_BUS, 0.0 if _audio.get_volume(AudioBus.SFX_BUS) > 0.0 else 1.0)
	_set_label(&"Sfx", _audio.get_volume(AudioBus.SFX_BUS) > 0.0)


## Updates the "name: on" or "name: off" text of a toggle button.
func _set_label(name: StringName, enabled: bool) -> void:
	for child: Node in _controls.get_children():
		if child is Button and (child as Button).text.begins_with(String(name) + ":"):
			(child as Button).text = "%s: %s" % [name, "on" if enabled else "off"]


func _start_benchmark() -> void:
	_benchmark_elapsed = 0.0
	_benchmark_frames = 0
	_benchmark_running = true


func _build_credits() -> void:
	_credits = CreditsScreen.new()
	_credits.name = "Credits"
	$Hud.add_child(_credits)


func _build_game_over() -> void:
	_game_over = GameOverScreen.new()
	_game_over.name = "GameOver"
	_game_over.retry_requested.connect(func() -> void:
		_audio.play(&"ui_click")
		_start_game())
	_game_over.camp_requested.connect(func() -> void:
		_audio.play(&"ui_click")
		_change_hero())
	$Hud.add_child(_game_over)


## Counts only what this run did, because the shooter and pickups keep totals since the page loaded.
func _reset_run_stats() -> void:
	_run_zombies = 0
	_run_seconds = 0.0
	_run_weapon_seconds.clear()
	_run_base_shots = _shooter.shots_fired
	_run_base_hits = _shooter.shots_hit
	_run_base_pickups = _pickup_total()


func _pickup_total() -> int:
	return _pickups.collected_ammo + _pickups.collected_health + _pickups.collected_weapons


func _track_run_time(delta: float) -> void:
	if _flow != Flow.PLAY or _director.phase != RailsDirector.Phase.RUNNING:
		return
	_run_seconds += delta
	var weapon_id: StringName = _shooter.get_weapon()["id"]
	_run_weapon_seconds[weapon_id] = _run_weapon_seconds.get(weapon_id, 0.0) + delta


func _on_game_over(metres: int) -> void:
	_shooter.active = false
	var favourite: StringName = _picked_id
	var most: float = -1.0
	for weapon_id: StringName in _run_weapon_seconds:
		if _run_weapon_seconds[weapon_id] > most:
			most = _run_weapon_seconds[weapon_id]
			favourite = weapon_id
	_game_over.show_result({
		"metres": metres,
		"hero": String(HeroTable.get_spec(_picked_id)["name"]),
		"weapon": String(HeroTable.weapon_by_id(favourite)["label"]),
		"zombies": _run_zombies,
		"shots": _shooter.shots_fired - _run_base_shots,
		"hits": _shooter.shots_hit - _run_base_hits,
		"pickups": _pickup_total() - _run_base_pickups,
		"combo": _juice.best_combo,
		"seconds": int(_run_seconds),
	})


## Palm and fist press Try again on the game over screen. The select screen reads its own palm hold.
func _confirm_by_pose() -> void:
	if _game_over.visible:
		_game_over.confirm()


## Lets the browser test end a run at a chosen distance and read the screen, because a real run needs a long fight.
func _poll_test_command() -> void:
	if not OS.has_feature("web"):
		return
	var command: Variant = JavaScriptBridge.eval("(function(b){var c=b&&b.gameOverCommand;if(b)b.gameOverCommand=null;return c||''})(window.railsBridge)")
	if command is String and String(command).begins_with("end:"):
		_director.distance = float(String(command).substr(4))
		while _director.phase == RailsDirector.Phase.RUNNING:
			_director._on_hazard_reached_player()
	JavaScriptBridge.eval("window.railsBridge && (window.railsBridge.gameOverReport = '%s')" % JSON.stringify(_game_over.report()).replace("'", "\\'"))


func _open_credits() -> void:
	_credits.open_screen()


## The first tap unlocks web audio and asks for fullscreen, because browsers allow both only from a real gesture.
## The Hands button asks for the camera. Tapping a hero plays by touch, so the camera stays opt-in.
func _build_start_screen() -> void:
	var start_button: Button = _start_overlay.get_node("StartButton")
	# The overlay sits above the camp, so it must let taps through to the heroes.
	_start_overlay.color = Color(0, 0, 0, 0)
	_start_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_start_buttons = BoxContainer.new()
	_start_buttons.name = "StartButtons"
	_start_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_start_buttons.add_theme_constant_override("separation", int(START_BUTTON_GAP))
	_start_buttons.set_anchors_preset(Control.PRESET_FULL_RECT)
	# The buttons sit on the bottom edge because the heroes and their weapon pills fill the middle of every screen shape.
	_start_buttons.offset_bottom = -START_BUTTON_MARGIN
	_start_buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_start_overlay.add_child(_start_buttons)
	start_button.reparent(_start_buttons, false)
	_style_start_button(start_button, "Hands", "Play with hands", "palm")
	start_button.pressed.connect(_start_with_hands)
	var credits_button: Button = Button.new()
	credits_button.name = "CreditsButton"
	credits_button.theme = UiKit.theme()
	credits_button.text = "Credits"
	credits_button.custom_minimum_size = Vector2(UiKit.MIN_TARGET * 2.5, START_BUTTON_SIZE.y)
	credits_button.size_flags_vertical = Control.SIZE_SHRINK_END
	credits_button.pressed.connect(_open_credits)
	_start_buttons.add_child(credits_button)
	_camera_notice = PanelContainer.new()
	_camera_notice.name = "CameraNotice"
	_camera_notice.theme = UiKit.theme()
	_camera_notice.add_theme_stylebox_override("panel", UiKit.brush())
	_camera_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_camera_notice.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_camera_notice.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_camera_notice.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_camera_notice.offset_bottom = -CAMERA_NOTICE_BOTTOM
	_camera_notice.visible = false
	var notice_label := Label.new()
	notice_label.text = "No camera here. Tap a hero to play."
	notice_label.add_theme_font_size_override("font_size", START_FONT_SIZE)
	notice_label.add_theme_font_override("font", UiKit.font())
	notice_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice_label.custom_minimum_size = Vector2(CAMERA_NOTICE_WIDTH, 0.0)
	notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_camera_notice.add_child(notice_label)
	_start_overlay.add_child(_camera_notice)
	_start_title = TitleLogo.new()
	_start_title.name = "Title"
	_start_title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE, Control.PRESET_MODE_MINSIZE, 0)
	_start_title.offset_top = 24.0
	_start_title.big_size = TITLE_FONT_SIZE
	_start_overlay.add_child(_start_title)


## Stacks the start buttons in portrait and shrinks the title to fit the width, so nothing clips on a phone.
func _fit_start_screen(layout: Vector2i) -> void:
	var portrait: bool = layout.x < layout.y
	_start_buttons.vertical = portrait
	_camera_notice.offset_bottom = -(CAMERA_NOTICE_BOTTOM_PORTRAIT if portrait else CAMERA_NOTICE_BOTTOM)
	_start_buttons.alignment = BoxContainer.ALIGNMENT_END if portrait else BoxContainer.ALIGNMENT_CENTER
	_start_title.big_size = TITLE_FONT_SIZE if layout.x >= 900 else int(layout.x * 0.2)


## Big green icon button below the hero. The icon says how to play, and the single word backs it up.
func _style_start_button(button: Button, word: String, tooltip: String, icon_name: String) -> void:
	button.theme = UiKit.theme()
	button.text = word
	button.tooltip_text = tooltip
	button.icon = UiKit.icon(icon_name)
	button.expand_icon = true
	button.add_theme_font_size_override("font_size", START_FONT_SIZE)
	button.add_theme_constant_override("icon_max_width", START_ICON_SIZE)
	UiKit.primary(button)
	button.custom_minimum_size = START_BUTTON_SIZE
	button.size_flags_vertical = Control.SIZE_SHRINK_END


func _unlock_from_tap() -> void:
	_audio.unlock()
	_audio.play(&"ui_click")
	if OS.has_feature("web"):
		JavaScriptBridge.eval("document.documentElement.requestFullscreen && document.documentElement.requestFullscreen().catch(function(){})")


func _start_with_hands() -> void:
	_unlock_from_tap()
	_body_input.set_magic(true)


func _on_pickup_collected(kind: Pickups.Kind, weapon_id: StringName) -> void:
	if kind == Pickups.Kind.AMMO:
		_shooter.refill_ammo()
	elif kind == Pickups.Kind.WEAPON:
		_shooter.add_weapon(weapon_id)
	else:
		_director.heal(1)
	_audio.play(&"pickup")


## Publishes pickup counts so the browser test can watch them.
func _publish_pickup_state() -> void:
	if not OS.has_feature("web"):
		return
	var state: String = "%d,%d,%d,%d" % [_pickups.get_child_count(), _pickups.collected_ammo, _pickups.collected_health, _director.hearts]
	JavaScriptBridge.eval("window.railsBridge && (window.railsBridge.godotPickups = '%s')" % state)
