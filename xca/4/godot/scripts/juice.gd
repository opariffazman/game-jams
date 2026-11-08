class_name Juice
extends Node3D
## Hit feedback: sparks, green goo, damage numbers, hit stop, chain kills and the combo count.
##
## Everything is pooled and built once, so a hit never allocates on the web build. The zombie owns its white flash and knockback.
## Goo and sparks are green and yellow, never red, so the game stays kid friendly.

## Emitted when the chain of quick kills changes. Zero means the chain broke.
signal combo_changed(count: int)
## Emitted on each kill with the pitch boost the audio uses. The boost rises with the chain.
signal kill_chained(pitch_scale: float)

## Seconds between kills that still count as one chain.
const CHAIN_WINDOW: float = 1.6
## Pitch rise per kill in the chain, and the highest pitch scale. A semitone is about 0.06.
const PITCH_STEP: float = 0.06
const PITCH_MAX: float = 1.6
## Seconds the world freezes on a kill. Short enough to read as impact, not as lag.
const HIT_STOP_SECONDS: float = 0.05
## Time scale during the hit stop. Not zero, so animation and physics never divide by zero.
const HIT_STOP_SCALE: float = 0.02
const EMITTER_POOL_SIZE: int = 6
const GOO_PER_KILL: int = 18
const SPARKS_PER_HIT: int = 7
const NUMBER_POOL_SIZE: int = 8
const NUMBER_RISE_SPEED: float = 1.6
const NUMBER_SECONDS: float = 0.7
const NUMBER_FONT_SIZE: int = 72
## Height above the zombie origin where effects appear, in metres.
const EFFECT_HEIGHT: float = 1.1
const GOO_COLOR: Color = Color(0.45, 0.95, 0.3)
const SPARK_COLOR: Color = Color(1.0, 0.9, 0.35)

## Pool that reports damage. Main assigns it after this node is ready, so the connection happens in the setter.
@export var pool: ZombiePool:
	set(value):
		pool = value
		if value != null and not value.zombie_damaged.is_connected(_on_zombie_damaged):
			value.zombie_damaged.connect(_on_zombie_damaged)
## Director that shakes the camera.
@export var director: RailsDirector

## Chain length now.
var combo: int = 0
## Highest chain of the run.
var best_combo: int = 0

var _goo: Array[CPUParticles3D] = []
var _sparks: Array[CPUParticles3D] = []
var _numbers: Array[Label3D] = []
var _number_age: Array[float] = []
var _goo_index: int = 0
var _spark_index: int = 0
var _number_index: int = 0
var _chain_left: float = 0.0
var _stopping: bool = false


func _ready() -> void:
	for index: int in EMITTER_POOL_SIZE:
		_goo.append(_make_emitter(GOO_COLOR, GOO_PER_KILL, 0.1, 3.2, 0.7))
		_sparks.append(_make_emitter(SPARK_COLOR, SPARKS_PER_HIT, 0.05, 4.5, 0.3))
	for index: int in NUMBER_POOL_SIZE:
		var label := Label3D.new()
		label.font_size = NUMBER_FONT_SIZE
		label.pixel_size = 0.008
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.modulate = Color(1.0, 1.0, 0.6)
		label.outline_modulate = Color.BLACK
		label.outline_size = 14
		label.visible = false
		add_child(label)
		_numbers.append(label)
		_number_age.append(NUMBER_SECONDS)


func _process(delta: float) -> void:
	for index: int in _numbers.size():
		if _number_age[index] >= NUMBER_SECONDS:
			continue
		_number_age[index] += delta
		var label: Label3D = _numbers[index]
		label.position.y += NUMBER_RISE_SPEED * delta
		label.modulate.a = 1.0 - clampf(_number_age[index] / NUMBER_SECONDS, 0.0, 1.0)
		if _number_age[index] >= NUMBER_SECONDS:
			label.visible = false
	if combo > 0:
		_chain_left -= delta
		if _chain_left <= 0.0:
			combo = 0
			combo_changed.emit(0)


## Clears the chain, for a new run.
func reset() -> void:
	combo = 0
	best_combo = 0
	combo_changed.emit(0)


func _on_zombie_damaged(zombie: Zombie, amount: int, killed: bool) -> void:
	var point: Vector3 = zombie.global_position + Vector3.UP * EFFECT_HEIGHT
	_burst(_sparks, _spark_index, point)
	_spark_index = (_spark_index + 1) % _sparks.size()
	_show_number(point, amount)
	if not killed:
		return
	_burst(_goo, _goo_index, point)
	_goo_index = (_goo_index + 1) % _goo.size()
	combo += 1
	best_combo = maxi(best_combo, combo)
	_chain_left = CHAIN_WINDOW
	combo_changed.emit(combo)
	kill_chained.emit(minf(1.0 + PITCH_STEP * float(combo - 1), PITCH_MAX))
	if director != null:
		director.add_shake(0.35)
	_hit_stop()


func _burst(emitters: Array[CPUParticles3D], index: int, point: Vector3) -> void:
	var emitter: CPUParticles3D = emitters[index]
	emitter.global_position = point
	emitter.restart()
	emitter.emitting = true


func _show_number(point: Vector3, amount: int) -> void:
	var label: Label3D = _numbers[_number_index]
	label.text = str(amount)
	label.position = point + Vector3(randf_range(-0.3, 0.3), 0.3, 0.0)
	label.modulate.a = 1.0
	label.visible = true
	_number_age[_number_index] = 0.0
	_number_index = (_number_index + 1) % _numbers.size()


## Slows the world for a few real milliseconds. The timer ignores the time scale, so it always ends.
func _hit_stop() -> void:
	if _stopping or Engine.time_scale < 1.0:
		return
	_stopping = true
	Engine.time_scale = HIT_STOP_SCALE
	await get_tree().create_timer(HIT_STOP_SECONDS, true, false, true).timeout
	Engine.time_scale = 1.0
	_stopping = false


func _make_emitter(colour: Color, amount: int, size: float, speed: float, lifetime: float) -> CPUParticles3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	quad.material = material
	var emitter := CPUParticles3D.new()
	emitter.mesh = quad
	emitter.amount = amount
	emitter.lifetime = lifetime
	emitter.one_shot = true
	emitter.explosiveness = 1.0
	emitter.emitting = false
	emitter.direction = Vector3.UP
	emitter.spread = 70.0
	emitter.initial_velocity_min = speed * 0.5
	emitter.initial_velocity_max = speed
	emitter.gravity = Vector3(0.0, -9.0, 0.0)
	emitter.scale_amount_min = 0.6
	emitter.scale_amount_max = 1.2
	add_child(emitter)
	return emitter
