class_name KampongScenery
extends RefCounted
## Kampong village dressing for the 3D arena: sand floor tiles, fence ring, lanterns, flags, trees, huts and ground patches.
##
## Every prop sits outside the play field. The camera shows only a thin strip beyond the field, so front
## props stay low (a tall prop in front rises up the screen over the field) and tall props go to the sides.
## One [MultiMeshInstance3D] per model keeps the node count low. The layout is fixed, never random.

const FOREST_DIR: String = "res://assets/kenney/forest/"
const FOREST_TEXTURE: String = "res://assets/kenney/forest/Textures/colormap.png"
const ARENA_DIR: String = "res://assets/kenney/arena/"
const ARENA_TEXTURE: String = "res://assets/kenney/arena/Textures/colormap.png"

const GRASS_COLOR: Color = Color("1f7a45")
const PATCH_TINT: Color = Color(1.0, 1.0, 1.0)
## Multiplier on the sand floor colour. It turns the tile into a bright lime pitch that stays clear of the darker green surround.
const FLOOR_TINT: Color = Color(0.5, 1.0, 0.6)
const FLOOR_TILE: float = 120.0
const FLOOR_LIFT: float = 0.0
const GRASS_PATCH_SIZE: float = 70.0
const DIRT_PATCH_SIZE: float = 60.0
const DETAIL_SIZE: float = 52.0
const FRONT_FENCE_SHARE: float = 0.55
const LANTERN_COLOR: Color = Color("ffb347")
const POST_COLOR: Color = Color("4a3322")

const FENCE_UNITS: float = 1.1
const FENCE_STEP: float = 64.0
const FENCE_OFFSET: float = 14.0
const GROUND_MARGIN: float = 400.0

var _stretch: float
var _forest_material: StandardMaterial3D
var _arena_material: StandardMaterial3D
var _transforms: Dictionary = {}


func _init(stretch: float) -> void:
	_stretch = stretch
	_forest_material = _textured(FOREST_TEXTURE, Color.WHITE)
	_arena_material = _textured(ARENA_TEXTURE, Color.WHITE)


## Builds all scenery under [param parent]. [param half] is the half extent of the play field in pixels.
func build(parent: Node3D, half: Vector2) -> void:
	layout(half)
	_add_grass(parent, half)
	for path: String in _transforms:
		var material: StandardMaterial3D = _arena_material if path.begins_with(ARENA_DIR) else _forest_material
		var tint: Color = Color.WHITE
		if path.ends_with("patch-grass.glb") or path.ends_with("patch-dirt.glb"):
			tint = PATCH_TINT
		elif path.begins_with(ARENA_DIR + "floor"):
			tint = FLOOR_TINT
		var instance_material: StandardMaterial3D = material
		if tint != Color.WHITE:
			instance_material = material.duplicate() as StandardMaterial3D
			instance_material.albedo_color = tint
		_add_multi(parent, path, instance_material)
	_add_lanterns(parent, half)


## Fills and returns the placements per model path. The test reads this because headless MultiMesh keeps no transforms.
func layout(half: Vector2) -> Dictionary:
	_transforms.clear()
	_add_fence(half)
	_add_flags(half)
	_add_sides(half)
	_add_front(half)
	_add_patches(half)
	return _transforms


func _add_grass(parent: Node3D, half: Vector2) -> void:
	var ground: MeshInstance3D = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = (half * 2.0) + Vector2.ONE * GROUND_MARGIN
	ground.mesh = plane
	ground.material_override = MeshBuilder3D.flat_material(GRASS_COLOR)
	ground.position.y = -1.0
	ground.scale = Vector3(1.0, 1.0, 1.0 / _stretch)
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(ground)


func _add_fence(half: Vector2) -> void:
	var piece_scale: float = FENCE_STEP / FENCE_UNITS * 1.25
	var x: float = -half.x + FENCE_STEP * 0.5
	while x < half.x:
		_place("fence.glb", Vector3(x, 0.0, -(half.y + FENCE_OFFSET) * _stretch), 0.0, piece_scale)
		_place("fence.glb", Vector3(x, 0.0, (half.y + FENCE_OFFSET) * _stretch), 0.0, piece_scale * FRONT_FENCE_SHARE)
		x += FENCE_STEP
	var y: float = -half.y + FENCE_STEP * 0.5
	while y < half.y:
		_place("fence.glb", Vector3(-(half.x + FENCE_OFFSET), 0.0, y * _stretch), PI * 0.5, piece_scale)
		_place("fence.glb", Vector3(half.x + FENCE_OFFSET, 0.0, y * _stretch), PI * 0.5, piece_scale * FRONT_FENCE_SHARE)
		y += FENCE_STEP


