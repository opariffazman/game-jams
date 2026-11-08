class_name HeroDef
extends Resource
## One hero: the model, the power icon and the numbers of its power.
##
## A power has an attack form and a defence form that share one icon, because roles swap every round.
## Keys in [member attack_params] and [member defence_params]: [code]duration[/code] seconds,
## [code]speed_mult[/code], [code]pickup_mult[/code], [code]pass_turn_mult[/code], [code]carry_free[/code],
## [code]absorb[/code] and [code]dash_burst[/code].

@export var id: StringName = &""
## Portrait icon for the select card.
@export var icon: Texture2D
## Icon on the power button.
@export var power_icon: Texture2D
## Kenney character model, a .glb with the shared rig.
@export_file("*.glb") var model_path: String = ""
## Size against a regular player.
@export_range(0.8, 1.6, 0.05) var model_scale: float = 1.15
@export_range(1.0, 60.0, 0.5, "suffix:s") var cooldown_seconds: float = 12.0
@export_range(1, 5, 1) var stat_speed: int = 3
@export_range(1, 5, 1) var stat_build: int = 3
@export_range(1, 5, 1) var stat_guard: int = 3
@export_range(1, 5, 1) var stat_throw: int = 3
@export var attack_params: Dictionary = {}
@export var defence_params: Dictionary = {}


## Parameters of the power for [param attacking].
func params_for(attacking: bool) -> Dictionary:
	return attack_params if attacking else defence_params
