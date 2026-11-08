class_name RestartLayer
extends CanvasLayer
## Wires the restart button and the match-end overlay to the round manager.
##
## The layer sits above the HUD and the touch controls, and it is the last node of the main scene,
## so its buttons see touches before the throw pad does.

## Round manager to restart. Found by group when empty.
@export var round_manager: RoundManager
## Seconds the restart button must be held. The button reads this value.
@export_range(0.3, 3.0, 0.1, "suffix:s") var hold_time: float = 0.8

var _restarting: bool = false

@onready var _button: RestartButton = $RestartButton
@onready var _overlay: MatchEndOverlay = $MatchEndOverlay


func _ready() -> void:
	layer = 10
	if round_manager == null:
		round_manager = get_tree().get_first_node_in_group(RoundManager.GROUP) as RoundManager
	if round_manager == null:
		push_error("RestartLayer: needs a RoundManager.")
		return
	_button.hold_time = hold_time
	_button.confirmed.connect(_restart)
	_overlay.restart_requested.connect(_restart)
	round_manager.match_ended.connect(_on_match_ended)
	round_manager.phase_changed.connect(_on_phase_changed)


func _restart() -> void:
	if _restarting:
		return
	_restarting = true
	if round_manager.restart_match() != OK:
		_restarting = false


func _on_match_ended(winner_team: int) -> void:
	_button.visible = false
	_overlay.show_result(winner_team == round_manager.tuning.human_team)


func _on_phase_changed(phase: int) -> void:
	if phase != RoundManager.MATCH_END:
		_overlay.hide_result()
		_button.visible = true