func _add_flags(half: Vector2) -> void:
	var flag_size: float = 70.0
	for x: float in [-320.0, -160.0, 160.0, 320.0]:
		_place("flag.glb", Vector3(x, 0.0, -(half.y + FENCE_OFFSET) * _stretch), 0.0, flag_size)
	for y: float in [-150.0, 150.0]:
		_place("flag.glb", Vector3(-(half.x + FENCE_OFFSET), 0.0, y * _stretch), 0.0, flag_size)
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			var front: bool = sx + sy > 0.0
			_place("flag.glb", Vector3(sx * (half.x + FENCE_OFFSET), 0.0, sy * (half.y + FENCE_OFFSET) * _stretch), 0.0, flag_size * (0.6 if front else 1.0))
	for x: float in [-480.0, 480.0, -240.0, 240.0, 0.0]:
		_place("banner.glb", Vector3(x, 0.0, -(half.y + 30.0) * _stretch), 0.0, 64.0, ARENA_DIR)


# The camera looks from the +x +z side, so the back edges (-x and -z) rise up the screen and hold the tall props.
# The two side tips of the diamond are left free of anything high so the corners stay readable.
func _add_sides(half: Vector2) -> void:
	var tall: bool = true
	for y: float in [-220.0, -90.0, 60.0]:
		var at: Vector3 = Vector3(-(half.x + 70.0), 0.0, y * _stretch)
		_place("tree-high.glb" if tall else "tree.glb", at, y * 0.013, 62.0)
		tall = not tall
	for x: float in [-400.0, -260.0, -120.0, 20.0, 160.0, 300.0, 440.0]:
		var at: Vector3 = Vector3(x, 0.0, -(half.y + 70.0) * _stretch)
		_place("tree-high.glb" if tall else "tree.glb", at, x * 0.013, 62.0)
		tall = not tall
	_place("tent.glb", Vector3(-(half.x + 70.0), 0.0, 190.0 * _stretch), PI * 0.5, 62.0)
	_place("building-platform.glb", Vector3(half.x - 120.0, 0.0, -(half.y + 90.0) * _stretch), 0.0, 60.0)
	_place("building-structure.glb", Vector3(half.x - 120.0, 30.0, -(half.y + 90.0) * _stretch), 0.0, 60.0)
	_place("building-roof.glb", Vector3(half.x - 120.0, 90.0, -(half.y + 90.0) * _stretch), 0.0, 60.0)


# Front props stay low because they rise toward the field from the near edges.
func _add_front(half: Vector2) -> void:
	var z: float = (half.y + 34.0) * _stretch
	for x: float in [-480.0, -380.0, -210.0, -60.0, 90.0, 250.0, 400.0, 500.0]:
		_place("plant.glb", Vector3(x, 0.0, z), x * 0.01, 40.0)
	for x: float in [-310.0, 20.0, 330.0]:
		_place("stones.glb", Vector3(x, 0.0, z), x * 0.02, 40.0)
	for y: float in [-250.0, -120.0, 20.0, 150.0, 260.0]:
		_place("plant.glb", Vector3(half.x + 34.0, 0.0, y * _stretch), y * 0.01, 40.0)
	for y: float in [-170.0, 90.0]:
		_place("rocks-low.glb", Vector3(half.x + 34.0, 0.0, y * _stretch), y * 0.03, 36.0)


# Floor tiles, grass patches and low dressing sit on the field. They keep clear of the throw ring and the centre,
# so characters and sandals never stand on a prop. They are flat or a few pixels high.
func _add_patches(half: Vector2) -> void:
	for tile: Vector2 in floor_tiles(half):
		_place_floor("floor.glb", Vector3(tile.x, FLOOR_LIFT, tile.y * _stretch), 0.0, FLOOR_TILE)
	for spot: Vector4 in dressing_spots(half):
		var at: Vector3 = Vector3(spot.x, FLOOR_LIFT + 0.4, spot.y * _stretch)
		match int(spot.w):
			0:
				_place_floor("patch-grass.glb", at, spot.z, GRASS_PATCH_SIZE)
			1:
				_place_floor("floor-detail.glb", at, spot.z, DETAIL_SIZE)
			2:
				_place_floor("patch-dirt.glb", at, spot.z, DIRT_PATCH_SIZE)


## Centres of the sand floor tiles. The tiles cover the play field and stop at its edge.
func floor_tiles(half: Vector2) -> Array[Vector2]:
	var tiles: Array[Vector2] = []
	var columns: int = ceili(half.x * 2.0 / FLOOR_TILE)
	var rows: int = ceili(half.y * 2.0 / FLOOR_TILE)
	for row: int in rows:
		for column: int in columns:
			tiles.append(Vector2(-half.x + FLOOR_TILE * (float(column) + 0.5), -half.y + FLOOR_TILE * (float(row) + 0.5)))
	return tiles


