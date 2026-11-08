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

const GRASS_COLOR: Color = Color("3d8f47")
const PATCH_TINT: Color = Color(0.55, 0.78, 0.5)
## Multiplier on the sand floor colour. It turns the tile into a bright lime pitch that stays clear of the darker green surround.
const FLOOR_TINT: Color = Color(0.42, 0.85, 0.5)
## Multiplier on the stand blocks. It darkens the wood so the spectators stand out.
const STAND_TINT: Color = Color(0.62, 0.52, 0.42)
## Share of seats left empty so the stands look lived in.
const EMPTY_SEAT_SHARE: float = 0.25
const FLOOR_TILE: float = 120.0
const FLOOR_LIFT: float = 0.0
const GRASS_PATCH_SIZE: float = 70.0
const DIRT_PATCH_SIZE: float = 60.0
const DETAIL_SIZE: float = 52.0
const FRONT_FENCE_SHARE: float = 0.55
const LANTERN_COLOR: Color = Color("ffb347")
const POST_COLOR: Color = Color("4a3322")

const FRIENDLY_COLOR: Color = Color("40bfff")
const ENEMY_COLOR: Color = Color("ff5230")
const CREAM_COLOR: Color = Color("fff1c9")
const STRAW_COLOR: Color = Color("e0b84e")
const STRAW_BAND_COLOR: Color = Color("b8862f")
const POLE_COLOR: Color = Color("6b4a2b")

## Stand tiers: first distance from the field edge, depth and height step of each tier. Heights rise with every tier.
const STAND_GAP: float = 14.0
const STAND_TIER_DEPTH: float = 40.0
const STAND_TIER_HEIGHT: float = 16.0
const BACK_TIERS: int = 2
const SIDE_TIERS: int = 0
const STAND_OVERHANG: float = 40.0
const SPECTATOR_SPACING: float = 72.0
const SPECTATOR_SIZE: float = 92.0
const WALL_SIZE: float = 44.0
const CANOPY_HEIGHT: float = 62.0
const CANOPY_RADIUS: float = 78.0
const CANOPY_RISE: float = 30.0
const CANOPY_SEGMENTS: int = 12
const BUNTING_FLAG_WIDTH: float = 11.0
const BUNTING_FLAG_DROP: float = 13.0
const BUNTING_SAG: float = 9.0

## Dirt apron between the pitch edge and the stands, and the stripe tint of the mown pitch.
const DIRT_COLOR: Color = Color("c08a55")
const DIRT_WIDTH: float = 46.0
const DIRT_LIFT: float = -0.4
const MOWN_LIGHT: Color = Color("459a4a")
const MOWN_DARK: Color = Color("29683a")
## Fake ambient occlusion: darkness at the foot of stands and inside the pitch edge, and under props.
const AO_LIFT: float = 0.7
const AO_STAND_ALPHA: float = 0.5
const AO_STAND_WIDTH: float = 34.0
const AO_EDGE_ALPHA: float = 0.2
const AO_EDGE_WIDTH: float = 46.0
const AO_PROP_ALPHA: float = 0.42
const PAVILION_SIZE: float = 64.0
## Contact shadow radius under a prop, as a share of the prop size.
const CONTACT_RADIUS: Dictionary = {
	"tree-high.glb": 0.5, "tree.glb": 0.5, "tent.glb": 0.7, "weapon-rack.glb": 0.55, "target.glb": 0.4,
	"column.glb": 0.45, "statue.glb": 0.5, "building-platform.glb": 0.6, "stones.glb": 0.5, "rocks-low.glb": 0.5,
}

const FENCE_UNITS: float = 1.1
const FENCE_STEP: float = 64.0
const FENCE_OFFSET: float = 14.0
const GROUND_MARGIN: float = 900.0

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
	_add_apron(parent, half)
	for path: String in _transforms:
		if path.ends_with("/floor.glb"):
			_add_striped_floor(parent, path, half)
			continue
		var material: StandardMaterial3D = _arena_material if path.begins_with(ARENA_DIR) else _forest_material
		var tint: Color = Color.WHITE
		if path.ends_with("patch-grass.glb") or path.ends_with("patch-dirt.glb"):
			tint = PATCH_TINT
		elif path.begins_with(ARENA_DIR + "floor"):
			tint = FLOOR_TINT
		elif path.ends_with("/block.glb"):
			tint = STAND_TINT
		var instance_material: StandardMaterial3D = material
		if tint != Color.WHITE:
			instance_material = material.duplicate() as StandardMaterial3D
			instance_material.albedo_color = tint
		_add_multi(parent, path, instance_material)
	_add_lanterns(parent, half)
	_add_flat_dressing(parent, half)
	_add_crowd(parent, half)
	_add_occlusion(parent, half)


