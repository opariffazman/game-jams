class_name LevelBaker
extends RefCounted
## Merges owned models and primitive shapes into one ArrayMesh with three surfaces.
##
## The kit paints with a flat colour atlas, so each vertex samples its swatch once and keeps the colour.
## That drops the texture, and a whole street chunk costs three draw calls on the web build.

## Surface groups. Each group has its own material, so each costs one draw call per chunk.
const COLOR: int = 0
const GLOW: int = 1
const POOL: int = 2
const GROUP_COUNT: int = 3

const MODEL_DIR: String = "res://assets/level/"
## Glow materials have no texture, so their colour comes from this table.
const GLOW_COLORS: Dictionary = {
	"Light": Color(1.0, 0.86, 0.5),
	"Headlights": Color(1.0, 0.95, 0.7),
	"BrakeLight": Color(0.8, 0.25, 0.2),
	"Fire": Color(1.0, 0.55, 0.12),
}
## Survival Pack colours are written in linear space, and the vertex colour path reads them as sRGB.
const OBJ_BRIGHTEN: bool = true

static var _atlas: Image
static var _model_cache: Dictionary = {}
static var _material_cache: Dictionary = {}

var _vertices: Array[PackedVector3Array] = []
var _normals: Array[PackedVector3Array] = []
var _colors: Array[PackedColorArray] = []
var _indices: Array[PackedInt32Array] = []


func _init() -> void:
	for group: int in GROUP_COUNT:
		_vertices.append(PackedVector3Array())
		_normals.append(PackedVector3Array())
		_colors.append(PackedColorArray())
		_indices.append(PackedInt32Array())


## Triangles merged so far, for the budget report.
func triangle_count() -> int:
	var total: int = 0
	for group: int in GROUP_COUNT:
		total += _indices[group].size() / 3
	return total


## Triangle count of a model, so a recipe can skip heavy ones on the low tier.
static func model_triangles(model: String) -> int:
	var total: int = 0
	for part: Dictionary in model_parts(model):
		var part_indices: PackedInt32Array = part["indices"]
		total += part_indices.size() / 3
	return total


## Adds a model by file name without extension. A glow override with alpha above zero replaces the model's glow colour.
func add_model(model: String, xf: Transform3D, tint: Color = Color.WHITE, glow_override: Color = Color(0.0, 0.0, 0.0, 0.0)) -> void:
	var rotation: Basis = xf.basis.orthonormalized()
	for part: Dictionary in model_parts(model):
		var group: int = part["group"]
		var source: PackedVector3Array = part["vertices"]
		var source_normals: PackedVector3Array = part["normals"]
		var source_colors: PackedColorArray = part["colors"]
		var source_indices: PackedInt32Array = part["indices"]
		var base: int = _vertices[group].size()
		_vertices[group].append_array(xf * source)
		for index: int in source.size():
			_normals[group].append(rotation * source_normals[index])
			var colour: Color = source_colors[index]
			if group == GLOW and glow_override.a > 0.0:
				colour = glow_override
			elif group == COLOR:
				colour = Color(colour.r * tint.r, colour.g * tint.g, colour.b * tint.b, 1.0)
			_colors[group].append(colour)
		for index: int in source_indices:
			_indices[group].append(base + index)


## One-sided upright rectangle that faces +z before the transform. It is the cheapest window, eye or sign.
func add_panel(group: int, xf: Transform3D, size: Vector2, colour: Color) -> void:
	var hx: float = size.x * 0.5
	var hy: float = size.y * 0.5
	_quad(group, xf, Vector3(-hx, -hy, 0.0), Vector3(-hx, hy, 0.0), Vector3(hx, hy, 0.0), Vector3(hx, -hy, 0.0), Vector3.BACK, colour)


