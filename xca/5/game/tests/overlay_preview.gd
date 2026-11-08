extends Node2D
## Preview scene for the match-end overlay. It shows a win, then a loss, on the arena floor colour.
##
## Open tests/overlay_preview.tscn. The loss shows after [constant LOSS_DELAY] seconds.

## Seconds the win shows before the loss replaces it.
const LOSS_DELAY: float = 3.0

var _overlay: MatchEndOverlay


func _ready() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	var floor: ColorRect = ColorRect.new()
	floor.color = Color(0.09, 0.13, 0.22)
	floor.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(floor)
	_overlay = MatchEndOverlay.new()
	layer.add_child(_overlay)
	_overlay.show_result(true)
	get_tree().create_timer(LOSS_DELAY).timeout.connect(_overlay.show_result.bind(false))