## Fills and returns the placements per model path. The test reads this because headless MultiMesh keeps no transforms.
func layout(half: Vector2) -> Dictionary:
	_transforms.clear()
	_add_fence(half)
	_add_flags(half)
	_add_stands(half)
	_add_sides(half)
	_add_front(half)
	_add_patches(half)
	_add_landmarks(half)
	_add_hedge(half)
	return _transforms


func _add_grass(parent: Node3D, half: Vector2) -> void:
	var ground: MeshInstance3D = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = (half * 2.0) + Vector2.ONE * GROUND_MARGIN
	ground.mesh = plane
	ground.material_override = MeshBuilder3D.lit_material(GRASS_COLOR)
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


# The camera looks from the +x +z side, so the back edges (-x and -z) rise up the screen and hold the tall props.
# The two side tips of the diamond are left free of anything high so the corners stay readable.
func _add_sides(half: Vector2) -> void:
	var far: float = half.y + STAND_GAP + STAND_TIER_DEPTH * BACK_TIERS + 30.0
	for x: float in [-half.x - 90.0, half.x + 90.0]:
		_place("tree-high.glb", Vector3(x, 0.0, -far * _stretch), x * 0.013, 62.0)
	_place("tent.glb", Vector3(-(half.x + 70.0), 0.0, 190.0 * _stretch), PI * 0.5, 50.0)
	_place("weapon-rack.glb", Vector3(half.x + 52.0, 0.0, 160.0 * _stretch), -PI * 0.5, 56.0, ARENA_DIR)
	_place("weapon-rack.glb", Vector3(-(half.x + 52.0), 0.0, 120.0 * _stretch), PI * 0.5, 56.0, ARENA_DIR)
	_place("target.glb", Vector3(half.x + 52.0, 0.0, 70.0 * _stretch), -PI * 0.5, 50.0)
	_place("target.glb", Vector3(-(half.x + 52.0), 0.0, 60.0 * _stretch), PI * 0.5, 50.0)


# Tiered blocks behind the far edge and along both sides, a stone wall behind the far stand and its gate in the middle.
func _add_stands(half: Vector2) -> void:
	var width: float = half.x * 2.0 + STAND_OVERHANG * 2.0
	for tier: int in BACK_TIERS:
		var height: float = STAND_TIER_HEIGHT * float(tier + 1)
		var edge: float = half.y + STAND_GAP + STAND_TIER_DEPTH * float(tier)
		_place_box("block.glb", Vector3(0.0, 0.0, -(edge + STAND_TIER_DEPTH * 0.5) * _stretch), Vector3(width, height / 0.5, STAND_TIER_DEPTH * _stretch))
	var side_length: float = half.y + 20.0
	var side_centre: float = -half.y + side_length * 0.5 - 20.0
	for sign: float in [-1.0, 1.0]:
		for tier: int in SIDE_TIERS:
			var height: float = STAND_TIER_HEIGHT * float(tier + 1)
			var edge: float = half.x + STAND_GAP + STAND_TIER_DEPTH * float(tier)
			_place_box("block.glb", Vector3(sign * (edge + STAND_TIER_DEPTH * 0.5), 0.0, side_centre * _stretch), Vector3(STAND_TIER_DEPTH, height / 0.5, side_length * _stretch))
	var wall_y: float = half.y + STAND_GAP + STAND_TIER_DEPTH * float(BACK_TIERS) + WALL_SIZE * 0.3
	var x: float = -half.x - STAND_OVERHANG + WALL_SIZE * 0.5
	while x < half.x + STAND_OVERHANG:
		var model: String = "wall-gate.glb" if absf(x) < WALL_SIZE * 0.5 else "wall.glb"
		_place(model, Vector3(x, 0.0, -wall_y * _stretch), 0.0, WALL_SIZE, ARENA_DIR)
		x += WALL_SIZE


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