## Upright rectangle that is lit to the glow colour at the top edge and fades at the bottom, for awnings and bunting.
func add_panel_gradient(group: int, xf: Transform3D, size: Vector2, top: Color, bottom: Color) -> void:
	var hx: float = size.x * 0.5
	var hy: float = size.y * 0.5
	var a := Vector3(-hx, -hy, 0.0)
	var b := Vector3(-hx, hy, 0.0)
	var c := Vector3(hx, hy, 0.0)
	var d := Vector3(hx, -hy, 0.0)
	_triangle(group, xf, a, b, c, Vector3.BACK, bottom, top, top)
	_triangle(group, xf, a, c, d, Vector3.BACK, bottom, top, bottom)


## Box centred on the transform origin. The bottom face is skipped unless asked for, because nobody sees it.
func add_box(group: int, xf: Transform3D, size: Vector3, colour: Color, with_bottom: bool = false) -> void:
	var half: Vector3 = size * 0.5
	var faces: Array = [
		[Vector3.RIGHT, Vector3.UP, Vector3.BACK],
		[Vector3.LEFT, Vector3.BACK, Vector3.UP],
		[Vector3.UP, Vector3.BACK, Vector3.RIGHT],
		[Vector3.BACK, Vector3.RIGHT, Vector3.UP],
		[Vector3.FORWARD, Vector3.UP, Vector3.RIGHT],
	]
	if with_bottom:
		faces.append([Vector3.DOWN, Vector3.RIGHT, Vector3.BACK])
	for face: Array in faces:
		var normal: Vector3 = face[0]
		var u: Vector3 = face[1]
		var v: Vector3 = face[2]
		var centre: Vector3 = normal * absf(normal.dot(half))
		var hu: Vector3 = u * absf(u.dot(half))
		var hv: Vector3 = v * absf(v.dot(half))
		_quad(group, xf, centre - hu - hv, centre - hu + hv, centre + hu + hv, centre + hu - hv, normal, colour)


## Gable roof. The span runs along x, the ridge along z, and the base sits at y = 0.
func add_gable(group: int, xf: Transform3D, span: float, height: float, length: float, colour: Color, eave: float = 0.0) -> void:
	var hs: float = span * 0.5 + eave
	var hl: float = length * 0.5
	var front_left := Vector3(-hs, 0.0, hl)
	var front_right := Vector3(hs, 0.0, hl)
	var front_top := Vector3(0.0, height, hl)
	var back_left := Vector3(-hs, 0.0, -hl)
	var back_right := Vector3(hs, 0.0, -hl)
	var back_top := Vector3(0.0, height, -hl)
	_triangle(group, xf, front_left, front_top, front_right, Vector3.BACK, colour, colour, colour)
	_triangle(group, xf, back_left, back_top, back_right, Vector3.FORWARD, colour, colour, colour)
	_quad(group, xf, back_left, back_top, front_top, front_left, Vector3(-height, hs, 0.0), colour)
	_quad(group, xf, back_right, back_top, front_top, front_right, Vector3(height, hs, 0.0), colour)


## Tapered column with a flat top. A top radius of zero makes a cone.
func add_column(group: int, xf: Transform3D, bottom_radius: float, top_radius: float, height: float, colour: Color, sides: int = 6) -> void:
	for side: int in sides:
		var angle_a: float = TAU * float(side) / float(sides)
		var angle_b: float = TAU * float(side + 1) / float(sides)
		var bottom_a := Vector3(cos(angle_a) * bottom_radius, 0.0, sin(angle_a) * bottom_radius)
		var bottom_b := Vector3(cos(angle_b) * bottom_radius, 0.0, sin(angle_b) * bottom_radius)
		var top_a := Vector3(cos(angle_a) * top_radius, height, sin(angle_a) * top_radius)
		var top_b := Vector3(cos(angle_b) * top_radius, height, sin(angle_b) * top_radius)
		var outward: Vector3 = (bottom_a + bottom_b) * 0.5
		if top_radius <= 0.0:
			_triangle(group, xf, bottom_a, top_a, bottom_b, outward, colour, colour, colour)
		else:
			_quad(group, xf, bottom_a, top_a, top_b, bottom_b, outward, colour)
			_triangle(group, xf, top_a, Vector3(0.0, height, 0.0), top_b, Vector3.UP, colour, colour, colour)


