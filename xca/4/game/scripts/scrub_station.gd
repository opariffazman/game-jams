class_name ScrubStation
extends Node
## The calm station: after a wave the player can stop the run, look at the weapon and scrub the dirt off it.
##
## The run pauses while the viewer is open, so cleaning never costs a heart. A clean weapon fires at full rate, and a full clean gives a short bonus.

## Emitted when the viewer opens, so the page and the music can react.
signal opened
## Emitted when the viewer closes and the run resumes.
signal finished

const PROMPT_SECONDS: float = 7.0
## Canvas layer of the viewer. The run HUD uses the default layer.
const VIEW_LAYER: int = 20
const PROMPT_SIZE: Vector2 = Vector2(440.0, 150.0)
const ICON_BUTTON: Vector2 = Vector2(72.0, 72.0)
const PROMPT_TOP: float = 8.0
const PROMPT_MARGIN: float = 8.0
## Colours chosen for WCAG AA: white on the panel is above 15:1, white on the button is above 6:1, borders are above 3:1 on the panel.
const PANEL_COLOR: Color = Color(0.05, 0.04, 0.11)
const BUTTON_COLOR: Color = Color(0.1, 0.32, 0.75)
const BUTTON_PRESSED_COLOR: Color = Color(0.06, 0.2, 0.5)
const BORDER_COLOR: Color = Color(1.0, 1.0, 1.0)
const MIN_TARGET: float = 48.0
const BUTTON_SIZE: Vector2 = Vector2(150.0, 64.0)
const INSPECT_BUTTON_SIZE: Vector2 = Vector2(150.0, 56.0)
const HUD_TOP: float = 154.0
const HUD_LEFT: float = 12.0
const SCRUB_SOUND_INTERVAL: float = 0.18
## Seconds two open palms must stay up before slow motion starts. A short hold would trigger while the player waves both hands.
const PALM_SLOWMO_AFTER: float = 0.5
## Seconds of steady two palms that commit to the viewer. The slow motion between the two gives the player time to drop the hand.
const PALM_COMMIT_AFTER: float = 1.6
const SLOWMO_SCALE: float = 0.25
const FONT: int = 26
## A prompt only shows when the current weapon carries at least this much dirt.
const PROMPT_MIN_GRIME: float = 0.08
const DIRT_SHADER: String = """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back;
uniform float grime : hint_range(0.0, 1.0) = 0.0;
uniform float scale = 14.0;
varying vec3 local;
float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}
float value_noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash(i), hash(i + vec3(1.0, 0.0, 0.0)), f.x), mix(hash(i + vec3(0.0, 1.0, 0.0)), hash(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
		mix(mix(hash(i + vec3(0.0, 0.0, 1.0)), hash(i + vec3(1.0, 0.0, 1.0)), f.x), mix(hash(i + vec3(0.0, 1.0, 1.0)), hash(i + vec3(1.0, 1.0, 1.0)), f.x), f.y),
		f.z);
}
void vertex() {
	local = VERTEX;
}
void fragment() {
	float n = value_noise(local * scale) * 0.65 + value_noise(local * scale * 2.3) * 0.35;
	float threshold = 0.75 - grime * 0.45;
	float mask = smoothstep(threshold, threshold + 0.1, n);
	ALBEDO = mix(vec3(0.24, 0.15, 0.08), vec3(0.09, 0.06, 0.04), n);
	ROUGHNESS = 1.0;
	ALPHA = mask * 0.92;
}
"""

## Shooter that owns the grime and the weapon in hand.
var shooter: Shooter
## Hero whose weapon mesh shows the dirt during the run.
var hero: RailsHero
## Audio for the scrub sounds.
var audio: AudioBus
## Tracker data for the two-hand and scrub fields.
var body_input: BodyInput
## Parent for the station's controls. A canvas layer anchors them to the viewport.
var hud: Node
## Whether the player is in the run. The page and the keys only open the station then.
var available: bool = false:
	set(value):
		available = value
		_sync_tracker_hands()
		if _inspect_button != null:
			_inspect_button.visible = value and not _view.is_open() and not _prompt.visible
		if not value:
			_hide_prompt()

var _view: InspectView
var _bridge: JavaScriptObject
var _two_hands_on: bool = false
var _prompt: PanelContainer
var _prompt_label: Label
var _prompt_timer: float = 0.0
var _inspect_button: Button
var _grime_chip: ProgressBar
var _grime_row: HBoxContainer
var _materials: Dictionary[StringName, ShaderMaterial] = {}
var _scrub_sound_clock: float = 0.0
var _mesh_with_overlay: MeshInstance3D
var _commit_bar: ProgressBar
var _commit_label: Label
var _palm_held: float = 0.0
## After a close the player's palms are still up. The gate stays shut until they drop.
var _needs_release: bool = false
var _demo: TutorialHints
var _learn_strokes: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for weapon: Dictionary in HeroTable.WEAPONS:
		var id: StringName = weapon["id"]
		var material := ShaderMaterial.new()
		material.shader = Shader.new()
		material.shader.code = DIRT_SHADER
		_materials[id] = material


