class_name RailsCourse
extends Node3D
## The endless Halloween street. It leads the player home by light: town, market, park, gate, graveyard, then a bright porch.
##
## Every chunk mesh is baked once at start. A small pool of nodes slides toward the hero and swaps meshes as chunks pass,
## so nothing is instantiated while the run is going. Lanes are never drawn, the lamps on alternating sides carry the lane language.

const KIND_SEQUENCE: Array[LevelChunks.Kind] = [
	LevelChunks.Kind.STREET, LevelChunks.Kind.STREET, LevelChunks.Kind.CROSSROADS, LevelChunks.Kind.MARKET,
	LevelChunks.Kind.STREET, LevelChunks.Kind.PARK, LevelChunks.Kind.PARK, LevelChunks.Kind.GATE,
	LevelChunks.Kind.GRAVEYARD, LevelChunks.Kind.GRAVEYARD, LevelChunks.Kind.STREET, LevelChunks.Kind.PORCH,
]
## Variants baked per kind. Together with the kind they pick each chunk's props deterministically.
const VARIANTS: int = 2
## Chunks behind the hero and ahead of it. Ahead reaches past the fog, so a swap never shows.
const CHUNKS_BEHIND: int = 1
const CHUNKS_AHEAD: int = 1
## Fog colour and density per kind. The porch stays warmer and thinner, so home glows at the end of the dark.
const FOG_NIGHT: Color = Color(0.11, 0.08, 0.22)
const FOG_PARK: Color = Color(0.07, 0.12, 0.2)
const FOG_GRAVE: Color = Color(0.06, 0.09, 0.19)
const FOG_HOME: Color = Color(0.2, 0.11, 0.2)
const FOG_BLEND_SPEED: float = 0.8
## Exponential fog density. Was 0.026. Hides hazards that spawn 60 m out and lets them show from about 30 m.
const FOG_DENSITY: float = 0.045
## Seconds between bridge updates. The test reads render cost at this rate.
const BRIDGE_INTERVAL: float = 0.25

var chunk_count: int:
	get:
		return CHUNKS_BEHIND + 1 + CHUNKS_AHEAD

## Extra metres added to the drawn street only. Zero in play.
var view_offset: float = 0.0

var _bridge_clock: float = 0.0
var _meshes: Dictionary = {}
var _slots: Array[MeshInstance3D] = []
var _slot_chunk: Array[int] = []
var _environment: Environment
var _fog_target: Color = FOG_NIGHT
var _first_chunk: int = -1000
var _last_distance: float = 0.0


func _ready() -> void:
	var started: int = Time.get_ticks_msec()
	for kind: LevelChunks.Kind in LevelChunks.Kind.values():
		for variant: int in VARIANTS:
			_meshes[_key(kind, variant)] = LevelChunks.build(kind, variant)
	print("LEVEL baked %d chunk meshes in %d ms" % [_meshes.size(), Time.get_ticks_msec() - started])
	for index: int in chunk_count:
		var slot := MeshInstance3D.new()
		slot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(slot)
		_slots.append(slot)
		_slot_chunk.append(-1000)
	_build_backdrop()
	var world_environment: WorldEnvironment = get_parent().get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_environment != null:
		_environment = world_environment.environment
		_environment.fog_enabled = true
		_environment.fog_light_color = FOG_NIGHT
		_environment.fog_density = FOG_DENSITY
		_environment.background_color = FOG_NIGHT
	set_scroll(0.0)


## Kind of the chunk with the given index. The sequence repeats, so the run never ends.
static func kind_of(chunk: int) -> LevelChunks.Kind:
	return KIND_SEQUENCE[posmod(chunk, KIND_SEQUENCE.size())]


## Variant of the chunk with the given index. It depends on the index only, so a run always looks the same.
static func variant_of(chunk: int) -> int:
	return posmod(chunk * 7 + chunk / KIND_SEQUENCE.size(), VARIANTS)


## Slides the street to match the distance the hero has run and swaps a mesh into any slot whose chunk changed.
func set_scroll(run_distance: float) -> void:
	_last_distance = run_distance
	var distance: float = run_distance + view_offset
	var hero_chunk: int = int(floorf(distance / LevelChunks.LENGTH))
	var first: int = hero_chunk - CHUNKS_BEHIND
	for chunk: int in range(first, first + chunk_count):
		var slot_index: int = posmod(chunk, chunk_count)
		var slot: MeshInstance3D = _slots[slot_index]
		if _slot_chunk[slot_index] != chunk:
			_slot_chunk[slot_index] = chunk
			slot.mesh = _meshes[_key(kind_of(chunk), variant_of(chunk))]
		slot.position.z = distance - float(chunk) * LevelChunks.LENGTH
	_first_chunk = first
	_fog_target = _fog_for(kind_of(hero_chunk))


