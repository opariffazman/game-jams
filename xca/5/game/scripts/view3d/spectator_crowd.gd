class_name SpectatorCrowd
extends Node3D
## Audience on the tournament stands. Each spectator plays a looping Kenney clip, baked into a few mesh frames per model and variant.
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
## Clip per animation variant. The idle clip keeps the arms wide, so these clips bring them in. interact moves the arms like a cheer.
const VARIANT_CLIPS: Array[StringName] = [&"holding-both", &"interact-right", &"interact-left"]
const FRAMES_PER_CLIP: int = 8
const FRAMES_PER_SECOND: float = 8.0

## One spectator: ground position, standing height of the tier, model size in pixels and yaw.
class Spot:
	var at: Vector3
	var size: float
	var yaw: float
	var phase: float
	var speed: float
	var model: int
	var variant: int

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
		entry.variant = (index * 7 + int(absf(spot.x) * 0.05)) % VARIANT_CLIPS.size()
		var key: int = entry.model * VARIANT_CLIPS.size() + entry.variant
		if not by_model.has(key):
			by_model[key] = [] as Array[Spot]
		(by_model[key] as Array[Spot]).append(entry)
	for key: int in by_model:
		var variant: int = key % VARIANT_CLIPS.size()
		_add_group(MODELS[key / VARIANT_CLIPS.size()], by_model[key] as Array[Spot], variant)
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
	_show_frames()
	_update_all()


# Spectators face straight across their stand toward the pitch. Aiming at the field centre fans the far ends out and looks skewed.
func _facing_yaw(at: Vector3) -> float:
	if absf(at.x) > absf(at.z):
		return -PI * 0.5 * signf(at.x)
	return 0.0


func _add_group(model_name: String, spots: Array[Spot], variant: int) -> void:
	var packed: PackedScene = load(MODEL_DIR + model_name + ".glb") as PackedScene
	if packed == null:
		return
	var root: Node = packed.instantiate()
	# Baking the skinned parts needs the skeleton inside the tree.
	add_child(root)
	var sources: Array[MeshInstance3D] = []
	for candidate: Node in root.find_children("*", "MeshInstance3D", true, false):
		sources.append(candidate as MeshInstance3D)
	var frames: Array[Array] = []
	for source: MeshInstance3D in sources:
		frames.append([])
	var player: AnimationPlayer = root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var clip_name: StringName = VARIANT_CLIPS[variant]
	var clip: Animation = null
	var clip_length: float = 0.0
	if player != null and player.has_animation(clip_name):
		clip = player.get_animation(clip_name)
		clip_length = clip.length
	var frame_count: int = FRAMES_PER_CLIP if clip_length > 0.0 else 1
	for frame: int in frame_count:
		if clip != null:
			_pose_bones(root, clip, clip_length * float(frame) / float(frame_count))
		for part_index: int in sources.size():
			frames[part_index].append(_bake(sources[part_index]))
	var parts: Array[MultiMesh] = []
	for part_index: int in sources.size():
		var multi: MultiMesh = MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = frames[part_index][0]
		multi.instance_count = spots.size()
		var holder: MultiMeshInstance3D = MultiMeshInstance3D.new()
		holder.multimesh = multi
		holder.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(holder)
		parts.append(multi)
	root.queue_free()
	var offset: int = (model_name.hash() + variant * 3) % frame_count
	_groups.append({"spots": spots, "parts": parts, "frames": frames, "offset": offset, "shown": 0})


# An AnimationPlayer applies a pose only on a processed frame, and the crowd bakes in the frame it is built.
# Sampling the clip tracks onto the bones sets the pose at once.
func _pose_bones(root: Node, clip: Animation, time: float) -> void:
	for track: int in clip.get_track_count():
		var path: NodePath = clip.track_get_path(track)
		var skeleton: Skeleton3D = root.get_node_or_null(NodePath(path.get_concatenated_names())) as Skeleton3D
		if skeleton == null:
			continue
		var bone: int = skeleton.find_bone(path.get_concatenated_subnames())
		if bone < 0:
			continue
		match clip.track_get_type(track):
			Animation.TYPE_POSITION_3D:
				skeleton.set_bone_pose_position(bone, clip.position_track_interpolate(track, time))
			Animation.TYPE_ROTATION_3D:
				skeleton.set_bone_pose_rotation(bone, clip.rotation_track_interpolate(track, time))
			Animation.TYPE_SCALE_3D:
				skeleton.set_bone_pose_scale(bone, clip.scale_track_interpolate(track, time))


# A baked mesh keeps no materials, so the colormap material is copied back or the crowd draws white.
func _bake(source: MeshInstance3D) -> Mesh:
	var baked: Mesh = source.bake_mesh_from_current_skeleton_pose()
	if baked == null:
		return source.mesh
	for surface: int in baked.get_surface_count():
		baked.surface_set_material(surface, source.get_active_material(surface))
	return baked


func _show_frames() -> void:
	for group: Dictionary in _groups:
		var frames: Array = group["frames"]
		var count: int = (frames[0] as Array).size()
		if count < 2:
			continue
		var shown: int = (int(_elapsed * FRAMES_PER_SECOND) + int(group["offset"])) % count
		if shown == int(group["shown"]):
			continue
		group["shown"] = shown
		var parts: Array = group["parts"]
		for part_index: int in parts.size():
			(parts[part_index] as MultiMesh).mesh = (frames[part_index] as Array)[shown]


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
