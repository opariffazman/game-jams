class_name CampScene
extends Node3D
## The hero select set: all four heroes sit around a campfire at night and the camera sweeps slowly across them.
##
## The camp sits far from the street so the street never shows. The models exist only while the screen is open, which keeps the run light.

## Metres from the street origin to the camp. The street chunks end long before this.
const CAMP_OFFSET: Vector3 = Vector3(300.0, 0.0, 0.0)
## Radius in metres of the ring the heroes stand on.
const RING_RADIUS: float = 1.8
## The camera sweeps this far to each side of the open side of the ring, in radians, and takes SWEEP_PERIOD seconds for a full back and forth.
const SWEEP: float = 0.9
const SWEEP_PERIOD: float = 36.0
## The ring is offset by an eighth turn, so no hero stands straight between the camera and the fire with its back to the lens.
const RING_OFFSET: float = PI * 0.25
const ORBIT_RADIUS_LANDSCAPE: float = 7.4
const ORBIT_RADIUS_PORTRAIT: float = 6.4
const ORBIT_HEIGHT: float = 3.0
## Where the camera looks, above the fire.
const LOOK_HEIGHT: float = 1.5
## Height in metres of a hero for the pick area.
const HERO_HEIGHT: float = 2.5
## Share of the turn from "face the fire" to "face the camera". Zero keeps every hero looking at the fire.
const FACE_CAMERA_SHARE: float = 0.0
const TURN_RATE: float = 3.0
## The heroes chat by cycling these one-shot clips between idle spells. No sit clip exists, so they stand.
const IDLE_CLIP: StringName = &"Idle"
const EMOTES: Array[StringName] = [&"Wave", &"Yes", &"No"]
const EMOTE_GAP_MIN: float = 2.0
const EMOTE_GAP_MAX: float = 5.0
const FIRE_LIGHT: Color = Color(1.0, 0.55, 0.2)
const FIRE_ENERGY: float = 2.6
const GROUND_COLOR: Color = Color(0.1, 0.1, 0.13)
const GROUND_RADIUS: float = 40.0
## Flame cones from the widest to the narrowest. The kit fire is too small to read from the camera, so these tall tongues carry the fire.
const FLAME_TONGUES: int = 3
const FLAME_HEIGHT: float = 1.5
const FLAME_RADIUS: float = 0.5
## The highlighted hero grows by this share and stands on a warm ring, so the cue never hides the character and needs no colour to read.
const HIGHLIGHT_SCALE: float = 1.12
const HIGHLIGHT_RATE: float = 8.0
const RING_INNER: float = 0.5
const RING_OUTER: float = 1.0
const RING_COLOUR: Color = Color(1.0, 0.78, 0.35)

var _heroes: Dictionary[StringName, Node3D] = {}
var _players: Dictionary[StringName, AnimationPlayer] = {}
var _reacting: Dictionary[StringName, bool] = {}
var _emote_timers: Dictionary[StringName, float] = {}
var _ring_angles: Dictionary[StringName, float] = {}
var _camp_props: MeshInstance3D
var _ground: MeshInstance3D
var _light: OmniLight3D
var _flames: Array[MeshInstance3D] = []
var _rings: Dictionary[StringName, MeshInstance3D] = {}
var _highlight_id: StringName = &""
var _angle: float = 0.0
var _clock: float = 0.0
var _built: bool = false


## Returns the world position of the camp centre.
static func centre() -> Vector3:
	return CAMP_OFFSET


## Creates the camp and the four heroes. Safe to call twice.
func open() -> void:
	if _built:
		return
	_built = true
	_build_ground()
	_build_props()
	_build_flames()
	_light = OmniLight3D.new()
	_light.light_color = FIRE_LIGHT
	_light.light_energy = FIRE_ENERGY
	_light.omni_range = 11.0
	_light.position = CAMP_OFFSET + Vector3(0.0, 1.1, 0.0)
	add_child(_light)
	var count: int = HeroTable.HEROES.size()
	for index: int in count:
		_build_hero(HeroTable.HEROES[index], RING_OFFSET + float(index) * TAU / float(count))
	visible = true