# Statues and banners on the wall behind the far stand, columns at the stand ends and the gate, stairs at the
# stand ends, a pavilion at each far corner and a ring of trees outside. All stand outside the play field.
func _add_landmarks(half: Vector2) -> void:
	var wall_z: float = half.y + STAND_GAP + STAND_TIER_DEPTH * float(BACK_TIERS) + WALL_SIZE * 0.3
	var behind: float = -(wall_z + 26.0) * _stretch
	for x: float in [-360.0, -190.0, 190.0, 360.0]:
		_place("statue.glb", Vector3(x, 0.0, behind), 0.0, 72.0, ARENA_DIR)
	for x: float in [-460.0, -275.0, -100.0, 100.0, 275.0, 460.0]:
		_place("banner.glb", Vector3(x, 12.0, behind - 10.0 * _stretch), 0.0, 80.0, ARENA_DIR)
	for x: float in [-half.x - STAND_OVERHANG + 10.0, -60.0, 60.0, half.x + STAND_OVERHANG - 10.0]:
		_place("column.glb", Vector3(x, 0.0, behind), 0.0, 70.0, ARENA_DIR)
	for sign: float in [-1.0, 1.0]:
		_place_box("stairs.glb", Vector3(sign * (half.x + STAND_OVERHANG + 14.0), 0.0, -(half.y + STAND_GAP + STAND_TIER_DEPTH * 0.5) * _stretch), Vector3(28.0, STAND_TIER_HEIGHT * 2.0, STAND_TIER_DEPTH * 0.7), sign * PI * 0.5)
		var box: Vector3 = Vector3(sign * 480.0, 0.0, behind - 60.0 * _stretch)
		_place("building-platform.glb", box, 0.0, 80.0)
		_place("building-structure.glb", box + Vector3(0.0, 40.0, 0.0), 0.0, 80.0)
		_place("building-roof.glb", box + Vector3(0.0, 120.0, 0.0), 0.0, 80.0)
	for x: float in [-560.0, -420.0, -90.0, 0.0, 90.0, 420.0, 560.0, 640.0, -640.0]:
		_place("tree-high.glb", Vector3(x, 0.0, behind - (130.0 + absf(x) * 0.1) * _stretch), x * 0.01, 80.0)
	for sign: float in [-1.0, 1.0]:
		for y: float in [-110.0, 40.0, 190.0]:
			_place("tree.glb", Vector3(sign * (half.x + STAND_GAP + STAND_TIER_DEPTH + 90.0), 0.0, y * _stretch), y * 0.02, 74.0)
		_place("rocks-low.glb", Vector3(sign * (half.x + 130.0), 0.0, 100.0 * _stretch), sign, 40.0)


# Two rows of trees and bushes close the near edge so no bare ground shows below the field.
func _add_hedge(half: Vector2) -> void:
	var x: float = -half.x - 200.0
	var index: int = 0
	while x <= half.x + 200.0:
		_place("tree.glb" if index % 3 != 0 else "tree-high.glb", Vector3(x, 0.0, (half.y + 120.0 + float(index % 2) * 30.0) * _stretch), float(index) * 0.7, 48.0)
		_place("plant.glb", Vector3(x + 40.0, 0.0, (half.y + 75.0) * _stretch), float(index), 46.0)
		x += 80.0
		index += 1


# Mown stripes: the floor tiles alternate between two tints by column.
func _add_striped_floor(parent: Node3D, path: String, half: Vector2) -> void:
	var even: Array[Transform3D] = []
	var odd: Array[Transform3D] = []
	for placed: Transform3D in _transforms[path]:
		var column: int = roundi((placed.origin.x + half.x) / FLOOR_TILE - 0.5)
		(even if column % 2 == 0 else odd).append(placed)
	var mesh: Mesh = first_mesh(path)
	if mesh == null:
		return
	for group: Array[Transform3D] in [even, odd]:
		var material: StandardMaterial3D = MeshBuilder3D.lit_material(MOWN_LIGHT if group == even else MOWN_DARK)
		_add_multi_mesh(parent, mesh, group, material)


