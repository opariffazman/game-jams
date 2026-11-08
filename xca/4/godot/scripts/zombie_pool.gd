class_name ZombiePool
extends Node3D
## Fixed pool of zombies. The pool size is the cap on active zombies.

## Emitted with the world position where a zombie ended, for the confetti poof.
signal zombie_defeated(world_position: Vector3)
## Emitted when a shot hurts a zombie without defeating it.
signal zombie_hurt
## Emitted for every damage to a zombie, with the lives taken and whether it was defeated. Effects listen here.
signal zombie_damaged(zombie: Zombie, amount: int, killed: bool)
## Emitted when a zombie reaches the player.
signal zombie_reached_player

## Model scenes, one per zombie type, in the order basic, chubby, arm brute, ribcage runner.
const ZOMBIE_SCENES: Array[PackedScene] = [
	preload("res://assets/Zombie_Basic.gltf"),
	preload("res://assets/Zombie_Chubby.gltf"),
	preload("res://assets/Zombie_Arm.gltf"),
	preload("res://assets/Zombie_Ribcage.gltf"),
]
## Type of each pooled zombie. The length is the cap of 12 active zombies.
const POOL_TYPES: Array[int] = [0, 0, 0, 0, 0, 1, 1, 1, 3, 3, 3, 2]
## Blob shadow texture size in pixels.
const BLOB_TEXTURE_SIZE: int = 64
## Blob shadow edge length in metres.
const BLOB_SIZE: float = 1.8
## Distance from the camera beyond which animation LOD halves the update rate.
const LOD_FAR_DISTANCE: float = 16.0

## Camera used for the animation level of detail distance.
@export var camera: Camera3D

## Whether far zombies update animation at half rate.
var animation_lod_enabled: bool = false

var _zombies: Array[Zombie] = []
var _blob_mesh: QuadMesh
var _frame_parity: int = 0


func _ready() -> void:
	_blob_mesh = make_blob_mesh()
	for type: int in POOL_TYPES:
		var zombie: Zombie = Zombie.new()
		add_child(zombie)
		zombie.setup(type, ZOMBIE_SCENES[type], _blob_mesh)
		zombie.defeated.connect(_on_zombie_defeated)
		zombie.hurt.connect(func(_z: Zombie) -> void: zombie_hurt.emit())
		zombie.reached_player.connect(_on_zombie_reached_player)
		zombie.damaged.connect(func(z: Zombie, amount: int, killed: bool) -> void: zombie_damaged.emit(z, amount, killed))
		_zombies.append(zombie)


func _process(_delta: float) -> void:
	if not animation_lod_enabled or camera == null:
		return
	_frame_parity = 1 - _frame_parity
	var camera_position: Vector3 = camera.global_position
	var index: int = 0
	for zombie: Zombie in _zombies:
		index += 1
		if zombie.state == Zombie.State.INACTIVE:
			continue
		var is_far: bool = zombie.global_position.distance_to(camera_position) > LOD_FAR_DISTANCE
		zombie.apply_animation_lod(is_far, is_far and (index + _frame_parity) % 2 == 0)


## Turns animation LOD on or off and restores full speed when off.
func set_animation_lod(enabled: bool) -> void:
	animation_lod_enabled = enabled
	if enabled:
		return
	for zombie: Zombie in _zombies:
		zombie.reset_animation_speed()


## Activates a free zombie, preferring the wanted type. Returns null when the pool is empty.
func spawn(type_id: int, spawn_point: Vector3, hero: Node3D) -> Zombie:
	var fallback: Zombie = null
	for zombie: Zombie in _zombies:
		if zombie.state != Zombie.State.INACTIVE:
			continue
		if zombie.type_id == type_id:
			zombie.activate(spawn_point, hero)
			return zombie
		fallback = fallback if fallback != null else zombie
	if fallback != null:
		fallback.activate(spawn_point, hero)
	return fallback


## Returns every pooled zombie, for the shooter that scans for targets.
func get_zombies() -> Array[Zombie]:
	return _zombies


## Returns how many zombies are walking or shrinking away.
func get_active_count() -> int:
	var count: int = 0
	for zombie: Zombie in _zombies:
		if zombie.state != Zombie.State.INACTIVE:
			count += 1
	return count


## Returns the pool size, which is the cap on active zombies.
func get_capacity() -> int:
	return _zombies.size()


## Returns the targetable zombies whose centre lies within a horizontal radius of a world point.
## A front direction other than zero also keeps only zombies on that side of the point.
func find_in_radius(point: Vector3, radius: float, front: Vector3 = Vector3.ZERO) -> Array[Zombie]:
	var found: Array[Zombie] = []
	for zombie: Zombie in _zombies:
		if not zombie.is_targetable():
			continue
		var offset: Vector3 = zombie.global_position - point
		offset.y = 0.0
		if offset.length() > radius:
			continue
		if front != Vector3.ZERO and offset.dot(front) < 0.0:
			continue
		found.append(zombie)
	return found


## Hides every zombie without effects.
func clear_all() -> void:
	for zombie: Zombie in _zombies:
		zombie.clear()


func _on_zombie_defeated(zombie: Zombie) -> void:
	zombie_defeated.emit(zombie.get_center())


func _on_zombie_reached_player(_zombie: Zombie) -> void:
	zombie_reached_player.emit()


## Builds the soft round blob shadow quad that stands in for real shadows on the web build.
static func make_blob_mesh() -> QuadMesh:
	var image: Image = Image.create(BLOB_TEXTURE_SIZE, BLOB_TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	var half: float = BLOB_TEXTURE_SIZE * 0.5
	for y: int in BLOB_TEXTURE_SIZE:
		for x: int in BLOB_TEXTURE_SIZE:
			var distance: float = Vector2(x + 0.5 - half, y + 0.5 - half).length() / half
			image.set_pixel(x, y, Color(0.0, 0.0, 0.0, clampf(1.0 - distance, 0.0, 1.0) * 0.6))
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_texture = ImageTexture.create_from_image(image)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var mesh: QuadMesh = QuadMesh.new()
	mesh.size = Vector2(BLOB_SIZE, BLOB_SIZE)
	mesh.material = material
	return mesh
