class_name FxLayer
extends Node2D
## Short particle bursts for hits, topples, dashes and wins.
##
## The layer lives in the match scene, so bursts follow the camera zoom and shake. It sits above the 3D picture
## and below the HUD. Emitters come from a pool and a burst is skipped when [constant MAX_LIVE] emitters run,
## so a busy scatter never costs frames. A burst keeps the sprite look of the Kenney particle pack.

## Group of the layer.
const GROUP: StringName = &"fx_layer"
## Most emitters alive at once.
const MAX_LIVE: int = 40
const DIR: String = "res://assets/particles/"

## Burst recipes by kind. Each has a texture, count, lifetime, speed range, size range and blend mode.
const KINDS: Dictionary = {
	&"hit": {"texture": "star_04", "count": 10, "lifetime": 0.45, "speed_min": 120.0, "speed_max": 320.0, "scale_min": 0.14, "scale_max": 0.3, "add": true, "gravity": 0.0},
	&"death": {"texture": "star_01", "count": 8, "lifetime": 0.7, "speed_min": 80.0, "speed_max": 220.0, "scale_min": 0.12, "scale_max": 0.26, "add": true, "gravity": 0.0},
	&"topple": {"texture": "dirt_01", "count": 12, "lifetime": 0.8, "speed_min": 90.0, "speed_max": 260.0, "scale_min": 0.12, "scale_max": 0.3, "add": false, "gravity": 0.0},
	&"smoke": {"texture": "smoke_05", "count": 5, "lifetime": 0.6, "speed_min": 20.0, "speed_max": 70.0, "scale_min": 0.15, "scale_max": 0.3, "add": false, "gravity": 0.0},
	&"dash": {"texture": "smoke_01", "count": 4, "lifetime": 0.4, "speed_min": 10.0, "speed_max": 50.0, "scale_min": 0.12, "scale_max": 0.22, "add": false, "gravity": 0.0},
	&"throw": {"texture": "spark_05", "count": 3, "lifetime": 0.25, "speed_min": 60.0, "speed_max": 140.0, "scale_min": 0.1, "scale_max": 0.18, "add": true, "gravity": 0.0},
	&"pickup": {"texture": "circle_05", "count": 3, "lifetime": 0.3, "speed_min": 30.0, "speed_max": 80.0, "scale_min": 0.08, "scale_max": 0.16, "add": true, "gravity": 0.0},
	&"block": {"texture": "circle_05", "count": 6, "lifetime": 0.45, "speed_min": 40.0, "speed_max": 110.0, "scale_min": 0.3, "scale_max": 0.5, "add": true, "gravity": 0.0},
	&"win": {"texture": "star_04", "count": 14, "lifetime": 1.0, "speed_min": 120.0, "speed_max": 300.0, "scale_min": 0.14, "scale_max": 0.3, "add": true, "gravity": 180.0},
}

var _pool: Array[CPUParticles2D] = []
var _textures: Dictionary = {}


func _ready() -> void:
	add_to_group(GROUP)
	z_index = 50
	process_mode = Node.PROCESS_MODE_ALWAYS


## Number of emitters running now.
func live_count() -> int:
	var count: int = 0
	for emitter: CPUParticles2D in _pool:
		if emitter.emitting:
			count += 1
	return count


## Starts the burst [param kind] at [param world_position]. [param tint] multiplies the sprite colour.
## Does nothing for an unknown kind or when [constant MAX_LIVE] emitters run.
func burst(kind: StringName, world_position: Vector2, tint: Color = Color.WHITE) -> void:
	var recipe: Dictionary = KINDS.get(kind, {})
	if recipe.is_empty():
		return
	var emitter: CPUParticles2D = _free_emitter()
	if emitter == null:
		return
	emitter.texture = _texture(recipe["texture"])
	emitter.amount = int(recipe["count"])
	emitter.lifetime = float(recipe["lifetime"])
	emitter.initial_velocity_min = float(recipe["speed_min"])
	emitter.initial_velocity_max = float(recipe["speed_max"])
	emitter.scale_amount_min = float(recipe["scale_min"])
	emitter.scale_amount_max = float(recipe["scale_max"])
	emitter.gravity = Vector2(0.0, float(recipe["gravity"]))
	emitter.color = tint
	var material: CanvasItemMaterial = CanvasItemMaterial.new()
	material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD if recipe["add"] else CanvasItemMaterial.BLEND_MODE_MIX
	emitter.material = material
	# Bursts live in canvas space, so the tilted view needs the projected spot.
	emitter.position = get_viewport().get_canvas_transform().affine_inverse() * ViewProjection.to_screen(get_viewport(), world_position)
	emitter.restart()
	emitter.emitting = true


func _free_emitter() -> CPUParticles2D:
	for emitter: CPUParticles2D in _pool:
		if not emitter.emitting:
			return emitter
	if _pool.size() >= MAX_LIVE:
		return null
	var created: CPUParticles2D = CPUParticles2D.new()
	created.one_shot = true
	created.explosiveness = 1.0
	created.emitting = false
	created.direction = Vector2.UP
	created.spread = 180.0
	created.damping_min = 40.0
	created.damping_max = 80.0
	created.color_ramp = _fade_ramp()
	add_child(created)
	_pool.append(created)
	return created


func _texture(file: String) -> Texture2D:
	if not _textures.has(file):
		_textures[file] = load(DIR + file + ".png") as Texture2D
	return _textures[file]


func _fade_ramp() -> Gradient:
	var ramp: Gradient = Gradient.new()
	ramp.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	ramp.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	return ramp