## Low-poly sphere. The transform can squash or stretch it.
func add_sphere(group: int, xf: Transform3D, radius: float, colour: Color, rings: int = 4, sides: int = 8) -> void:
	for ring: int in rings:
		var lat_a: float = PI * float(ring) / float(rings) - PI * 0.5
		var lat_b: float = PI * float(ring + 1) / float(rings) - PI * 0.5
		for side: int in sides:
			var lon_a: float = TAU * float(side) / float(sides)
			var lon_b: float = TAU * float(side + 1) / float(sides)
			var p00: Vector3 = _sphere_point(radius, lat_a, lon_a)
			var p01: Vector3 = _sphere_point(radius, lat_a, lon_b)
			var p10: Vector3 = _sphere_point(radius, lat_b, lon_a)
			var p11: Vector3 = _sphere_point(radius, lat_b, lon_b)
			var outward: Vector3 = p00 + p01 + p10 + p11
			if ring > 0:
				_triangle(group, xf, p00, p10, p01, outward, colour, colour, colour)
			if ring < rings - 1:
				_triangle(group, xf, p01, p10, p11, outward, colour, colour, colour)


## Flat disc that fades to nothing at the rim, for lamp pools. It faces up before the transform.
func add_disc(group: int, xf: Transform3D, radius: float, colour: Color, sides: int = 14) -> void:
	var rim := Color(colour.r, colour.g, colour.b, 0.0)
	for side: int in sides:
		var angle_a: float = TAU * float(side) / float(sides)
		var angle_b: float = TAU * float(side + 1) / float(sides)
		var a := Vector3(cos(angle_a) * radius, 0.0, sin(angle_a) * radius)
		var b := Vector3(cos(angle_b) * radius, 0.0, sin(angle_b) * radius)
		_triangle(group, xf, Vector3.ZERO, b, a, Vector3.UP, colour, rim, rim)


## Finishes the mesh. Empty groups are skipped, so a chunk without glow costs one draw call fewer.
func bake() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var surface: int = 0
	for group: int in GROUP_COUNT:
		if _indices[group].is_empty():
			continue
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = _vertices[group]
		arrays[Mesh.ARRAY_NORMAL] = _normals[group]
		arrays[Mesh.ARRAY_COLOR] = _colors[group]
		arrays[Mesh.ARRAY_INDEX] = _indices[group]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(surface, material_for(group))
		surface += 1
	return mesh


static func material_for(group: int) -> StandardMaterial3D:
	if _material_cache.has(group):
		return _material_cache[group]
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 1.0
	material.metallic_specular = 0.0
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX if group == COLOR else BaseMaterial3D.SHADING_MODE_UNSHADED
	if group == POOL:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material_cache[group] = material
	return material


## Reads each model once and keeps the arrays, so baking a chunk never touches the model files again.
static func model_parts(model: String) -> Array:
	if _model_cache.has(model):
		return _model_cache[model]
	var parts: Array = []
	var is_obj: bool = false
	var path: String = MODEL_DIR + model + ".gltf"
	if not ResourceLoader.exists(path):
		path = MODEL_DIR + model + ".obj"
		is_obj = true
	var resource: Resource = load(path)
	if resource is PackedScene:
		var root: Node = (resource as PackedScene).instantiate()
		for node: Node in root.find_children("*", "MeshInstance3D", true, false):
			var instance: MeshInstance3D = node as MeshInstance3D
			var to_root: Transform3D = Transform3D.IDENTITY
			var walker: Node = instance
			while walker != root and walker is Node3D:
				to_root = (walker as Node3D).transform * to_root
				walker = walker.get_parent()
			_collect_parts(instance.mesh, to_root, parts, is_obj)
		root.free()
	elif resource is Mesh:
		_collect_parts(resource as Mesh, Transform3D.IDENTITY, parts, is_obj)
	else:
		push_error("LevelBaker: missing model " + path)
	_model_cache[model] = parts
	return parts


