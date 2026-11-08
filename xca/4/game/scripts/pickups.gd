class_name Pickups
extends Node3D
## Ammo crates and health packs that scroll toward the hero in the lanes.
##
## They spawn deep in the fog like zombies and never block, because the hero collects one by standing in its lane and otherwise it drifts past.
## The field only spawns what the hero can use, so a full heart bar never gets a health pack.

## Emitted when the hero picks one up.
signal collected(kind: Kind, weapon_id: StringName)

enum Kind { AMMO, HEALTH, WEAPON }

## Metres of running between two spawns.
const SPAWN_GAP: float = 38.0
## Metres ahead of the hero where a pickup appears. Matches the zombie spawn depth, so the fog hides it.
const SPAWN_AHEAD: float = 60.0
## Metres of running between two weapon drops. A drop always spawns, because a new weapon is a choice and never a need.
const WEAPON_GAP: float = 150.0
## World size of a weapon icon in metres.
const WEAPON_ICON_SIZE: float = 1.3
## Length in metres of a weapon model, longest side.
const WEAPON_MODEL_LENGTH: float = 1.5
const WEAPON_SOURCE_SCENE: String = "res://assets/Characters_Shaun.gltf"
## A pickup is collected when it is this close in z, and within COLLECT_HALF_WIDTH of the hero in x.
const COLLECT_REACH: float = 0.9
const COLLECT_HALF_WIDTH: float = 1.1
## Metres behind the hero where a missed pickup is removed.
const PASSED_Z: float = 4.0
## Ammo below this share of the limited weapons makes a crate worth spawning.
const AMMO_NEED: float = 0.75
const SPIN_SPEED: float = 2.0
const BOB_HEIGHT: float = 0.12
const POP_SECONDS: float = 0.22
const AMMO_MODEL: String = "Chest_Special"
const AMMO_SCALE: float = 1.1
const AMMO_TINT: Color = Color(1.5, 1.25, 0.5)
const HEALTH_MODEL: String = "Backpack"
const HEALTH_SCALE: float = 0.24
## Metres from the backpack model origin down to its base at scale 1.
const HEALTH_BASE: float = 1.465
const HEALTH_TINT: Color = Color(1.6, 0.45, 0.5)
## Height in metres of the model, so it sits centred on the item origin.
const ITEM_HEIGHT: float = 0.7
const HALO_RADIUS: float = 0.8

@export var director: RailsDirector
@export var shooter: Shooter

## Totals since start, for the readout and the browser test.
var collected_ammo: int = 0
var collected_health: int = 0
var collected_weapons: int = 0
var _next_spawn_at: float = SPAWN_GAP * 0.5
var _next_weapon_at: float = WEAPON_GAP * 0.5
var _last_distance: float = 0.0
var _clock: float = 0.0
var _items: Array[Node3D] = []
var _ammo_material: StandardMaterial3D = _glow(Color(1.0, 0.8, 0.15))
var _health_material: StandardMaterial3D = _glow(Color(1.0, 0.2, 0.3))
var _kit_meshes: Dictionary[String, ArrayMesh] = {}
var _weapon_scene: Node3D


func _process(delta: float) -> void:
	if director == null:
		return
	if director.phase != RailsDirector.Phase.RUNNING or director.distance < _last_distance:
		clear()
	_last_distance = director.distance
	if director.phase != RailsDirector.Phase.RUNNING:
		return
	_clock += delta
	if director.distance >= _next_spawn_at:
		_next_spawn_at = director.distance + SPAWN_GAP
		_spawn_useful()
	if director.distance >= _next_weapon_at:
		_next_weapon_at = director.distance + WEAPON_GAP
		_spawn_weapon()
	_move(delta)


## Removes every pickup and restarts the spawn spacing.
func clear() -> void:
	for item: Node3D in _items:
		item.queue_free()
	_items.clear()
	_next_spawn_at = director.distance + SPAWN_GAP * 0.5 if director != null else SPAWN_GAP * 0.5
	_next_weapon_at = director.distance + WEAPON_GAP * 0.5 if director != null else WEAPON_GAP * 0.5