# Four dirt strips frame the pitch between its edge and the stands and fence.
func _add_apron(parent: Node3D, half: Vector2) -> void:
	var builder: SurfaceTool = SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	var inner: Vector2 = half
	var outer: Vector2 = half + Vector2.ONE * DIRT_WIDTH
	var y: float = DIRT_LIFT
	var s: float = _stretch
	_add_quad(builder, Vector3(-outer.x, y, -outer.y * s), Vector3(outer.x, y, -outer.y * s), Vector3(outer.x, y, -inner.y * s), Vector3(-outer.x, y, -inner.y * s), DIRT_COLOR)
	_add_quad(builder, Vector3(-outer.x, y, inner.y * s), Vector3(outer.x, y, inner.y * s), Vector3(outer.x, y, outer.y * s), Vector3(-outer.x, y, outer.y * s), DIRT_COLOR)
	_add_quad(builder, Vector3(-outer.x, y, -inner.y * s), Vector3(-inner.x, y, -inner.y * s), Vector3(-inner.x, y, inner.y * s), Vector3(-outer.x, y, inner.y * s), DIRT_COLOR)
	_add_quad(builder, Vector3(inner.x, y, -inner.y * s), Vector3(outer.x, y, -inner.y * s), Vector3(outer.x, y, inner.y * s), Vector3(inner.x, y, inner.y * s), DIRT_COLOR)
	var holder: MeshInstance3D = MeshInstance3D.new()
	holder.mesh = builder.commit()
	holder.material_override = MeshBuilder3D.flat_material(Color.WHITE, true)
	holder.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(holder)


# Soft dark gradients at the foot of the stands and inside the pitch edge, and a dark blob under each tall prop.
func _add_occlusion(parent: Node3D, half: Vector2) -> void:
	var strips: Array[Transform3D] = []
	var stand_edge: float = half.y + STAND_GAP
	var side_edge: float = half.x + STAND_GAP
	var side_from: float = -half.y - 20.0
	var side_to: float = half.y * 0.4
	strips.append(_strip(Vector3(0.0, AO_LIFT, -(stand_edge - AO_STAND_WIDTH * 0.5) * _stretch), 0.0, half.x * 2.0 + STAND_OVERHANG * 2.0, AO_STAND_WIDTH))
	for sign: float in [-1.0, 1.0]:
		strips.append(_strip(Vector3(sign * (side_edge - AO_STAND_WIDTH * 0.5), AO_LIFT, (side_from + side_to) * 0.5 * _stretch), -sign * PI * 0.5, side_to - side_from, AO_STAND_WIDTH))
	_add_multi_mesh(parent, _unit_quad(), strips, _occlusion_material(_linear_gradient(AO_STAND_ALPHA)))
	var edges: Array[Transform3D] = []
	var lift: float = AO_LIFT + 0.1
	edges.append(_strip(Vector3(0.0, lift, -(half.y - AO_EDGE_WIDTH * 0.5) * _stretch), 0.0, half.x * 2.0, AO_EDGE_WIDTH))
	edges.append(_strip(Vector3(0.0, lift, (half.y - AO_EDGE_WIDTH * 0.5) * _stretch), PI, half.x * 2.0, AO_EDGE_WIDTH))
	edges.append(_strip(Vector3(-(half.x - AO_EDGE_WIDTH * 0.5), lift, 0.0), PI * 0.5, half.y * 2.0, AO_EDGE_WIDTH))
	edges.append(_strip(Vector3(half.x - AO_EDGE_WIDTH * 0.5, lift, 0.0), -PI * 0.5, half.y * 2.0, AO_EDGE_WIDTH))
	_add_multi_mesh(parent, _unit_quad(), edges, _occlusion_material(_linear_gradient(AO_EDGE_ALPHA)))
	var blobs: Array[Transform3D] = []
	for path: String in _transforms:
		var radius: float = float(CONTACT_RADIUS.get(path.get_file(), 0.0))
		if radius <= 0.0:
			continue
		for placed: Transform3D in _transforms[path]:
			var diameter: float = placed.basis.x.length() * radius * 2.0
			blobs.append(Transform3D(Basis.from_scale(Vector3(diameter, 1.0, diameter)), Vector3(placed.origin.x, placed.origin.y + AO_LIFT + 0.2, placed.origin.z)))
	if not blobs.is_empty():
		_add_multi_mesh(parent, _unit_quad(), blobs, _occlusion_material(_radial_gradient(AO_PROP_ALPHA)))


## A strip on the floor, dark at its local -z edge and clear at +z. [param yaw] turns the dark edge toward the wall.
func _strip(centre: Vector3, yaw: float, length: float, width: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(length, 1.0, width)), centre)


func _unit_quad() -> PlaneMesh:
	var quad: PlaneMesh = PlaneMesh.new()
	quad.size = Vector2.ONE
	return quad


