class_name ConfettiPool
extends Node3D
## Reusable candy and confetti bursts that replace a defeated zombie.
##
## Emitters are built once and recycled, so a defeat never allocates on the web build.

## Number of emitters recycled in turn.
const POOL_SIZE: int = 8
## Particles per burst.
const PARTICLES_PER_BURST: int = 28
## Seconds each particle lives.
const LIFETIME: float = 0.9
## Edge length of one confetti piece in metres.
const PIECE_SIZE: float = 0.16
## Candy colours picked at random per particle.
const COLORS: Array[Color] = [
	Color(1.0, 0.35, 0.55), Color(1.0, 0.8, 0.2), Color(0.35, 0.9, 0.6),
	Color(0.4, 0.7, 1.0), Color(0.8, 0.5, 1.0), Color(1.0, 0.55, 0.15),
]

var _emitters: Array[CPUParticles3D] = []
var _next_index: int = 0


func _ready() -> void:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.disable_fog = true
	var piece: QuadMesh = QuadMesh.new()
	piece.size = Vector2(PIECE_SIZE, PIECE_SIZE)
	piece.material = material
	var ramp: Gradient = Gradient.new()
	ramp.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	ramp.offsets = PackedFloat32Array()
	ramp.colors = PackedColorArray()
	for index: int in COLORS.size():
		var offset: float = float(index) / float(COLORS.size())
		if index < ramp.get_point_count():
			ramp.set_offset(index, offset)
			ramp.set_color(index, COLORS[index])
		else:
			ramp.add_point(offset, COLORS[index])
	for _i: int in POOL_SIZE:
		_emitters.append(_build_emitter(piece, ramp))


## Plays one burst at a world position.
func burst(world_position: Vector3) -> void:
	var emitter: CPUParticles3D = _emitters[_next_index]
	_next_index = (_next_index + 1) % POOL_SIZE
	emitter.global_position = world_position
	emitter.restart()
	emitter.emitting = true


func _build_emitter(piece: Mesh, ramp: Gradient) -> CPUParticles3D:
	var emitter: CPUParticles3D = CPUParticles3D.new()
	emitter.mesh = piece
	emitter.amount = PARTICLES_PER_BURST
	emitter.lifetime = LIFETIME
	emitter.one_shot = true
	emitter.explosiveness = 1.0
	emitter.emitting = false
	emitter.direction = Vector3.UP
	emitter.spread = 75.0
	emitter.initial_velocity_min = 3.0
	emitter.initial_velocity_max = 6.0
	emitter.gravity = Vector3(0.0, -9.0, 0.0)
	emitter.scale_amount_min = 0.7
	emitter.scale_amount_max = 1.5
	emitter.color_initial_ramp = ramp
	emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(emitter)
	return emitter
