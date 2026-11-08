class_name TutorialHints
extends HBoxContainer
## A wordless icon strip that loops through the steps of a task. The step that is playing pops and the others dim.
##
## Players who steer by hand cannot guess that rubbing the weapon cleans it, so the strip shows the order in icons.
## It stops showing once the player has cleaned a weapon, and that choice persists in the browser.

## Strokes that count as having learned to clean. About half a full clean.
const LEARN_STROKES: int = 6
## Seconds each step plays.
const STEP_SECONDS: float = 1.1
## Icon edge in layout pixels at scale 1. The 48 px target size stays the floor.
const ICON_SIZE: float = 56.0
## Sideways swing of a rub icon in pixels at scale 1.
const RUB_SWING: float = 10.0
const DIMMED: Color = Color(1.0, 1.0, 1.0, 0.72)
const STORAGE_KEY: String = "railsCleanLearned"

static var _learned: int = -1

## Steps shown at the calm station: raise two palms, rub, sparkle. A touch or mouse player drags instead.
static func station_steps(by_hand: bool) -> Array:
	var rub: Array = ["~palm", "grime"] if by_hand else ["~pointing", "grime"]
	return [["palm", "palm"] if by_hand else ["pointing"], rub, ["sparkles"]]


## Steps shown in the viewer: zoom, turn, roll, rub, close.
static func viewer_steps(by_hand: bool) -> Array:
	var rub: Array = ["~palm", "grime"] if by_hand else ["~pointing", "grime"]
	var steps: Array = [["search_plus"], ["move_lr"], ["reload"], rub]
	if by_hand:
		steps.append(["palm", "palm", "check"])
	return steps


var _chips: Array[PanelContainer] = []
var _wiggles: Array[Array] = []
var _steps: Array = []


## True once the player has cleaned a weapon in this browser.
static func is_learned() -> bool:
	if _learned < 0:
		_learned = 0
		if OS.has_feature("web"):
			var stored: String = str(JavaScriptBridge.eval("(function(){try{return localStorage.getItem('%s')||''}catch(e){return ''}})()" % STORAGE_KEY, true))
			_learned = 1 if stored == "1" else 0
	return _learned == 1


static func mark_learned() -> void:
	_learned = 1
	if OS.has_feature("web"):
		JavaScriptBridge.eval("try{localStorage.setItem('%s','1')}catch(e){}" % STORAGE_KEY)


## Steps are lists of icon names. A name that starts with "~" swings sideways, so a rub reads as motion.
func show_steps(steps: Array) -> void:
	_steps = steps
	for child: Node in get_children():
		child.queue_free()
	_chips.clear()
	_wiggles.clear()
	process_mode = Node.PROCESS_MODE_ALWAYS
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", 8)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for step: Array in steps:
		var chip := PanelContainer.new()
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_theme_stylebox_override("panel", UiKit.brush(UiKit.PANEL_SOLID, UiKit.ORANGE, 6.0, 7, false))
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 2)
		chip.add_child(row)
		var swingers: Array = []
		for icon_name: String in step:
			var swing: bool = icon_name.begins_with("~")
			var slot := Control.new()
			slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(slot)
			var rect := TextureRect.new()
			rect.texture = UiKit.icon(icon_name.trim_prefix("~"))
			rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			slot.add_child(rect)
			if swing:
				swingers.append(rect)
		add_child(chip)
		_chips.append(chip)
		_wiggles.append(swingers)
	_fit()
	if not get_viewport().size_changed.is_connected(_fit):
		get_viewport().size_changed.connect(_fit)


func _fit() -> void:
	var edge: float = maxf(ICON_SIZE * UiKit.scale_for(get_viewport().get_visible_rect().size), UiKit.MIN_TARGET)
	for chip: PanelContainer in _chips:
		for slot: Node in chip.get_child(0).get_children():
			(slot as Control).custom_minimum_size = Vector2(edge, edge)
			(slot.get_child(0) as TextureRect).size = Vector2(edge, edge)
		chip.pivot_offset = chip.size * 0.5


func _process(_delta: float) -> void:
	if _chips.is_empty() or not is_visible_in_tree():
		return
	# Real time, because the station runs in slow motion and the viewer pauses the tree.
	var now: float = Time.get_ticks_msec() / 1000.0
	var active: int = int(now / STEP_SECONDS) % _chips.size()
	var swing: float = RUB_SWING * UiKit.scale_for(get_viewport().get_visible_rect().size)
	for index: int in _chips.size():
		var chip: PanelContainer = _chips[index]
		var playing: bool = index == active
		chip.pivot_offset = chip.size * 0.5
		chip.scale = Vector2.ONE * (1.12 if playing else 1.0)
		chip.modulate = Color.WHITE if playing else DIMMED
		for rect: TextureRect in _wiggles[index]:
			rect.position.x = sin(now * TAU * 1.6) * swing if playing else 0.0