## Frees the camp.
func close() -> void:
	for child: Node in get_children():
		child.queue_free()
	_flames.clear()
	_heroes.clear()
	_players.clear()
	_reacting.clear()
	_emote_timers.clear()
	_ring_angles.clear()
	_rings.clear()
	_highlight_id = &""
	_built = false
	visible = false


func is_open() -> bool:
	return _built


## Sweeps the camera across the camp, flickers the fire and keeps the heroes facing the fire.
func update(delta: float, camera: Camera3D, portrait: bool) -> void:
	if not _built:
		return
	_clock += delta
	_angle = sin(_clock * TAU / SWEEP_PERIOD) * SWEEP
	var radius: float = ORBIT_RADIUS_PORTRAIT if portrait else ORBIT_RADIUS_LANDSCAPE
	camera.global_position = CAMP_OFFSET + Vector3(sin(_angle) * radius, ORBIT_HEIGHT, cos(_angle) * radius)
	camera.look_at(CAMP_OFFSET + Vector3(0.0, LOOK_HEIGHT, 0.0))
	for index: int in _flames.size():
		var flicker: float = 1.0 + 0.18 * sin(_clock * (11.0 + index * 4.0) + index * 2.0)
		_flames[index].scale = Vector3(1.0 / flicker, flicker, 1.0 / flicker)
		_flames[index].rotation.y = _clock * (1.5 + index)
	_light.light_energy = FIRE_ENERGY * (0.88 + 0.12 * sin(_clock * 17.0) * sin(_clock * 7.3 + 1.0))
	_tick_emotes(delta)
	var grow: float = 1.0 - exp(-HIGHLIGHT_RATE * delta)
	for id: StringName in _heroes:
		var target: float = RailsHero.MODEL_SCALE * (HIGHLIGHT_SCALE if id == _highlight_id else 1.0)
		_heroes[id].scale = _heroes[id].scale.lerp(Vector3.ONE * target, grow)
		_rings[id].visible = id == _highlight_id
		var pulse: float = 1.0 + 0.05 * sin(_clock * 4.0)
		_rings[id].scale = Vector3(pulse, 0.12, pulse)
	var turn: float = 1.0 - exp(-TURN_RATE * delta)
	for id: StringName in _heroes:
		var hero: Node3D = _heroes[id]
		var to_camera: Vector3 = camera.global_position - hero.global_position
		var to_fire: Vector3 = CAMP_OFFSET - hero.global_position
		var toward_camera: float = atan2(to_camera.x, to_camera.z)
		var toward_fire: float = atan2(to_fire.x, to_fire.z)
		hero.rotation.y = lerp_angle(hero.rotation.y, lerp_angle(toward_fire, toward_camera, FACE_CAMERA_SHARE), turn)


## Returns each hero's pick area in the viewport's pixels, keyed by hero id. The area covers the whole body.
func screen_targets(camera: Camera3D) -> Dictionary[StringName, Rect2]:
	var rects: Dictionary[StringName, Rect2] = {}
	for id: StringName in _heroes:
		var foot_world: Vector3 = _heroes[id].global_position
		if camera.is_position_behind(foot_world):
			continue
		var foot: Vector2 = camera.unproject_position(foot_world)
		var head: Vector2 = camera.unproject_position(foot_world + Vector3(0.0, HERO_HEIGHT, 0.0))
		var height: float = absf(foot.y - head.y)
		var width: float = height * 0.55
		rects[id] = Rect2(Vector2(foot.x - width * 0.5, head.y), Vector2(width, height))
	return rects


## Plays a clip once on one hero, then returns to idle. A busy hero ignores a plain call, so a hand sweeping across the group does not restart every wave.
func react(id: StringName, clip: StringName, force: bool = false) -> void:
	var player: AnimationPlayer = _players.get(id)
	if player == null or not player.has_animation(clip) or (_reacting.has(id) and not force):
		return
	_reacting[id] = true
	player.play(clip, AnimUtil.BLEND_SECONDS)


## Marks one hero as the highlighted one: a ground ring and a slight scale-up.
func highlight(id: StringName) -> void:
	_highlight_id = id


func _idle(id: StringName) -> void:
	var player: AnimationPlayer = _players.get(id)
	if player == null:
		return
	_reacting.erase(id)
	_emote_timers[id] = randf_range(EMOTE_GAP_MIN, EMOTE_GAP_MAX)
	player.play(IDLE_CLIP, AnimUtil.BLEND_SECONDS)


