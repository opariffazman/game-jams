class_name Figure3D
extends Node3D
## Gunman built from primitives: capsule body, sphere head, box arm and gun. The origin is at the feet and the gun points along -Z.

## Total height in world units.
const HEIGHT: float = 1.8
## Fall tween length in seconds.
const FALL_S: float = 0.35
## World units a falling body drifts away from the camera, so it stays out of the lens.
const FALL_DRIFT: float = 1.1
## World units a falling body drifts sideways, off the center of the frame.
const FALL_SIDE: float = 0.5
const BODY_COLOR: Color = Color("ff2e88")
const HEAD_COLOR: Color = Color("ff6fae")
const GUN_COLOR: Color = Color("f6f6f8")
const DEAD_COLOR: Color = Color("3a1228")

var _body_mat: StandardMaterial3D
var _head_mat: StandardMaterial3D
var _ring: MeshInstance3D
var _dead: bool = false
var _gun_mesh: MeshInstance3D
var _plate_pivot: Node3D = Node3D.new()
var _plate_yaw: float = 0.0
var _kind: int = RoomState.Kind.PISTOL
var _jam_cross: Node3D


func _init() -> void:
	_body_mat = _unshaded(BODY_COLOR)
	_head_mat = _unshaded(HEAD_COLOR)
	var gun_mat: StandardMaterial3D = _unshaded(GUN_COLOR)
	var body: CapsuleMesh = CapsuleMesh.new()
	body.radius = 0.25
	body.height = 1.4
	body.radial_segments = 12
	body.rings = 4
	_add_mesh(body, _body_mat, Vector3(0, 0.7, 0))
	var head: SphereMesh = SphereMesh.new()
	head.radius = 0.2
	head.height = 0.4
	head.radial_segments = 12
	head.rings = 6
	_add_mesh(head, _head_mat, Vector3(0, 1.6, 0))
	var arm: BoxMesh = BoxMesh.new()
	arm.size = Vector3(0.09, 0.09, 0.55)
	_add_mesh(arm, _body_mat, Vector3(0.2, 1.15, -0.35))
	var gun: BoxMesh = BoxMesh.new()
	gun.size = Vector3(0.1, 0.16, 0.28)
	_gun_mesh = _add_mesh(gun, gun_mat, Vector3(0.2, 1.12, -0.72))
	var ring_mesh: TorusMesh = TorusMesh.new()
	ring_mesh.inner_radius = 0.55
	ring_mesh.outer_radius = 0.7
	ring_mesh.rings = 24
	ring_mesh.ring_segments = 4
	_ring = _add_mesh(ring_mesh, _unshaded(GUN_COLOR), Vector3(0, 0.03, 0))
	_ring.scale = Vector3(1, 0.05, 1)
	_ring.visible = false
	add_child(_plate_pivot)
	var plate: BoxMesh = BoxMesh.new()
	plate.size = Vector3(0.9, 1.1, 0.1)
	var plate_node: MeshInstance3D = _add_mesh(plate, _unshaded(GUN_COLOR), Vector3(0, 0.9, -0.55))
	remove_child(plate_node)
	_plate_pivot.add_child(plate_node)
	_plate_pivot.visible = false


## Sets the gunman type. A shield shows a plate on his facing side, a knife swaps the gun for a blade.
func configure(kind: int, facing: int) -> void:
	_kind = kind
	var front: Vector2 = RoomState.facing_vector(facing)
	_plate_yaw = atan2(-front.x, -front.y)
	_plate_pivot.visible = kind == RoomState.Kind.SHIELD
	_plate_pivot.rotation.y = _plate_yaw - rotation.y
	if kind == RoomState.Kind.KNIFE:
		_gun_mesh.mesh = _blade_mesh()
		_gun_mesh.position = Vector3(0.2, 1.12, -0.7)


## Turns the gunman to face the floor point [param target]. Keeps him upright.
func face(target: Vector3) -> void:
	var flat: Vector3 = Vector3(target.x, global_position.y, target.z)
	if flat.distance_squared_to(global_position) > 0.0001:
		look_at(flat, Vector3.UP)
	_plate_pivot.rotation.y = _plate_yaw - rotation.y


## Shows or hides the floor ring that marks the swapped gunman.
func set_ring(shown: bool) -> void:
	_ring.visible = shown


## Falls over, drifts and dims. [param away] is the floor direction from the camera to the body: he tips along it and drifts
## away and to the side, so the lens stays clear. A zero vector falls backwards in place. Safe to call twice.
func fall(away: Vector3 = Vector3.ZERO) -> void:
	if _dead:
		return
	_dead = true
	set_ring(false)
	set_jam(false)
	var flat: Vector3 = Vector3(away.x, 0.0, away.z)
	var tween: Tween = create_tween().set_parallel(true)
	if flat.length_squared() < 0.0001:
		tween.tween_property(self, "rotation:x", PI * 0.5, FALL_S).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_property(self, "position:y", 0.22, FALL_S).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	else:
		flat = flat.normalized()
		var axis: Vector3 = Vector3.UP.cross(flat)
		var start: Basis = basis
		var side: Vector3 = axis * (FALL_SIDE if axis.x >= 0.0 else -FALL_SIDE)
		tween.tween_method(func(angle: float) -> void: basis = Basis(axis, angle) * start, 0.0, PI * 0.5, FALL_S).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_property(self, "position", position + flat * FALL_DRIFT + side + Vector3(0, 0.22 - position.y, 0), FALL_S).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(_body_mat, "albedo_color", DEAD_COLOR, FALL_S)
	tween.tween_property(_head_mat, "albedo_color", DEAD_COLOR, FALL_S)


## Shows or hides a small amber cross over the gun, the jam cue.
func set_jam(shown: bool) -> void:
	if _jam_cross == null:
		_jam_cross = Node3D.new()
		var material: StandardMaterial3D = _unshaded(Color("ffb020"))
		var bar_mesh: BoxMesh = BoxMesh.new()
		bar_mesh.size = Vector3(0.34, 0.07, 0.07)
		for plane: float in [0.0, PI * 0.5]:
			for angle: float in [PI * 0.25, -PI * 0.25]:
				var bar: MeshInstance3D = MeshInstance3D.new()
				bar.mesh = bar_mesh
				bar.material_override = material
				var pivot: Node3D = Node3D.new()
				pivot.rotation.y = plane
				bar.rotation.z = angle
				pivot.add_child(bar)
				_jam_cross.add_child(pivot)
		_jam_cross.position = Vector3(0.2, 1.5, -0.72)
		add_child(_jam_cross)
	_jam_cross.visible = shown
	if shown:
		_jam_cross.scale = Vector3.ONE * 0.4
		create_tween().set_ignore_time_scale(true).tween_property(_jam_cross, "scale", Vector3.ONE * 1.3, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Returns true once [method fall] has run.
func is_dead() -> bool:
	return _dead


func _add_mesh(mesh: Mesh, material: Material, offset: Vector3) -> MeshInstance3D:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = offset
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	return instance


func _blade_mesh() -> BoxMesh:
	var blade: BoxMesh = BoxMesh.new()
	blade.size = Vector3(0.04, 0.1, 0.4)
	return blade


func _unshaded(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	return material
