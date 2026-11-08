class_name ThrowIcons
extends RefCounted
## Icons shared by both throw schemes. Each one shows what a throw does by the target kind.

const STACK: Texture2D = preload("res://assets/icons/throw_stack.svg")
const PASS: Texture2D = preload("res://assets/icons/throw_pass.svg")
const HIT: Texture2D = preload("res://assets/icons/throw_hit.svg")
const CANCEL: Texture2D = preload("res://assets/icons/throw_cancel.svg")


## Icons indexed by [enum ThrowScheme.TargetKind]: stack, friend (pass), foe (hit), none.
static func kind_icons() -> Array[Texture2D]:
	var icons: Array[Texture2D] = [STACK, PASS, HIT, CANCEL]
	return icons
