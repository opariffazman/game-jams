class_name RailsHero
extends Node3D
## The hero model with a small animation state machine.
##
## Base clips loop and come from the weapon in hand: running during the run, idle on the intro screens.
## One-shot clips (HitReact, Wave, Yes, Slash) play over the base clip, then the base clip resumes.
## A lost heart plays HitReact. Only the last heart plays Death, which holds its final frame until the next set_base.

## Base pose of the hero.
enum Base {
	STOPPED, ## Standing still.
	MOVING, ## Running.
}

## Uniform scale applied to the model.
const MODEL_SCALE: float = 1.35
## Higher values turn toward the aim faster.
const TURN_RATE: float = 8.0
## Names of every weapon on the model. The model ships with all of them on the hand bone, and the table picks the one kept visible.
const ALL_WEAPONS: Array[StringName] = [&"Axe", &"Guitar", &"Knife", &"Pistol", &"Rifle", &"Shotgun", &"SMG", &"Spear", &"WoodenBat_Barbed", &"WoodenBat_Saw"]
## Clips played on a cleared wave, in turn.
const CELEBRATE_CLIPS: Array[StringName] = [&"Wave", &"Yes"]

## Clip that is playing as a one-shot, or empty.
var one_shot_clip: StringName = &""

var _animation: AnimationPlayer
var _model: Node3D
var _spec: Dictionary = HeroTable.get_spec(HeroTable.DEFAULT_ID)
var _weapon: Dictionary = HeroTable.WEAPONS[0]
var _base: Base = Base.STOPPED
var _celebrate_index: int = 0
var _blob: MeshInstance3D
var _models: Dictionary[StringName, Node3D] = {}
var _animations: Dictionary[StringName, AnimationPlayer] = {}


func _ready() -> void:
	_blob = MeshInstance3D.new()
	_blob.mesh = ZombiePool.make_blob_mesh()
	_blob.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	_blob.position = Vector3(0.0, 0.02, 0.0)
	_blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_blob)
	for spec: Dictionary in HeroTable.HEROES:
		_build_model(spec)
	set_hero(HeroTable.DEFAULT_ID)


## Shows the hero from the table. Every model is built once at start, so a preview swap on the hero select screen never loads a file.
## Only that hero's weapon stays visible.
func set_hero(id: StringName) -> void:
	if _model != null and _spec["id"] == id:
		return
	if _model != null:
		_model.visible = false
		_model.process_mode = Node.PROCESS_MODE_DISABLED
	_spec = HeroTable.get_spec(id)
	_model = _models[_spec["id"]]
	_animation = _animations[_spec["id"]]
	_model.visible = true
	_model.process_mode = Node.PROCESS_MODE_INHERIT
	_show_weapon()
	set_base(_base)


## Puts a weapon from the shared inventory in the hero's hand and switches the base clips to match.
func set_weapon(weapon: Dictionary) -> void:
	_weapon = weapon
	_show_weapon()
	set_base(_base)


func _show_weapon() -> void:
	for weapon_name: StringName in ALL_WEAPONS:
		var node: Node3D = _model.find_child(String(weapon_name), true, false) as Node3D
		if node != null:
			node.visible = weapon_name == _weapon["node"]


func _build_model(spec: Dictionary) -> void:
	var model: Node3D = (load(String(spec["model"])) as PackedScene).instantiate()
	model.scale = Vector3.ONE * MODEL_SCALE
	model.visible = false
	model.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(model)
	var player: AnimationPlayer = AnimUtil.find_player(model)
	if player != null:
		AnimUtil.configure_loops(player)
		player.animation_finished.connect(_on_animation_finished)
	_models[spec["id"]] = model
	_animations[spec["id"]] = player


## Returns the table entry of the current hero.
func get_spec() -> Dictionary:
	return _spec


## Returns the weapon in hand.
func get_weapon() -> Dictionary:
	return _weapon


## Returns the mesh of the weapon in hand, or null when the model has none.
func get_weapon_mesh() -> MeshInstance3D:
	return _model.find_child(String(_weapon["node"]), true, false) as MeshInstance3D


## Returns the name of the weapon node that is visible, for tests.
func get_visible_weapons() -> Array[StringName]:
	var shown: Array[StringName] = []
	for weapon_name: StringName in ALL_WEAPONS:
		var weapon: Node3D = _model.find_child(String(weapon_name), true, false) as Node3D
		if weapon != null and weapon.visible:
			shown.append(weapon_name)
	return shown


## Switches the base pose and cancels any one-shot clip.
func set_base(base: Base) -> void:
	_base = base
	one_shot_clip = &""
	AnimUtil.play(_animation, _base_clip())


## Plays HitReact once, then resumes the base clip.
func play_react() -> void:
	_play_one_shot(&"HitReact")


## Plays Death once and stays on the last frame.
## one_shot_clip stays empty, so the finish handler never resumes the base clip.
func play_death() -> void:
	one_shot_clip = &""
	AnimUtil.play(_animation, &"Death", true)


## Plays the swing clip of a melee weapon once, then resumes the base clip.
func play_swing() -> void:
	_play_one_shot(_weapon["swing_clip"])


## Plays Yes or Wave once, for the pick on the hero select screen.
func play_clip(clip: StringName) -> void:
	_play_one_shot(clip)


## Plays Wave or Yes once, then resumes the base clip.
func celebrate() -> void:
	_play_one_shot(CELEBRATE_CLIPS[_celebrate_index % CELEBRATE_CLIPS.size()])
	_celebrate_index += 1


## Returns the clip that is playing now, for the readout and tests.
func get_current_clip() -> StringName:
	return _animation.current_animation if _animation != null else &""


## Turns smoothly to face a horizontal direction.
func face_direction(direction: Vector3, delta: float) -> void:
	if direction.length_squared() < 0.0001:
		return
	var target_yaw: float = atan2(direction.x, direction.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-TURN_RATE * delta))


## Faces down the road and tilts toward the sideways speed, so a lane change reads as a lean.
func run_pose(sideways_speed: float, lean_per_speed: float, max_lean: float) -> void:
	rotation = Vector3(0.0, PI, clampf(sideways_speed * lean_per_speed, -max_lean, max_lean))


func _play_one_shot(clip: StringName) -> void:
	one_shot_clip = clip
	AnimUtil.play(_animation, clip, true)


func _base_clip() -> StringName:
	return _weapon["run_clip"] if _base == Base.MOVING else _weapon["idle_clip"]


func _on_animation_finished(clip: StringName) -> void:
	if clip != one_shot_clip:
		return
	one_shot_clip = &""
	AnimUtil.play(_animation, _base_clip())
