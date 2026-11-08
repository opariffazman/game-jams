class_name Hud
extends CanvasLayer
## Score, combo, verdict text, start hint and the results panel.

const VERDICT_LIFE: float = 0.6

var _score: Label
var _combo: Label
var _verdict: Label
var _hint: Label
var _results_panel: ColorRect
var _results: Label
var _verdict_life: float = 0.0


func _ready() -> void:
	_score = _make_label("SCORE 0", 28, Rect2(20, 14, 300, 36), HORIZONTAL_ALIGNMENT_LEFT, Kata.INK)
	var caption: Label = _make_label("COMBO", 18, Rect2(0, 44, 540, 24), HORIZONTAL_ALIGNMENT_CENTER, Color(Kata.INK, 0.7))
	caption.name = "ComboCaption"
	_combo = _make_label("", 64, Rect2(0, 62, 540, 80), HORIZONTAL_ALIGNMENT_CENTER, Kata.INK)
	_verdict = _make_label("", 30, Rect2(0, 490, 540, 40), HORIZONTAL_ALIGNMENT_CENTER, Kata.INK)
	_hint = _make_label("Tap a pad on the beat\nKeys: A S D or J K L", 22, Rect2(20, 100, 500, 60), HORIZONTAL_ALIGNMENT_CENTER, Kata.INK)
	_results_panel = ColorRect.new()
	_results_panel.color = Color(Kata.BG, 0.92)
	_results_panel.position = Vector2(40, 90)
	_results_panel.size = Vector2(460, 240)
	_results_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_results_panel.visible = false
	add_child(_results_panel)
	_results = _make_label("", 34, Rect2(0, 0, 460, 240), HORIZONTAL_ALIGNMENT_CENTER, Kata.INK)
	_results.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_results.reparent(_results_panel, false)


func _process(delta: float) -> void:
	_verdict_life -= delta
	_verdict.modulate.a = clampf(_verdict_life / 0.35, 0.0, 1.0)


## Shows the score text.
func set_score(value: int) -> void:
	_score.text = "SCORE %d" % value


## Shows the combo. Hidden below 2.
func set_combo(value: int) -> void:
	_combo.text = str(value) if value >= 2 else ""


## Shows short verdict text above the hit line.
func flash_verdict(text: String, color: Color) -> void:
	_verdict.text = text
	_verdict.add_theme_color_override("font_color", color)
	_verdict_life = VERDICT_LIFE


## Fades out the start hint.
func dismiss_hint() -> void:
	if _hint.modulate.a == 1.0:
		create_tween().tween_property(_hint, "modulate:a", 0.0, 0.4)


## Opens the results panel.
func show_results(score: int, max_combo: int) -> void:
	_results.text = "SCORE %d\nMAX COMBO %d\n\nTAP TO PLAY AGAIN" % [score, max_combo]
	_results_panel.visible = true
	_combo.text = ""


## Closes the results panel.
func hide_results() -> void:
	_results_panel.visible = false


func _make_label(text: String, font_size: int, rect: Rect2, align: HorizontalAlignment, color: Color) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.position = rect.position
	label.size = rect.size
	label.horizontal_alignment = align
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Kata.BG)
	label.add_theme_constant_override("outline_size", 6)
	add_child(label)
	return label
