class_name MeshBuilder3D
extends RefCounted
## Builds flat ground meshes for the 3D view. Every mesh lies in the XZ plane at y = 0.
##
## Coordinates are 2D arena pixels: x is x, and the second 2D axis is z. The parent node stretches z
## by [constant World3DView.GROUND_STRETCH], so a circle built here shows as a circle on screen.

const RING_SEGMENTS: int = 48


## Returns an unshaded material. [param albedo] may carry alpha.
static func flat_material(albedo: Color, use_vertex_color: bool = false) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = albedo
	material.vertex_color_use_as_albedo = use_vertex_color
	if albedo.a < 1.0 or use_vertex_color:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material


## Returns a per-pixel lit material that receives shadows. [param albedo] must be opaque.
static func lit_material(albedo: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = albedo
	material.roughness = 1.0
	return material


## Returns a flat ring between [param inner] and [param outer] radius.
static func annulus(inner: float, outer: float) -> ArrayMesh:
	var tool: SurfaceTool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_arc(tool, inner, outer, 0.0, TAU, RING_SEGMENTS, Color.WHITE)
	return tool.commit()


## Returns a flat square frame between [param inner] and [param outer] half sizes.
static func square_frame(inner: float, outer: float) -> ArrayMesh:
	var tool: SurfaceTool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var band: float = outer - inner
	_add_rect(tool, Rect2(-outer, -outer, outer * 2.0, band), Color.WHITE)
	_add_rect(tool, Rect2(-outer, inner, outer * 2.0, band), Color.WHITE)
	_add_rect(tool, Rect2(-outer, -inner, band, inner * 2.0), Color.WHITE)
	_add_rect(tool, Rect2(inner, -inner, band, inner * 2.0), Color.WHITE)
	return tool.commit()


## Collects many flat shapes into one mesh, so the arena markings cost one draw call.
class Lines:
	extends RefCounted

	var _tool: SurfaceTool = SurfaceTool.new()

	func _init() -> void:
		_tool.begin(Mesh.PRIMITIVE_TRIANGLES)

	## Adds an axis-aligned filled rectangle.
	func rect(area: Rect2, color: Color) -> void:
		MeshBuilder3D._add_rect(_tool, area, color)

	## Adds the outline of an axis-aligned rectangle centred on the origin.
	func outline(half: Vector2, width: float, color: Color) -> void:
		rect(Rect2(-half.x - width * 0.5, -half.y - width * 0.5, half.x * 2.0 + width, width), color)
		rect(Rect2(-half.x - width * 0.5, half.y - width * 0.5, half.x * 2.0 + width, width), color)
		rect(Rect2(-half.x - width * 0.5, -half.y + width * 0.5, width, half.y * 2.0 - width), color)
		rect(Rect2(half.x - width * 0.5, -half.y + width * 0.5, width, half.y * 2.0 - width), color)

	## Adds a dashed circle.
	func dashed_ring(radius: float, width: float, dash: float, gap: float, color: Color) -> void:
		var angle: float = 0.0
		while angle < TAU:
			MeshBuilder3D._add_arc(_tool, radius - width * 0.5, radius + width * 0.5, angle, minf(angle + dash, TAU), 3, color)
			angle += dash + gap

	func build() -> ArrayMesh:
		return _tool.commit()


static func _add_rect(tool: SurfaceTool, area: Rect2, color: Color) -> void:
	var corners: Array[Vector3] = [
		Vector3(area.position.x, 0.0, area.position.y),
		Vector3(area.end.x, 0.0, area.position.y),
		Vector3(area.end.x, 0.0, area.end.y),
		Vector3(area.position.x, 0.0, area.end.y),
	]
	for index: int in [0, 1, 2, 0, 2, 3]:
		tool.set_color(color)
		tool.set_normal(Vector3.UP)
		tool.add_vertex(corners[index])


static func _add_arc(tool: SurfaceTool, inner: float, outer: float, from: float, to: float, steps: int, color: Color) -> void:
	for step: int in steps:
		var a0: float = lerpf(from, to, float(step) / float(steps))
		var a1: float = lerpf(from, to, float(step + 1) / float(steps))
		var p0: Vector3 = Vector3(cos(a0) * inner, 0.0, sin(a0) * inner)
		var p1: Vector3 = Vector3(cos(a0) * outer, 0.0, sin(a0) * outer)
		var p2: Vector3 = Vector3(cos(a1) * outer, 0.0, sin(a1) * outer)
		var p3: Vector3 = Vector3(cos(a1) * inner, 0.0, sin(a1) * inner)
		for point: Vector3 in [p0, p1, p2, p0, p2, p3]:
			tool.set_color(color)
			tool.set_normal(Vector3.UP)
			tool.add_vertex(point)