## Fixed set dressing spots on the floor as (x, y, yaw, kind). Kind 0 is a grass patch, 1 a pebble tile, 2 a dirt patch.
## Every spot is far from the throw ring and the centre, and close to a field edge.
func dressing_spots(half: Vector2) -> Array[Vector4]:
	var spots: Array[Vector4] = []
	var inset_x: float = half.x - 70.0
	var inset_y: float = half.y - 55.0
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			spots.append(Vector4(sx * inset_x, sy * inset_y, sx * 0.7, 0.0))
	spots.append(Vector4(-290.0, -inset_y, 0.3, 0.0))
	spots.append(Vector4(260.0, inset_y, 1.1, 0.0))
	spots.append(Vector4(inset_x - 90.0, 20.0, 0.0, 2.0))
	spots.append(Vector4(-inset_x + 80.0, 90.0, 0.5, 2.0))
	for point: Vector2 in [Vector2(-380.0, -inset_y + 10.0), Vector2(330.0, -inset_y + 6.0), Vector2(-340.0, inset_y - 4.0), Vector2(inset_x - 30.0, -150.0), Vector2(-inset_x + 24.0, -60.0), Vector2(inset_x - 24.0, 170.0)]:
		spots.append(Vector4(point.x, point.y, point.x * 0.02, 1.0))
	return spots


func _add_lanterns(parent: Node3D, half: Vector2) -> void:
	var spots: Array[Vector2] = [
		Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(-half.x, half.y), Vector2(half.x, half.y),
		Vector2(-half.x, 0.0), Vector2(half.x, 0.0), Vector2(0.0, -half.y), Vector2(0.0, half.y),
	]
	var posts: Array[Transform3D] = []
	var bulbs: Array[Transform3D] = []
	var post_height: float = 48.0
	for spot: Vector2 in spots:
		var outward: Vector2 = Vector2(signf(spot.x), signf(spot.y))
		var at: Vector3 = Vector3(spot.x + outward.x * FENCE_OFFSET * 1.8, 0.0, (spot.y + outward.y * FENCE_OFFSET * 1.8) * _stretch)
		posts.append(Transform3D(Basis.IDENTITY, at + Vector3(0.0, post_height * 0.5, 0.0)))
		bulbs.append(Transform3D(Basis.IDENTITY, at + Vector3(0.0, post_height + 5.0, 0.0)))
	var post_mesh: CylinderMesh = CylinderMesh.new()
	post_mesh.top_radius = 2.5
	post_mesh.bottom_radius = 2.5
	post_mesh.height = post_height
	post_mesh.radial_segments = 6
	post_mesh.rings = 1
	var bulb_mesh: SphereMesh = SphereMesh.new()
	bulb_mesh.radius = 9.0
	bulb_mesh.height = 18.0
	bulb_mesh.radial_segments = 8
	bulb_mesh.rings = 4
	_add_multi_mesh(parent, post_mesh, posts, MeshBuilder3D.flat_material(POST_COLOR))
	_add_multi_mesh(parent, bulb_mesh, bulbs, MeshBuilder3D.flat_material(LANTERN_COLOR))


func _place_floor(model: String, at: Vector3, yaw: float, size: float) -> void:
	_place(model, at, yaw, size, ARENA_DIR if model.begins_with("floor") else FOREST_DIR)


func _place(model: String, at: Vector3, yaw: float, size: float, dir: String = FOREST_DIR) -> void:
	var path: String = dir + model
	if not _transforms.has(path):
		_transforms[path] = [] as Array[Transform3D]
	var basis: Basis = Basis(Vector3.UP, yaw).scaled(Vector3.ONE * size)
	(_transforms[path] as Array[Transform3D]).append(Transform3D(basis, at))


func _add_multi(parent: Node3D, path: String, material: StandardMaterial3D) -> void:
	var mesh: Mesh = first_mesh(path)
	if mesh != null:
		_add_multi_mesh(parent, mesh, _transforms[path] as Array[Transform3D], material)


func _add_multi_mesh(parent: Node3D, mesh: Mesh, transforms: Array[Transform3D], material: Material) -> void:
	var multi: MultiMesh = MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = transforms.size()
	for index: int in transforms.size():
		multi.set_instance_transform(index, transforms[index])
	var holder: MultiMeshInstance3D = MultiMeshInstance3D.new()
	holder.multimesh = multi
	holder.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.material_override = material
	parent.add_child(holder)


func _textured(path: String, tint: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_texture = load(path) as Texture2D
	material.albedo_color = tint
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	material.roughness = 1.0
	return material


static func first_mesh(path: String) -> Mesh:
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		return null
	var root: Node = packed.instantiate()
	var found: MeshInstance3D = null
	for candidate: Node in root.find_children("*", "MeshInstance3D", true, false):
		found = candidate as MeshInstance3D
		break
	var mesh: Mesh = found.mesh if found != null else null
	root.free()
	return mesh
