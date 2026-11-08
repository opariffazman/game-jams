class_name SpectatorCrowd
extends Node3D
## Audience on the tournament stands. Each spectator is an instance of a Kenney character in its rest pose.
##
## One [MultiMeshInstance3D] per model part keeps the draw calls low. A timer bobs the crowd at a low rate, so the
## cost stays a few hundred transform writes per second. The crowd has no outline and casts no shadow.

const MODEL_DIR: String = "res://assets/kenney/characters/"
const MODELS: Array[String] = [
	"character-male-a", "character-female-a", "character-male-c", "character-female-c",
	"character-male-e", "character-female-e", "character-male-g", "character-female-b",
	"character-male-b", "character-female-d", "character-male-d", "character-female-f",
]
const TICK_SECONDS: float = 1.0 / 15.0
const BOB_HEIGHT: float = 4.0
const SWAY_RADIANS: float = 0.12
const FIRST_SPEED: float = 4.0
const SPEED_SPREAD: float = 5.0

## One spectator: ground position, standing height of the tier, model size in pixels and yaw.
class Spot:
	var at: Vector3
	var size: float
	var yaw: float
	var phase: float
	var speed: float
	var model: int

var _groups: Array[Dictionary] = []
var _clock: float = 0.0
var _elapsed: float = 0.0


## Builds the crowd for [param spots], given as (x, z, height, size) with the model chosen by index.
func build(spots: Array[Vector4], stretch: float) -> void:
	var by_model: Dictionary = {}
	for index: int in spots.size():
		var spot: Vector4 = spots[index]
		var entry: Spot = Spot.new()
		entry.at = Vector3(spot.x, spot.z, spot.y * stretch)
		entry.size = spot.w
		entry.yaw = _facing_yaw(entry.at)
		entry.phase = fmod(float(index) * 2.399, TAU)
		entry.speed = FIRST_SPEED + fmod(float(index) * 1.618, 1.0) * SPEED_SPREAD
		entry.model = (index * 5 + int(absf(spot.x) * 0.1)) % MODELS.size()
		if not by_model.has(entry.model):
			by_model[entry.model] = [] as Array[Spot]
		(by_model[entry.model] as Array[Spot]).append(entry)
	for model_index: int in by_model:
		_add_group(MODELS[model_index], by_model[model_index] as Array[Spot])
	_update_all()


## Number of spectators across all groups.
func spectator_count() -> int:
	var total: int = 0
	for group: Dictionary in _groups:
		total += (group["spots"] as Array[Spot]).size()
	return total


func _process(delta: float) -> void:
	_clock += delta
	if _clock < TICK_SECONDS:
		return
	_elapsed += _clock
	_clock = 0.0
	_update_all()


# Spectators face straight across their stand toward the pitch. Aiming at the field centre fans the far ends out and looks skewed.
func _facing_yaw(at: Vector3) -> float:
	if absf(at.x) > absf(at.z):
		return -PI * 0.5 * signf(at.x)
	return 0.0


func _add_group(model_name: String, spots: Array[Spot]) -> void:
	var packed: PackedScene = load(MODEL_DIR + model_name + ".glb") as PackedScene
	if packed == null:
		return
	var root: Node = packed.instantiate()
	# Baking the skinned parts needs the skeleton inside the tree.
	add_child(root)
	var parts: Array[MultiMesh] = []
	for candidate: Node in root.find_children("*", "MeshInstance3D", true, false):
		var source: MeshInstance3D = candidate as MeshInstance3D
		var multi: MultiMesh = MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		var baked: Mesh = source.bake_mesh_from_current_skeleton_pose()
		if baked == null:
			baked = source.mesh
		else:
			# A baked mesh keeps no materials, so copy the colormap material back or the crowd draws white.
			for surface: int in baked.get_surface_count():
				baked.surface_set_material(surface, source.get_active_material(surface))
		multi.mesh = baked
		multi.instance_count = spots.size()
		var holder: MultiMeshInstance3D = MultiMeshInstance3D.new()
		holder.multimesh = multi
		holder.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(holder)
		parts.append(multi)
	root.queue_free()
	_groups.append({"spots": spots, "parts": parts})


func _update_all() -> void:
	for group: Dictionary in _groups:
		var spots: Array[Spot] = group["spots"] as Array[Spot]
		var parts: Array[MultiMesh] = group["parts"] as Array[MultiMesh]
		for index: int in spots.size():
			var spot: Spot = spots[index]
			var hop: float = absf(sin(_elapsed * spot.speed + spot.phase)) * BOB_HEIGHT
			var sway: float = sin(_elapsed * spot.speed * 0.5 + spot.phase) * SWAY_RADIANS
			var basis: Basis = (Basis(Vector3.UP, spot.yaw) * Basis(Vector3.FORWARD, sway)).scaled(Vector3.ONE * spot.size)
			var placed: Transform3D = Transform3D(basis, spot.at + Vector3(0.0, hop, 0.0))
			for part: MultiMesh in parts:
				part.set_instance_transform(index, placed)