## Counts down each idle hero and starts a random emote at zero, so the group looks like it chats and never moves in lockstep.
func _tick_emotes(delta: float) -> void:
	for id: StringName in _emote_timers.keys():
		if _reacting.has(id):
			continue
		_emote_timers[id] -= delta
		if _emote_timers[id] <= 0.0:
			react(id, EMOTES[randi() % EMOTES.size()])


func _on_clip_finished(clip: StringName, id: StringName) -> void:
	if clip != IDLE_CLIP:
		_idle(id)


func _build_hero(spec: Dictionary, angle: float) -> void:
	var id: StringName = spec["id"]
	var hero: Node3D = (load(String(spec["model"])) as PackedScene).instantiate()
	hero.scale = Vector3.ONE * RailsHero.MODEL_SCALE
	add_child(hero)
	hero.global_position = CAMP_OFFSET + Vector3(sin(angle) * RING_RADIUS, 0.0, cos(angle) * RING_RADIUS)
	for weapon_name: StringName in RailsHero.ALL_WEAPONS:
		var node: Node3D = hero.find_child(String(weapon_name), true, false) as Node3D
		if node != null:
			node.visible = false
	var player: AnimationPlayer = AnimUtil.find_player(hero)
	_heroes[id] = hero
	_players[id] = player
	if player != null:
		AnimUtil.configure_loops(player)
		player.animation_finished.connect(func(clip: StringName) -> void: _on_clip_finished(clip, id))
		_idle(id)
		_emote_timers[id] = randf_range(0.5, EMOTE_GAP_MAX)
	_ring_angles[id] = angle
	_rings[id] = _build_ring(hero.global_position)


func _build_ground() -> void:
	_ground = MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = GROUND_RADIUS
	mesh.bottom_radius = GROUND_RADIUS
	mesh.height = 0.1
	mesh.radial_segments = 32
	mesh.rings = 1
	var material := StandardMaterial3D.new()
	material.albedo_color = GROUND_COLOR
	material.roughness = 1.0
	mesh.material = material
	_ground.mesh = mesh
	_ground.position = CAMP_OFFSET + Vector3(0.0, -0.06, 0.0)
	add_child(_ground)


## The camp props come from the level kit, so the select screen and the street camps look alike.
func _build_props() -> void:
	var baker := LevelBaker.new()
	LevelKit.camp(baker, CAMP_OFFSET.x, CAMP_OFFSET.z, -1.0, 1.0, true)
	_camp_props = MeshInstance3D.new()
	_camp_props.mesh = baker.bake()
	add_child(_camp_props)


## Unshaded tongues of flame, so the fire stays bright and visible whatever the light does.
func _build_flames() -> void:
	var colours: Array[Color] = [Color(1.0, 0.35, 0.08), Color(1.0, 0.6, 0.15), Color(1.0, 0.9, 0.5)]
	for index: int in FLAME_TONGUES:
		var share: float = 1.0 - float(index) / float(FLAME_TONGUES)
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.0
		mesh.bottom_radius = FLAME_RADIUS * share
		mesh.height = FLAME_HEIGHT * (0.55 + 0.45 * share)
		mesh.radial_segments = 6
		mesh.rings = 1
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = colours[index]
		mesh.material = material
		var flame := MeshInstance3D.new()
		flame.mesh = mesh
		flame.position = CAMP_OFFSET + Vector3(0.0, mesh.height * 0.5 + 0.1, 0.0)
		add_child(flame)
		_flames.append(flame)


## A flat warm ring on the ground under a hero. It is unshaded, so it stays visible in the dark.
func _build_ring(at: Vector3) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = RING_INNER
	mesh.outer_radius = RING_OUTER
	mesh.rings = 24
	mesh.ring_segments = 6
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = RING_COLOUR
	mesh.material = material
	var ring := MeshInstance3D.new()
	ring.mesh = mesh
	add_child(ring)
	ring.global_position = at + Vector3(0.0, 0.04, 0.0)
	ring.scale = Vector3(1.0, 0.12, 1.0)
	ring.visible = false
	return ring
