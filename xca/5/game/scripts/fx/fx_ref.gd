class_name FxRef
extends RefCounted
## Finds the [FxLayer] of the running match by group, so scripts compile and run in a test with no layer.
## The group name repeats [constant FxLayer.GROUP] because a test project may not hold the layer script.
## Every call does nothing when no layer exists.

const GROUP: StringName = &"fx_layer"


## The layer of the running match, or null.
static func node() -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.get_first_node_in_group(GROUP)


## Starts the particle burst [param kind] at [param world_position] in arena pixels.
static func burst(kind: StringName, world_position: Vector2, tint: Color = Color.WHITE) -> void:
	var layer: Node = node()
	if layer != null:
		layer.call("burst", kind, world_position, tint)