## Builds the controls. Called once by the game after the references are set.
func build() -> void:
	if OS.has_feature("web"):
		_bridge = JavaScriptBridge.get_interface("railsBridge")
	_view = InspectView.new()
	_view.process_mode = Node.PROCESS_MODE_ALWAYS
	_view.body_input = body_input
	_view.scrubbed.connect(_on_scrubbed)
	_view.closed.connect(_on_closed)
	_view.weapon_step.connect(_on_weapon_step)
	# Its own layer sits above the run HUD, so the hearts and the menu button never show through the backdrop.
	var layer := CanvasLayer.new()
	layer.layer = VIEW_LAYER
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	layer.add_child(_view)
	_build_prompt()
	_build_hud_widgets()
	shooter.weapon_changed.connect(func(_weapon: Dictionary) -> void: _refresh_overlay())
	shooter.shot_fired.connect(func(_hits: int) -> void: _refresh_overlay())
	if body_input != null:
		body_input.flick_horizontal.connect(func(_direction: int) -> void: _cancel_commit())
		body_input.flick_vertical.connect(func(_direction: int) -> void: _cancel_commit())
		body_input.process_mode = Node.PROCESS_MODE_ALWAYS
	if audio != null:
		audio.process_mode = Node.PROCESS_MODE_ALWAYS
	_refresh_overlay()


func _process(delta: float) -> void:
	_track_hand_gate(delta / maxf(Engine.time_scale, 0.01))
	_scrub_sound_clock = maxf(_scrub_sound_clock - delta, 0.0)
	if _prompt.visible:
		_prompt_timer -= delta
		if _prompt_timer <= 0.0:
			_hide_prompt()
	_grime_chip.value = shooter.grime.level(StringName(shooter.get_weapon()["id"])) * 100.0
	_grime_row.visible = available and not _view.is_open() and not _prompt.visible
	if body_input != null:
		body_input.inspect_open = _view.is_open()
		body_input.grime_level = shooter.grime.level(StringName(shooter.get_weapon()["id"]))
		body_input.inspect_zoom = _view.get_zoom()
		body_input.inspect_yaw = _view.get_yaw()
	if available and not _view.is_open() and not _inspect_button.visible and not _prompt.visible:
		_inspect_button.visible = true


func _unhandled_key_input(event: InputEvent) -> void:
	if not available or _view.is_open() or not event is InputEventKey or not event.pressed or event.echo:
		return
	match (event as InputEventKey).physical_keycode:
		KEY_I, KEY_C:
			open()


## Offers the station for a few seconds. Called when a wave clears.
func offer() -> void:
	if not available or _view.is_open():
		return
	if shooter.grime.level(StringName(shooter.get_weapon()["id"])) < PROMPT_MIN_GRIME:
		return
	_prompt_timer = PROMPT_SECONDS
	_demo.visible = not TutorialHints.is_learned()
	if _demo.visible:
		_demo.show_steps(TutorialHints.station_steps(body_input != null and body_input.magic))
		_prompt_timer = PROMPT_SECONDS * 2.0
	_prompt.visible = true
	_inspect_button.visible = false
	_update_prompt_text()


## Pauses the run and shows the viewer with the weapon in hand.
func open() -> void:
	if not available or _view.is_open():
		return
	_hide_prompt()
	_inspect_button.visible = false
	audio.play(&"inspect_open")
	get_tree().paused = true
	var weapon: Dictionary = shooter.get_weapon()
	_view.open(weapon, _weapon_mesh(), _materials[StringName(weapon["id"])], shooter.grime.level(StringName(weapon["id"])))
	opened.emit()


## Closes the viewer and resumes the run.
func close() -> void:
	_view.close()


func is_open() -> bool:
	return _view.is_open()


## Returns the viewer, for tests.
func get_view() -> InspectView:
	return _view


## Returns true while the offer is on screen, for tests.
func is_offering() -> bool:
	return _prompt.visible