func _occlusion_material(texture: Texture2D) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_texture = texture
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	return material


func _linear_gradient(alpha: float) -> GradientTexture2D:
	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.gradient = _fade(alpha)
	texture.fill = GradientTexture2D.FILL_LINEAR
	texture.fill_from = Vector2(0.0, 0.0)
	texture.fill_to = Vector2(0.0, 1.0)
	texture.width = 4
	texture.height = 64
	return texture


func _radial_gradient(alpha: float) -> GradientTexture2D:
	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.gradient = _fade(alpha)
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 64
	texture.height = 64
	return texture


func _fade(alpha: float) -> Gradient:
	var gradient: Gradient = Gradient.new()
	gradient.set_color(0, Color(0.05, 0.03, 0.08, alpha))
	gradient.set_color(1, Color(0.05, 0.03, 0.08, 0.0))
	return gradient


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


# Cheap flat-shaded pieces that Kenney has no model for: team bunting, standards, the striped canopy and hay bales.
func _add_flat_dressing(parent: Node3D, half: Vector2) -> void:
	var builder: SurfaceTool = SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_bunting(builder, half)
	_add_standards(builder, half)
	_add_canopy(builder, half)
	var mesh: ArrayMesh = builder.commit()
	var holder: MeshInstance3D = MeshInstance3D.new()
	holder.mesh = mesh
	holder.material_override = MeshBuilder3D.flat_material(Color.WHITE, true)
	holder.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(holder)
	_add_hay(parent, half)


