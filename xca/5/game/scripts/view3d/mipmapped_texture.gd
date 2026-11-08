class_name MipmappedTexture
extends RefCounted
## Kenney colormaps import without mipmaps, so minified models shimmer. This builds a mipmapped copy at run time.
## The .import sidecars stay untouched because the editor regenerates them.

static var _cache: Dictionary = {}


## Returns a mipmapped copy of [param source], or the source when it has no readable image.
static func of(source: Texture2D) -> Texture2D:
	if source == null:
		return null
	if _cache.has(source):
		return _cache[source] as Texture2D
	var image: Image = source.get_image()
	if image == null or image.is_empty():
		return source
	image = image.duplicate() as Image
	if image.is_compressed():
		return source
	image.generate_mipmaps()
	var copy: ImageTexture = ImageTexture.create_from_image(image)
	_cache[source] = copy
	return copy


## Swaps the albedo texture of every standard material under [param root] for its mipmapped copy.
static func apply_to_model(root: Node) -> void:
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var instance: MeshInstance3D = node as MeshInstance3D
		if instance.mesh == null:
			continue
		for surface: int in instance.mesh.get_surface_count():
			var material: StandardMaterial3D = instance.mesh.surface_get_material(surface) as StandardMaterial3D
			if material == null or material.albedo_texture == null:
				continue
			var swapped: StandardMaterial3D = material.duplicate() as StandardMaterial3D
			swapped.albedo_texture = of(material.albedo_texture)
			swapped.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			instance.set_surface_override_material(surface, swapped)
