class_name VisualSet
extends Resource
## Names the art scene for every visual slot.
##
## Swap a skin by pointing [code]res://assets/skins/active.tres[/code] at another set.
## The [code]*_scale[/code] fields scale art only. Hitboxes come from [Tuning].

## Every slot name, in the order of the fields below.
const SLOTS: Array[StringName] = [
	&"attacker", &"defender", &"sandal", &"pass_sandal", &"stack_marker",
	&"arena", &"tombstone", &"hit_effect", &"topple_effect",
]

@export_group("Scenes")
## Attacker character art.
@export var attacker: PackedScene
## Defender character art.
@export var defender: PackedScene
## Ordinary sandal art.
@export var sandal: PackedScene
## Pass sandal art. It must look different from [member sandal].
@export var pass_sandal: PackedScene
## Marker drawn on the centre spot under the stack.
@export var stack_marker: PackedScene
## Arena floor and markings.
@export var arena: PackedScene
## Marker left where an attacker is mati.
@export var tombstone: PackedScene
## One-shot effect played when a sandal hits a character.
@export var hit_effect: PackedScene
## One-shot effect played when the stack topples.
@export var topple_effect: PackedScene

@export_group("Art scale")
## Art scale of [member attacker].
@export var attacker_scale: float = 1.0
## Art scale of [member defender].
@export var defender_scale: float = 1.0
## Art scale of [member sandal].
@export var sandal_scale: float = 1.0
## Art scale of [member pass_sandal].
@export var pass_sandal_scale: float = 1.0
## Art scale of [member stack_marker].
@export var stack_marker_scale: float = 1.0
## Art scale of [member arena].
@export var arena_scale: float = 1.0
## Art scale of [member tombstone].
@export var tombstone_scale: float = 1.0
## Art scale of [member hit_effect].
@export var hit_effect_scale: float = 1.0
## Art scale of [member topple_effect].
@export var topple_effect_scale: float = 1.0


## Returns the art scale of [param slot], or 1.0 for an unknown slot.
func get_visual_scale(slot: StringName) -> float:
	if not SLOTS.has(slot):
		return 1.0
	return float(get(String(slot) + "_scale"))


## Creates the visual for [param slot] with its art scale applied.
## Returns null when the slot has no scene.
func make(slot: StringName) -> EntityVisual:
	if not SLOTS.has(slot):
		push_error("VisualSet: unknown slot '%s'." % slot)
		return null
	var scene: PackedScene = get(slot)
	if scene == null:
		return null
	var visual: EntityVisual = scene.instantiate() as EntityVisual
	if visual == null:
		push_error("VisualSet: slot '%s' root is not an EntityVisual." % slot)
		return null
	visual.scale = Vector2.ONE * get_visual_scale(slot)
	return visual