func _build_prompt() -> void:
	_prompt = PanelContainer.new()
	_prompt.visible = false
	_prompt.process_mode = Node.PROCESS_MODE_ALWAYS
	_prompt.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt.add_theme_stylebox_override("panel", _panel_style())
	_layout_prompt()
	get_viewport().size_changed.connect(_layout_prompt)
	_prompt.theme = UiKit.theme()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_prompt.add_child(box)
	var message_row := HBoxContainer.new()
	message_row.alignment = BoxContainer.ALIGNMENT_CENTER
	message_row.add_theme_constant_override("separation", 12)
	box.add_child(message_row)
	var drop := TextureRect.new()
	drop.texture = UiKit.icon("grime")
	drop.modulate = UiKit.DIRT
	drop.custom_minimum_size = Vector2(48.0, 48.0)
	drop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	drop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	message_row.add_child(drop)
	_prompt_label = Label.new()
	_prompt_label.add_theme_font_size_override("font_size", FONT + 10)
	message_row.add_child(_prompt_label)
	_demo = TutorialHints.new()
	_demo.show_steps(TutorialHints.station_steps(body_input != null and body_input.magic))
	box.add_child(_demo)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	box.add_child(row)
	var clean: Button = _make_button("sparkles", "Clean", open, "Clean the weapon")
	UiKit.primary(clean)
	row.add_child(clean)
	row.add_child(_make_button("times", "", _hide_prompt, "Skip"))
	hud.add_child(_prompt)


## Sits below the hearts and the weapon strip, so it never covers the hero. The width follows the viewport so portrait still fits.
func _layout_prompt() -> void:
	var width: float = minf(PROMPT_SIZE.x, get_viewport().get_visible_rect().size.x - 2.0 * PROMPT_MARGIN)
	_prompt.custom_minimum_size = Vector2(width, 0.0)
	_prompt.size = Vector2(width, 0.0)
	_prompt.offset_left = -width * 0.5
	_prompt.offset_right = width * 0.5
	_prompt.offset_top = PROMPT_TOP
	_prompt.offset_bottom = PROMPT_TOP


func _build_hud_widgets() -> void:
	_inspect_button = _make_button("search_plus", "", open, "Inspect the weapon")
	_inspect_button.custom_minimum_size = ICON_BUTTON
	_inspect_button.position = Vector2(HUD_LEFT, HUD_TOP)
	_inspect_button.size = ICON_BUTTON
	_inspect_button.visible = false
	_inspect_button.process_mode = Node.PROCESS_MODE_ALWAYS
	hud.add_child(_inspect_button)
	_commit_label = Label.new()
	_commit_label.visible = false
	_commit_label.process_mode = Node.PROCESS_MODE_ALWAYS
	_commit_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_commit_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_commit_label.offset_top = 12.0
	_commit_label.offset_bottom = 48.0
	_commit_label.add_theme_font_size_override("font_size", FONT)
	_commit_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	_commit_label.add_theme_constant_override("shadow_offset_y", 2)
	_commit_label.add_theme_constant_override("shadow_outline_size", 6)
	hud.add_child(_commit_label)
	_commit_bar = ProgressBar.new()
	_commit_bar.visible = false
	_commit_bar.show_percentage = false
	_commit_bar.process_mode = Node.PROCESS_MODE_ALWAYS
	_commit_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_commit_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_commit_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_commit_bar.custom_minimum_size = Vector2(320.0, 24.0)
	_commit_bar.offset_top = 52.0
	_commit_bar.offset_bottom = 76.0
	_commit_bar.add_theme_stylebox_override("fill", _flat(Color(0.3, 0.9, 1.0)))
	_commit_bar.add_theme_stylebox_override("background", _flat(Color(0.0, 0.0, 0.0, 0.7)))
	hud.add_child(_commit_bar)
	_grime_row = HBoxContainer.new()
	_grime_row.theme = UiKit.theme()
	_grime_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grime_row.position = Vector2(HUD_LEFT + ICON_BUTTON.x + 10.0, HUD_TOP + 10.0)
	_grime_row.add_theme_constant_override("separation", 8)
	var drop := TextureRect.new()
	drop.texture = UiKit.icon("grime")
	drop.modulate = UiKit.DIRT
	drop.custom_minimum_size = Vector2(48.0, 48.0)
	drop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	drop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	drop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grime_row.add_child(drop)
	_grime_chip = ProgressBar.new()
	_grime_chip.show_percentage = false
	_grime_chip.tooltip_text = "Weapon dirt"
	_grime_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grime_chip.custom_minimum_size = Vector2(110.0, 22.0)
	_grime_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_grime_row.add_child(_grime_chip)
	_grime_row.visible = false
	hud.add_child(_grime_row)


func _panel_style() -> StyleBox:
	return UiKit.brush(UiKit.PANEL, UiKit.ORANGE, 14.0, 8)


func _flat(color: Color) -> StyleBoxFlat:
	return UiKit.box(color, color, 0, 6, 0.0)