## Places a pickup of a kind in a lane.
func spawn(kind: Kind, lane_index: int, weapon_id: StringName = &"") -> void:
	var item := Node3D.new()
	item.set_meta(&"kind", kind)
	item.set_meta(&"weapon_id", weapon_id)
	item.set_meta(&"spin", randf() * TAU)
	if kind == Kind.WEAPON:
		item.add_child(_weapon_sprite(HeroTable.weapon_by_id(weapon_id)))
	elif kind == Kind.AMMO:
		item.add_child(_kit_item(AMMO_MODEL, AMMO_SCALE, 0.0, AMMO_TINT, _ammo_material))
	else:
		item.add_child(_kit_item(HEALTH_MODEL, HEALTH_SCALE, HEALTH_BASE, HEALTH_TINT, _health_material))
	add_child(item)
	item.global_position = Vector3(director.lane_x(lane_index), 0.7, -SPAWN_AHEAD)
	_items.append(item)


## A weapon the hero does not carry yet. Nothing spawns when it carries every droppable weapon.
func _spawn_weapon() -> void:
	var options: Array[StringName] = []
	for weapon: Dictionary in HeroTable.WEAPONS:
		if bool(weapon["drop"]) and (shooter == null or not shooter.carried.has(weapon["id"])):
			options.append(weapon["id"])
	if options.is_empty():
		return
	spawn(Kind.WEAPON, randi_range(0, director.lane_count - 1), options[randi() % options.size()])


func _spawn_useful() -> void:
	var wants_health: bool = director.hearts < director.max_hearts
	var wants_ammo: bool = shooter != null and shooter.ammo_share() < AMMO_NEED
	if not wants_health and not wants_ammo:
		return
	var kind: Kind = Kind.HEALTH if wants_health and (not wants_ammo or randf() < 0.5) else Kind.AMMO
	spawn(kind, randi_range(0, director.lane_count - 1))


func _move(delta: float) -> void:
	var hero_x: float = director.get_hero_x()
	for item: Node3D in _items.duplicate():
		if item.has_meta(&"popping"):
			continue
		item.global_position.z += RailsDirector.RUN_SPEED * delta
		item.global_position.y = 0.7 + sin(_clock * 4.0 + float(item.get_meta(&"spin"))) * BOB_HEIGHT
		# A flat icon spun edge-on would vanish, so it only sways.
		var sway: float = sin(_clock * 2.0 + float(item.get_meta(&"spin"))) * 0.35
		item.rotation.y = sway if item.get_meta(&"kind") == Kind.WEAPON else float(item.get_meta(&"spin")) + _clock * SPIN_SPEED
		var z: float = item.global_position.z
		if z > PASSED_Z:
			_items.erase(item)
			item.queue_free()
		elif z > -COLLECT_REACH and absf(item.global_position.x - hero_x) < COLLECT_HALF_WIDTH:
			_collect(item)


func _collect(item: Node3D) -> void:
	item.set_meta(&"popping", true)
	_items.erase(item)
	var kind: Kind = item.get_meta(&"kind") as Kind
	if kind == Kind.AMMO:
		collected_ammo += 1
	elif kind == Kind.WEAPON:
		collected_weapons += 1
	else:
		collected_health += 1
	collected.emit(kind, item.get_meta(&"weapon_id") as StringName)
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(item, "scale", Vector3.ONE * 2.2, POP_SECONDS)
	tween.tween_property(item, "position:y", item.position.y + 1.2, POP_SECONDS)
	tween.chain().tween_callback(item.queue_free)