func _add_tri(builder: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	for point: Vector3 in [a, b, c]:
		builder.set_color(color)
		builder.add_vertex(point)


func _add_quad(builder: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	_add_tri(builder, a, b, c, color)
	_add_tri(builder, a, c, d, color)


func _bunting_colour(index: int) -> Color:
	return [FRIENDLY_COLOR, CREAM_COLOR, ENEMY_COLOR, CREAM_COLOR][index % 4]


# One string of pennants hangs between two points and sags in the middle.
func _add_bunting_string(builder: SurfaceTool, from: Vector3, to: Vector3) -> void:
	var count: int = maxi(int(from.distance_to(to) / (BUNTING_FLAG_WIDTH * 1.6)), 2)
	var along: Vector3 = (to - from).normalized()
	for index: int in count:
		var t0: float = float(index) / float(count)
		var t1: float = (float(index) + 0.8) / float(count)
		var top0: Vector3 = _bunting_point(from, to, t0)
		var top1: Vector3 = _bunting_point(from, to, t1)
		var tip: Vector3 = (top0 + top1) * 0.5 + Vector3(0.0, -BUNTING_FLAG_DROP, 0.0) + along * 0.0
		_add_tri(builder, top0, top1, tip, _bunting_colour(index))


func _bunting_point(from: Vector3, to: Vector3, t: float) -> Vector3:
	return from.lerp(to, t) + Vector3(0.0, -BUNTING_SAG * 4.0 * t * (1.0 - t), 0.0)


# Strings run between the standards along the far stand and both side stands, above the crowd's heads.
func _add_bunting(builder: SurfaceTool, half: Vector2) -> void:
	var far: float = (half.y + STAND_GAP - 4.0) * _stretch
	var height: float = 92.0
	var count: int = 6
	for index: int in count:
		var x0: float = lerpf(-half.x - STAND_OVERHANG, half.x + STAND_OVERHANG, float(index) / float(count))
		var x1: float = lerpf(-half.x - STAND_OVERHANG, half.x + STAND_OVERHANG, float(index + 1) / float(count))
		_add_bunting_string(builder, Vector3(x0, height, -far), Vector3(x1, height, -far))
	for sign: float in [-1.0, 1.0]:
		var near: float = sign * (half.x + STAND_GAP - 4.0)
		for index: int in 4:
			var y0: float = lerpf(-half.y, half.y * 0.4, float(index) / 4.0)
			var y1: float = lerpf(-half.y, half.y * 0.4, float(index + 1) / 4.0)
			_add_bunting_string(builder, Vector3(near, height, y0 * _stretch), Vector3(near, height, y1 * _stretch))


# A standard is a thin pole with a swallow-tail pennant, blue on the left half of the stands and red on the right.
func _add_standards(builder: SurfaceTool, half: Vector2) -> void:
	var far: float = (half.y + STAND_GAP - 4.0) * _stretch
	var spots: Array[Vector3] = []
	for index: int in 7:
		spots.append(Vector3(lerpf(-half.x - STAND_OVERHANG, half.x + STAND_OVERHANG, float(index) / 6.0), 0.0, -far))
	for sign: float in [-1.0, 1.0]:
		spots.append(Vector3(sign * (half.x + STAND_GAP - 4.0), 0.0, -half.y * _stretch))
		spots.append(Vector3(sign * (half.x + STAND_GAP - 4.0), 0.0, half.y * 0.4 * _stretch))
	for spot: Vector3 in spots:
		var colour: Color = FRIENDLY_COLOR if spot.x < 0.0 else ENEMY_COLOR
		if absf(spot.x) < 1.0:
			colour = CREAM_COLOR
		var pole_height: float = 100.0
		_add_quad(builder, spot + Vector3(-1.2, 0.0, 0.0), spot + Vector3(1.2, 0.0, 0.0), spot + Vector3(1.2, pole_height, 0.0), spot + Vector3(-1.2, pole_height, 0.0), POLE_COLOR)
		var top: Vector3 = spot + Vector3(0.0, pole_height, 0.0)
		var flag_length: float = 26.0
		var flag_height: float = 17.0
		_add_quad(builder, top + Vector3(1.2, 0.0, 0.0), top + Vector3(flag_length, 0.0, 0.0), top + Vector3(flag_length - 7.0, -flag_height * 0.5, 0.0), top + Vector3(1.2, -flag_height * 0.5, 0.0), colour)
		_add_tri(builder, top + Vector3(1.2, -flag_height * 0.5, 0.0), top + Vector3(flag_length - 7.0, -flag_height * 0.5, 0.0), top + Vector3(flag_length, -flag_height, 0.0), colour)
		_add_tri(builder, top + Vector3(1.2, -flag_height * 0.5, 0.0), top + Vector3(flag_length, -flag_height, 0.0), top + Vector3(1.2, -flag_height, 0.0), colour)


# The royal canopy over the middle of the far stand: a blue, cream and red striped cone on four posts.
func _add_canopy(builder: SurfaceTool, half: Vector2) -> void:
	var centre: Vector3 = Vector3(0.0, CANOPY_HEIGHT, -(half.y + STAND_GAP + STAND_TIER_DEPTH * 1.5) * _stretch)
	var apex: Vector3 = centre + Vector3(0.0, CANOPY_RISE, 0.0)
	var stripes: Array[Color] = [FRIENDLY_COLOR, CREAM_COLOR, ENEMY_COLOR, CREAM_COLOR]
	for index: int in CANOPY_SEGMENTS:
		var angle0: float = TAU * float(index) / float(CANOPY_SEGMENTS)
		var angle1: float = TAU * float(index + 1) / float(CANOPY_SEGMENTS)
		var rim0: Vector3 = centre + Vector3(cos(angle0) * CANOPY_RADIUS, 0.0, sin(angle0) * CANOPY_RADIUS * 0.6)
		var rim1: Vector3 = centre + Vector3(cos(angle1) * CANOPY_RADIUS, 0.0, sin(angle1) * CANOPY_RADIUS * 0.6)
		var colour: Color = stripes[index % stripes.size()]
		_add_tri(builder, rim0, rim1, apex, colour)
	for sx: float in [-1.0, 1.0]:
		var post: Vector3 = Vector3(centre.x + sx * CANOPY_RADIUS * 0.8, 0.0, centre.z)
		_add_quad(builder, post + Vector3(-1.5, 0.0, 0.0), post + Vector3(1.5, 0.0, 0.0), post + Vector3(1.5, CANOPY_HEIGHT, 0.0), post + Vector3(-1.5, CANOPY_HEIGHT, 0.0), POLE_COLOR)


# Hay bales lie on their side along the near fences, low enough to stay under the field edge.
func _add_hay(parent: Node3D, half: Vector2) -> void:
	var bales: Array[Transform3D] = []
	var bands: Array[Transform3D] = []
	var at_points: Array[Vector2] = [
		Vector2(-440.0, half.y + 52.0), Vector2(-150.0, half.y + 52.0), Vector2(180.0, half.y + 52.0), Vector2(430.0, half.y + 52.0),
		Vector2(half.x + 52.0, -40.0), Vector2(half.x + 52.0, 230.0), Vector2(-half.x - 52.0, 230.0), Vector2(-half.x - 52.0, -230.0 + 20.0),
	]
	for point: Vector2 in at_points:
		var lying: Basis = Basis(Vector3.UP, point.x * 0.03) * Basis(Vector3(0.0, 0.0, 1.0), PI * 0.5)
		var at: Vector3 = Vector3(point.x, 10.0, point.y * _stretch)
		bales.append(Transform3D(lying, at))
		bands.append(Transform3D(lying.scaled(Vector3(1.06, 0.18, 1.06)), at))
	var bale: CylinderMesh = CylinderMesh.new()
	bale.top_radius = 10.0
	bale.bottom_radius = 10.0
	bale.height = 24.0
	bale.radial_segments = 8
	bale.rings = 1
	_add_multi_mesh(parent, bale, bales, MeshBuilder3D.flat_material(STRAW_COLOR))
	_add_multi_mesh(parent, bale, bands, MeshBuilder3D.flat_material(STRAW_BAND_COLOR))


# Spectators stand along each tier, spaced out, so every tier shows a row of heads above the one in front.
func _add_crowd(parent: Node3D, half: Vector2) -> void:
	var crowd: SpectatorCrowd = SpectatorCrowd.new()
	parent.add_child(crowd)
	crowd.build(crowd_spots(half), _stretch)


## Spectator positions as (x, ground y, tier height, size). Rows sit on the stand tops, never on the field.
func crowd_spots(half: Vector2) -> Array[Vector4]:
	var spots: Array[Vector4] = []
	var seat: int = 0
	for tier: int in BACK_TIERS:
		var height: float = STAND_TIER_HEIGHT * float(tier + 1)
		var row: float = -(half.y + STAND_GAP + STAND_TIER_DEPTH * (float(tier) + 0.5))
		var x: float = -half.x - STAND_OVERHANG + SPECTATOR_SPACING * (0.5 + 0.5 * float(tier % 2))
		while x < half.x + STAND_OVERHANG - SPECTATOR_SPACING * 0.4:
			seat += 1
			if _seat_taken(seat):
				spots.append(Vector4(x, row, height, SPECTATOR_SIZE))
			x += SPECTATOR_SPACING
	var side_from: float = -half.y + 10.0
	var side_to: float = half.y * 0.4
	for sign: float in [-1.0, 1.0]:
		for tier: int in SIDE_TIERS:
			var height: float = STAND_TIER_HEIGHT * float(tier + 1)
			var row: float = sign * (half.x + STAND_GAP + STAND_TIER_DEPTH * (float(tier) + 0.5))
			var y: float = side_from + SPECTATOR_SPACING * (0.5 + 0.5 * float(tier % 2))
			while y < side_to:
				seat += 1
				if _seat_taken(seat):
					spots.append(Vector4(row, y, height, SPECTATOR_SIZE))
				y += SPECTATOR_SPACING
	return spots


# Deterministic hash of the seat counter, so the same seats stay empty on every load.
func _seat_taken(counter: int) -> bool:
	return fposmod(float(counter) * 0.7548776662 + float(counter * counter) * 0.5698402909, 1.0) >= EMPTY_SEAT_SHARE


func _place_floor(model: String, at: Vector3, yaw: float, size: float) -> void:
	_place(model, at, yaw, size, ARENA_DIR if model.begins_with("floor") else FOREST_DIR)


func _place(model: String, at: Vector3, yaw: float, size: float, dir: String = FOREST_DIR) -> void:
	var path: String = dir + model
	if not _transforms.has(path):
		_transforms[path] = [] as Array[Transform3D]
	var basis: Basis = Basis(Vector3.UP, yaw).scaled(Vector3.ONE * size)
	(_transforms[path] as Array[Transform3D]).append(Transform3D(basis, at))


func _place_box(model: String, at: Vector3, extent: Vector3, yaw: float = 0.0) -> void:
	var path: String = ARENA_DIR + model
	if not _transforms.has(path):
		_transforms[path] = [] as Array[Transform3D]
	(_transforms[path] as Array[Transform3D]).append(Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(extent), at))


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
	holder.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	holder.material_override = material
	parent.add_child(holder)


func _textured(path: String, tint: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_texture = MipmappedTexture.of(load(path) as Texture2D)
	material.albedo_color = tint
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
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