func _process(delta: float) -> void:
	_bridge_clock += delta
	if _bridge_clock >= BRIDGE_INTERVAL and OS.has_feature("web"):
		_bridge_clock = 0.0
		_sync_bridge()
	if _environment == null:
		return
	var blend: float = clampf(FOG_BLEND_SPEED * delta, 0.0, 1.0)
	var colour: Color = _environment.fog_light_color.lerp(_fog_target, blend)
	_environment.fog_light_color = colour
	_environment.background_color = colour


## Publishes render cost and the chunk under the hero, and reads a chunk jump the level test asks for.
## The jump shifts only what the street draws, never the director distance, so zombies and pickups keep their timing.
func _sync_bridge() -> void:
	var draws: int = int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	var primitives: int = int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	var script: String = "(function(b){b.levelDraws=%d;b.levelTris=%d;b.levelChunk=%d;b.levelKind=%d;b.levelStreetTris=%d;var j=b.levelJump;if(j!==undefined&&j!==null){b.levelJump=null;return j;}return b.levelHide?-2:-1;})(window.railsBridge)" % [draws, primitives, current_chunk(), int(kind_of(current_chunk())), visible_triangles()]
	var jump: Variant = JavaScriptBridge.eval(script)
	visible = jump == null or float(jump) != -2.0
	_apply_hidden_groups()
	if jump != null and float(jump) >= 0.0:
		view_offset = float(jump) * LevelChunks.LENGTH - _last_distance
		set_scroll(_last_distance)


## Hides the named sibling nodes the profile test lists, so each group's draw cost shows as a difference.
func _apply_hidden_groups() -> void:
	var names: Variant = JavaScriptBridge.eval("window.railsBridge.levelOff||''")
	var hidden: PackedStringArray = String(names).split(",", false)
	for node_name: String in ["ZombiePool", "Hero", "Confetti", "Juice", "Hud", "Sun"]:
		var node: Node = get_parent().get_node_or_null(node_name)
		if node != null and "visible" in node:
			node.visible = not hidden.has(node_name)
	if _environment != null:
		_environment.fog_enabled = not hidden.has("Fog")
	LevelBaker.material_for(LevelBaker.POOL).albedo_color.a = 0.0 if hidden.has("Pool") else 1.0
	for index: int in _slots.size():
		_slots[index].visible = not hidden.has("Chunks")
	for index: int in range(_slots.size(), get_child_count()):
		(get_child(index) as MeshInstance3D).visible = not hidden.has("Backdrop")


## Chunk index and kind under the hero, for tests and the debug line.
func current_chunk() -> int:
	return int(floorf((_last_distance + view_offset) / LevelChunks.LENGTH))


## Pool nodes in use and the sum of their triangles, for the budget test.
func visible_triangles() -> int:
	var total: int = 0
	for slot: MeshInstance3D in _slots:
		var mesh: ArrayMesh = slot.mesh as ArrayMesh
		if mesh == null:
			continue
		for surface: int in mesh.get_surface_count():
			total += mesh.surface_get_array_index_len(surface) / 3
	return total


func _fog_for(kind: LevelChunks.Kind) -> Color:
	match kind:
		LevelChunks.Kind.PARK:
			return FOG_PARK
		LevelChunks.Kind.GRAVEYARD, LevelChunks.Kind.GATE:
			return FOG_GRAVE
		LevelChunks.Kind.PORCH:
			return FOG_HOME
	return FOG_NIGHT


func _key(kind: LevelChunks.Kind, variant: int) -> int:
	return int(kind) * 10 + variant


## Ground far beyond the chunks and a moon that ignores fog, so the horizon is never an empty void.
func _build_backdrop() -> void:
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(160.0, 200.0)
	ground.mesh = plane
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.07, 0.07, 0.13)
	ground_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ground.material_override = ground_material
	ground.position = Vector3(0.0, -0.06, -90.0)
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground)
	var moon := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 7.0
	sphere.height = 14.0
	sphere.radial_segments = 20
	sphere.rings = 10
	moon.mesh = sphere
	var moon_material := StandardMaterial3D.new()
	moon_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	moon_material.albedo_color = Color(1.0, 0.92, 0.7)
	moon_material.disable_fog = true
	moon.material_override = moon_material
	moon.position = Vector3(-34.0, 40.0, -170.0)
	moon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(moon)