## The weapon's own kit model spins above a glowing disc, so the pickup shows exactly what the hero will hold.
func _weapon_sprite(weapon: Dictionary) -> Node3D:
	var holder := Node3D.new()
	var disc := MeshInstance3D.new()
	var disc_mesh := CylinderMesh.new()
	disc_mesh.top_radius = WEAPON_ICON_SIZE * 0.6
	disc_mesh.bottom_radius = WEAPON_ICON_SIZE * 0.6
	disc_mesh.height = 0.08
	disc.mesh = disc_mesh
	disc.material_override = _glow(Color(weapon["accent"]))
	disc.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	disc.position = Vector3(0.0, 0.0, -0.45)
	holder.add_child(disc)
	var source: MeshInstance3D = _weapon_source(StringName(weapon["node"]))
	if source != null:
		holder.add_child(_weapon_model(source))
	return holder


## Finds a weapon mesh on a character model. Every character carries the same set, so one scene serves all pickups.
func _weapon_source(node_name: StringName) -> MeshInstance3D:
	if _weapon_scene == null:
		_weapon_scene = (load(WEAPON_SOURCE_SCENE) as PackedScene).instantiate()
	return _weapon_scene.find_child(String(node_name), true, false) as MeshInstance3D


## Scales the mesh so its longest side is WEAPON_ICON_SIZE and lays that side flat, so the spin shows the whole silhouette.
func _weapon_model(source: MeshInstance3D) -> Node3D:
	var box: AABB = source.mesh.get_aabb()
	var longest_axis: int = box.get_longest_axis_index()
	var lay_flat := Basis.IDENTITY
	if longest_axis == Vector3.AXIS_Y:
		lay_flat = Basis(Vector3.BACK, deg_to_rad(90.0))
	elif longest_axis == Vector3.AXIS_Z:
		lay_flat = Basis(Vector3.UP, deg_to_rad(90.0))
	var fit: float = WEAPON_MODEL_LENGTH / maxf(box.get_longest_axis_size(), 0.001)
	var body := MeshInstance3D.new()
	body.mesh = source.mesh
	var lit: StandardMaterial3D = (source.get_active_material(0) as StandardMaterial3D).duplicate()
	lit.albedo_color = Color(1.8, 1.8, 1.8)
	lit.emission_enabled = true
	lit.emission = Color(0.35, 0.35, 0.4)
	body.material_override = lit
	body.transform = Transform3D(lay_flat * Basis.from_scale(Vector3.ONE * fit), lay_flat * (-(box.position + box.size * 0.5) * fit))
	return body


## A kit model on a glowing pad. The pad is flat because the item spins, and keeps the item readable at fog distance, and the model keeps it on theme.
func _kit_item(model: String, scale: float, base: float, tint: Color, halo_material: StandardMaterial3D) -> Node3D:
	var holder := Node3D.new()
	var body := MeshInstance3D.new()
	body.mesh = _kit_mesh(model, scale, base, tint)
	body.position = Vector3(0.0, -ITEM_HEIGHT * 0.5, 0.0)
	holder.add_child(body)
	var halo := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = HALO_RADIUS
	disc.bottom_radius = HALO_RADIUS
	disc.height = 0.05
	halo.mesh = disc
	halo.material_override = halo_material
	halo.position = Vector3(0.0, -ITEM_HEIGHT * 0.5 - 0.02, 0.0)
	holder.add_child(halo)
	return holder


## Bakes a kit model once. Every pickup of a kind shares the mesh.
## The base is the model's distance below its origin at scale 1, so the model stands on the pad.
func _kit_mesh(model: String, scale: float, base: float, tint: Color) -> ArrayMesh:
	if _kit_meshes.has(model):
		return _kit_meshes[model]
	var baker := LevelBaker.new()
	baker.add_model(model, Transform3D(Basis.from_scale(Vector3.ONE * scale), Vector3(0.0, base * scale, 0.0)), tint)
	var mesh: ArrayMesh = baker.bake()
	_kit_meshes[model] = mesh
	return mesh


## Emissive, so the pickup stays readable at fog distance.
func _glow(colour: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.emission_enabled = true
	material.emission = colour
	material.emission_energy_multiplier = 1.4
	return material