static func _collect_parts(mesh: Mesh, xf: Transform3D, parts: Array, is_obj: bool) -> void:
	for surface: int in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var uvs: PackedVector2Array = PackedVector2Array()
		if arrays[Mesh.ARRAY_TEX_UV] != null:
			uvs = arrays[Mesh.ARRAY_TEX_UV]
		var material: BaseMaterial3D = mesh.surface_get_material(surface) as BaseMaterial3D
		var group: int = COLOR
		var flat: Color = Color(0.5, 0.5, 0.5)
		var atlas: Image = null
		if material != null:
			flat = material.albedo_color
			if is_obj and OBJ_BRIGHTEN:
				flat = flat.linear_to_srgb()
			if material.albedo_texture != null:
				atlas = _atlas_image(material.albedo_texture)
			elif GLOW_COLORS.has(material.resource_name):
				group = GLOW
				flat = GLOW_COLORS[material.resource_name]
			elif material.emission_enabled:
				group = GLOW
				flat = material.emission
		var colors := PackedColorArray()
		for index: int in vertices.size():
			if atlas != null and index < uvs.size():
				var pixel := Vector2i(
						clampi(int(uvs[index].x * atlas.get_width()), 0, atlas.get_width() - 1),
						clampi(int(uvs[index].y * atlas.get_height()), 0, atlas.get_height() - 1))
				var sample: Color = atlas.get_pixelv(pixel)
				colors.append(Color(sample.r, sample.g, sample.b, 1.0))
			else:
				colors.append(flat)
		var indices: PackedInt32Array = PackedInt32Array()
		if arrays[Mesh.ARRAY_INDEX] != null:
			indices = arrays[Mesh.ARRAY_INDEX]
		else:
			for index: int in vertices.size():
				indices.append(index)
		var rotation: Basis = xf.basis.orthonormalized()
		var moved_normals := PackedVector3Array()
		for normal: Vector3 in normals:
			moved_normals.append(rotation * normal)
		parts.append({
			"group": group,
			"vertices": xf * vertices,
			"normals": moved_normals,
			"colors": colors,
			"indices": indices,
		})


static func _atlas_image(texture: Texture2D) -> Image:
	if _atlas == null:
		_atlas = texture.get_image()
		if _atlas.is_compressed():
			_atlas.decompress()
	return _atlas


static func _sphere_point(radius: float, latitude: float, longitude: float) -> Vector3:
	return Vector3(cos(latitude) * cos(longitude), sin(latitude), cos(latitude) * sin(longitude)) * radius


func _quad(group: int, xf: Transform3D, a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3, colour: Color) -> void:
	_triangle(group, xf, a, b, c, outward, colour, colour, colour)
	_triangle(group, xf, a, c, d, outward, colour, colour, colour)


## Godot treats clockwise triangles as front faces, so the order flips when the first guess faces inward.
func _triangle(group: int, xf: Transform3D, a: Vector3, b: Vector3, c: Vector3, outward: Vector3, colour_a: Color, colour_b: Color, colour_c: Color) -> void:
	var normal: Vector3 = (c - a).cross(b - a)
	if normal.dot(outward) < 0.0:
		var swap_point: Vector3 = b
		b = c
		c = swap_point
		var swap_colour: Color = colour_b
		colour_b = colour_c
		colour_c = swap_colour
		normal = -normal
	var world_normal: Vector3 = (xf.basis.orthonormalized() * normal).normalized()
	var base: int = _vertices[group].size()
	_vertices[group].append(xf * a)
	_vertices[group].append(xf * b)
	_vertices[group].append(xf * c)
	_normals[group].append(world_normal)
	_normals[group].append(world_normal)
	_normals[group].append(world_normal)
	_colors[group].append(colour_a)
	_colors[group].append(colour_b)
	_colors[group].append(colour_c)
	_indices[group].append(base)
	_indices[group].append(base + 1)
	_indices[group].append(base + 2)