func _make_button(icon_name: String, word: String, action: Callable, tooltip: String) -> Button:
	var button: Button = UiKit.icon_button(icon_name, action, word, tooltip, ICON_BUTTON if word.is_empty() else BUTTON_SIZE)
	button.focus_mode = Control.FOCUS_NONE
	return button


func _update_prompt_text() -> void:
	var id: StringName = StringName(shooter.get_weapon()["id"])
	_prompt_label.text = "%d%%" % roundi(shooter.grime.level(id) * 100.0)


func _hide_prompt() -> void:
	if _prompt != null:
		_prompt.visible = false


## Opens on a long steady palm. Closing is never by hand, so rubbing the weapon cannot close it. This uses real seconds, because the slow motion shrinks the frame delta.
func _track_hand_gate(real_delta: float) -> void:
	_sync_tracker_hands()
	if body_input == null or not body_input.magic:
		return
	if _view.is_open():
		_cancel_commit()
		return
	if not body_input.two_palms:
		_needs_release = false
	if not available or get_tree().paused or not body_input.two_palms or _needs_release:
		_cancel_commit()
		return
	_palm_held += real_delta
	if _palm_held < PALM_SLOWMO_AFTER:
		return
	var progress: float = clampf((_palm_held - PALM_SLOWMO_AFTER) / (PALM_COMMIT_AFTER - PALM_SLOWMO_AFTER), 0.0, 1.0)
	Engine.time_scale = SLOWMO_SCALE
	_show_commit(progress, "Hold")
	if _palm_held >= PALM_COMMIT_AFTER:
		_cancel_commit()
		open()


func _cancel_commit() -> void:
	if _palm_held > 0.0:
		_palm_held = 0.0
		Engine.time_scale = 1.0
	_show_commit(0.0, "")


func _show_commit(progress: float, text: String) -> void:
	var showing: bool = progress > 0.0
	_commit_bar.visible = showing
	_commit_label.visible = showing
	_commit_bar.value = progress * 100.0
	_commit_label.text = text


func _on_scrubbed(reversals: int) -> void:
	var id: StringName = StringName(shooter.get_weapon()["id"])
	_learn_strokes += reversals
	if _learn_strokes >= TutorialHints.LEARN_STROKES and not TutorialHints.is_learned():
		TutorialHints.mark_learned()
		_view.hide_guide()
	var spotless: bool = shooter.grime.scrub(id, reversals)
	_view.set_grime(shooter.grime.level(id))
	_refresh_overlay()
	if _scrub_sound_clock <= 0.0:
		_scrub_sound_clock = SCRUB_SOUND_INTERVAL
		audio.play(&"scrub")
	if spotless:
		var bonus: bool = shooter.grime.bonus_remaining > 0.0
		_view.show_notice("Spotless! Full power for %d s." % roundi(WeaponGrime.BONUS_SECONDS) if bonus else "Spotless!")
		_view.sparkle()
		audio.play(&"clean_sparkle")


func _on_weapon_step(direction: int) -> void:
	shooter.cycle_weapon(direction)
	var weapon: Dictionary = shooter.get_weapon()
	var id: StringName = StringName(weapon["id"])
	_view.show_weapon(weapon, _weapon_mesh(), _materials[id], shooter.grime.level(id))
	_view.show_notice("")


func _on_closed() -> void:
	audio.play(&"inspect_close")
	_needs_release = true
	get_tree().paused = false
	finished.emit()
	_inspect_button.visible = available
	# The viewer switched the tracker back to one hand on close, so the cached state is stale.
	_two_hands_on = false
	_sync_tracker_hands()


## Two-hand tracking costs frame rate, so it runs only at the calm station, where the two-palm gate needs it.
func _sync_tracker_hands() -> void:
	if _bridge == null or _view == null or _view.is_open():
		return
	var wanted: bool = available and body_input != null and body_input.magic
	if wanted != _two_hands_on:
		_two_hands_on = wanted
		_bridge.setTwoHands(wanted)


func _weapon_mesh() -> MeshInstance3D:
	return hero.get_weapon_mesh()


# The overlay sits on the weapon in the hero's hand only while it carries dirt, so a clean run adds no draw call.
func _refresh_overlay() -> void:
	if hero == null or shooter == null:
		return
	var weapon: Dictionary = shooter.get_weapon()
	var id: StringName = StringName(weapon["id"])
	var level: float = shooter.grime.level(id)
	var material: ShaderMaterial = _materials[id]
	material.set_shader_parameter("grime", level)
	var mesh: MeshInstance3D = hero.get_weapon_mesh()
	if _mesh_with_overlay != null and _mesh_with_overlay != mesh and is_instance_valid(_mesh_with_overlay):
		_mesh_with_overlay.material_overlay = null
	_mesh_with_overlay = mesh
	if mesh != null:
		mesh.material_overlay = material if level > 0.001 else null
