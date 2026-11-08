class_name LevelChunks
extends RefCounted
## Chunk recipes. Every chunk is 5 tiles of 8 m, runs from z = 0 to z = -40, and meets the next one at the same road edge.
##
## Sockets that hold for every chunk: the road is 8 m wide and centred on x = 0, the curb sits at |x| = 4.2,
## the prop strip is 5 to 8.4 m from the centre, and buildings start at 8.4 m. Lamps stand at |x| = 5.

enum Kind { STREET, CROSSROADS, MARKET, PARK, GRAVEYARD, GATE, PORCH }

const LENGTH: float = 40.0
const TILE: float = 8.0
const TILES: int = 5
## Ground slab colours per theme, kept dark and cool so the warm lamps and windows read first.
const PAVEMENT: Color = Color(0.2, 0.18, 0.3)
const GRASS: Color = Color(0.09, 0.2, 0.17)
const GRAVE_GROUND: Color = Color(0.13, 0.17, 0.2)
const SIDE_REACH: float = 36.0

## Triangle count of the mesh that build() returned last, for the budget report.
static var last_triangles: int = 0


## Bakes one chunk. The same kind and variant always give the same mesh.
static func build(kind: Kind, variant: int) -> ArrayMesh:
	var baker := LevelBaker.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 * (int(kind) + 1) + 104729 * variant
	var glow: float = 1.6 if kind == Kind.PORCH else 1.0
	match kind:
		Kind.STREET:
			_road(baker, rng, -1)
			_ground(baker, PAVEMENT, PAVEMENT)
			_street_sides(baker, rng, glow, true)
		Kind.CROSSROADS:
			_road(baker, rng, 2)
			_ground(baker, PAVEMENT, PAVEMENT)
			_crossroads(baker, rng, glow)
		Kind.MARKET:
			_road(baker, rng, -1)
			_ground(baker, PAVEMENT, PAVEMENT)
			_market(baker, rng, glow)
		Kind.PARK:
			_road(baker, rng, -1)
			_ground(baker, GRASS, GRASS)
			_park(baker, rng, glow)
		Kind.GRAVEYARD:
			_road(baker, rng, -1)
			_ground(baker, GRAVE_GROUND, GRAVE_GROUND)
			_graveyard(baker, rng, glow)
		Kind.GATE:
			_road(baker, rng, -1)
			_ground(baker, GRAVE_GROUND, PAVEMENT)
			_gate(baker, rng, glow)
		Kind.PORCH:
			_road(baker, rng, -1)
			_ground(baker, PAVEMENT, PAVEMENT)
			_porch(baker, rng, glow)
	last_triangles = baker.triangle_count()
	return baker.bake()


## Five road tiles. A junction tile replaces the tile at the given index, and a negative index means none.
static func _road(baker: LevelBaker, rng: RandomNumberGenerator, junction: int) -> void:
	for tile: int in TILES:
		var z: float = -TILE * 0.5 - TILE * float(tile)
		var model: String = "Street_Straight"
		if tile == junction:
			model = "Street_4Way"
		elif rng.randf() < 0.25:
			model = "Street_Straight_Crack1"
		baker.add_model(model, LevelKit.at(0.0, z, PI * 0.5 * float(rng.randi() % 2) * 2.0))


## Flat slabs that colour the strip beside the road. The left and right sides can differ.
static func _ground(baker: LevelBaker, left: Color, right: Color) -> void:
	var middle: float = -LENGTH * 0.5
	var width: float = SIDE_REACH - 4.0
	baker.add_box(LevelBaker.COLOR, LevelKit.at(-4.0 - width * 0.5, middle, 0.0, 0.01), Vector3(width, 0.04, LENGTH), left)
	baker.add_box(LevelBaker.COLOR, LevelKit.at(4.0 + width * 0.5, middle, 0.0, 0.01), Vector3(width, 0.04, LENGTH), right)


## Houses, lamps, fences and clutter in the strip beside the road.
static func _street_sides(baker: LevelBaker, rng: RandomNumberGenerator, glow: float, with_cars: bool) -> void:
	for side: float in [-1.0, 1.0]:
		for slot: int in TILES:
			var z: float = -TILE * 0.5 - TILE * float(slot)
			LevelKit.house(baker, side, z, rng, glow)
		LevelKit.fence(baker, side * 8.0, -0.5, -39.5, Color(0.4, 0.3, 0.22) * 0.8, rng)
		for slot: int in (2 if Quality.is_high() else 1):
			_curb_clutter(baker, side, -3.0 - float(slot) * 19.0 - rng.randf_range(0.0, 3.0), rng)
		LevelKit.clutter_strip(baker, rng, side, -1.0, -39.0, 3.2, 5.6, 7.7)
	_lamps(baker, glow)
	# A wreck is 6k triangles, so only the high tier bakes one. It sits half on the pavement and leaves the lanes clear.
	if with_cars and Quality.is_high():
		var side: float = 1.0 if rng.randf() < 0.5 else -1.0
		LevelKit.wreck(baker, side * 6.3, -rng.randf_range(10.0, 30.0), side * 0.1, rng)


## Lamps alternate sides every 16 m, which is how the lanes read without any lane lines.
static func _lamps(baker: LevelBaker, glow: float) -> void:
	for slot: int in 3:
		var side: float = 1.0 if slot % 2 == 0 else -1.0
		LevelKit.lamp(baker, side, -4.0 - float(slot) * 16.0, glow)


static func _curb_clutter(baker: LevelBaker, side: float, z: float, rng: RandomNumberGenerator) -> void:
	var x: float = side * rng.randf_range(5.6, 7.2)
	match rng.randi() % 5:
		0:
			LevelKit.barrel(baker, x, z)
		1:
			LevelKit.bag(baker, x, z)
		2:
			LevelKit.hydrant(baker, x, z)
		3:
			LevelKit.cone(baker, x, z)
			LevelKit.cone(baker, x, z - 1.0)
		4:
			LevelKit.sandbags(baker, x, z, rng.randf() * TAU)
			LevelKit.prop(baker, "Wheel", x + side * 0.6, z - 1.0, rng.randf() * TAU, 1.0, LevelKit.SOOT)


static func _crossroads(baker: LevelBaker, rng: RandomNumberGenerator, glow: float) -> void:
	var junction_z: float = -TILE * 0.5 - TILE * 2.0
	for side: float in [-1.0, 1.0]:
		for step: int in 3:
			baker.add_model("Street_Straight", LevelKit.at(side * (TILE + TILE * float(step)), junction_z, PI * 0.5))
		for slot: int in TILES:
			if slot == 2:
				continue
			LevelKit.house(baker, side, -TILE * 0.5 - TILE * float(slot), rng, glow)
		for corner: float in [-1.0, 1.0]:
			LevelKit.house(baker, side * 2.9, junction_z + corner * 14.0, rng, glow)
		LevelKit.fence(baker, side * 8.0, -0.5, -12.0, Color(0.32, 0.24, 0.18), rng)
		LevelKit.fence(baker, side * 8.0, -28.0, -39.5, Color(0.32, 0.24, 0.18), rng)
		LevelKit.clutter_strip(baker, rng, side, -1.0, -12.0, 3.0, 5.5, 7.6)
		LevelKit.clutter_strip(baker, rng, side, -28.0, -39.0, 3.0, 5.5, 7.6)
		if side > 0.0:
			LevelKit.barricade(baker, side * 6.0, junction_z + 7.0, PI * 0.5, rng)
		LevelKit.prop(baker, "Wheels_Stack", side * 5.4, junction_z + 5.6 * side, 0.0, 1.0, LevelKit.SOOT)
		LevelKit.decal(baker, side * 4.9, junction_z - 5.0 * side, rng)
	LevelKit.traffic_light(baker, 5.2, junction_z + 5.0, PI, glow)
	LevelKit.traffic_light(baker, -5.2, junction_z - 5.0, 0.0, glow)
	LevelKit.lamp(baker, 1.0, junction_z + 12.0, glow)
	LevelKit.lamp(baker, -1.0, junction_z - 12.0, glow)
	LevelKit.cone(baker, 4.8, -3.0)
	LevelKit.cone(baker, 4.8, -4.2)
	baker.add_model("PlasticBarrier", LevelKit.at(-5.6, -34.0, 0.4), LevelKit.DIRT)
	LevelKit.prop(baker, "TownSign", 7.8, junction_z - 9.0, -PI * 0.5, 0.45, LevelKit.DIRT * 0.8)


## Stalls with striped awnings and lantern bulbs. The goods are sandbags, barrels and crates.
static func _market(baker: LevelBaker, rng: RandomNumberGenerator, glow: float) -> void:
	var awnings: Array[Color] = [Color(0.95, 0.4, 0.1), Color(0.55, 0.2, 0.75), Color(0.15, 0.7, 0.55)]
	for side: float in [-1.0, 1.0]:
		for slot: int in 4:
			var z: float = -4.0 - float(slot) * 9.5
			var x: float = side * 6.6
			baker.add_box(LevelBaker.COLOR, LevelKit.at(x, z, 0.0, 0.5), Vector3(1.6, 1.0, 3.6), LevelKit.WOOD)
			for post: float in [-1.7, 1.7]:
				baker.add_box(LevelBaker.COLOR, LevelKit.at(x + side * 0.7, z + post, 0.0, 1.3), Vector3(0.12, 2.6, 0.12), LevelKit.WOOD)
			var tilt: Basis = Basis(Vector3.UP, -side * PI * 0.5) * Basis(Vector3.RIGHT, 0.35 * side * -1.0)
			baker.add_panel_gradient(LevelBaker.GLOW, Transform3D(tilt, Vector3(x - side * 0.2, 2.5, z)), Vector2(3.8, 1.5), awnings[rng.randi() % awnings.size()], awnings[rng.randi() % awnings.size()] * 0.35)
			LevelKit.lantern(baker, x - side * 0.8, 2.2, z + 1.5)
			LevelKit.lantern(baker, x - side * 0.8, 2.2, z - 1.5)
			for crate: int in 3:
				LevelKit.sandbags(baker, x - side * 0.1, z - 1.0 + float(crate) * 1.0, PI * 0.5)
		baker.add_model("Container_Red" if side < 0.0 else "Container_Green", LevelKit.at(side * 11.0, -20.0, PI * 0.5), Color(0.55, 0.45, 0.4))
		for slot: int in 4:
			var z: float = -4.0 - float(slot) * 9.5
			for crate: int in 2:
				var crate_z: float = z - 2.6 - float(crate) * 1.1
				var crate_x: float = side * rng.randf_range(5.4, 5.9)
				LevelKit.prop(baker, "Pallet", crate_x, crate_z, rng.randf() * TAU, 1.0, LevelKit.DIRT * 0.7)
				LevelKit.prop(baker, "Barrel" if crate == 0 else "Pallet_Broken", crate_x, crate_z, rng.randf() * TAU, 1.0, LevelKit.RUST * 1.2, 0.14)
		LevelKit.clutter_strip(baker, rng, side, -2.0, -39.0, 3.4, 5.3, 5.8)
		LevelKit.prop(baker, "Wheels_Stack", side * 5.5, -19.0, 0.0, 1.0, LevelKit.SOOT)
		LevelKit.prop(baker, "Wheel", side * 5.6, -25.5, rng.randf() * TAU, 1.0, LevelKit.SOOT)
		LevelKit.prop(baker, "Pallet", side * 6.0, -37.5, rng.randf() * TAU, 1.0, LevelKit.DIRT * 0.7)
		LevelKit.barricade(baker, side * 6.8, -28.5 if side < 0.0 else -9.8, PI * 0.5, rng)
		LevelKit.fence(baker, side * 8.0, -0.5, -39.5, Color(0.32, 0.24, 0.18), rng)
		LevelKit.house(baker, side, -6.0, rng, glow)
		LevelKit.house(baker, side, -34.0, rng, glow)
	_lamps(baker, glow)


static func _park(baker: LevelBaker, rng: RandomNumberGenerator, glow: float) -> void:
	for side: float in [-1.0, 1.0]:
		for index: int in 8:
			var z: float = -2.5 - float(index) * 4.8
			LevelKit.tree(baker, side * rng.randf_range(8.5, 15.0), z + rng.randf_range(-1.0, 1.0), rng, rng.randf_range(3.6, 5.2))
		for slot: int in 4:
			var z: float = -5.0 - float(slot) * 10.0
			LevelKit.fence(baker, side * 5.8, z, z - 5.0, Color(0.3, 0.23, 0.17), rng)
			LevelKit.prop(baker, "WoodLog", side * rng.randf_range(6.4, 8.0), z - 6.5, rng.randf() * TAU, 1.0, LevelKit.DIRT)
		for fly: int in 12:
			var spot := Vector3(side * rng.randf_range(5.0, 12.0), rng.randf_range(0.6, 3.2), -rng.randf_range(1.0, 39.0))
			baker.add_sphere(LevelBaker.GLOW, Transform3D(Basis.IDENTITY, spot), 0.07, Color(0.75, 1.0, 0.45), 2, 4)
	# The camp sits on the left, off the lanes, so its glow reads from the road. Fire is landmark and stays on both tiers.
	LevelKit.camp(baker, -8.0, -12.0, -1.0, glow)
	LevelKit.camp(baker, 8.0, -31.0, 1.0, glow, Quality.is_high())
	for side: float in [-1.0, 1.0]:
		LevelKit.clutter_strip(baker, rng, side, -2.0, -39.0, 4.2, 5.4, 6.0)
		for log: int in 4:
			LevelKit.prop(baker, "WoodLog", side * rng.randf_range(6.4, 10.0), -rng.randf_range(2.0, 38.0), rng.randf() * TAU, 0.6, Color.WHITE * 0.75)
	_lamps(baker, glow)


static func _graveyard(baker: LevelBaker, rng: RandomNumberGenerator, glow: float) -> void:
	for side: float in [-1.0, 1.0]:
		for index: int in 10:
			var z: float = -2.0 - float(index) * 3.9
			LevelKit.tombstone(baker, side * rng.randf_range(6.0, 13.0), z, rng)
		for index: int in 3:
			LevelKit.tree(baker, side * rng.randf_range(10.0, 16.0), -6.0 - float(index) * 13.0, rng, 5.0)
		LevelKit.fence(baker, side * 5.6, -0.5, -39.5, Color(0.12, 0.12, 0.18), rng)
		LevelKit.clutter_strip(baker, rng, side, -2.0, -39.0, 5.0, 6.2, 8.0)
		LevelKit.decal(baker, side * rng.randf_range(5.0, 6.0), -rng.randf_range(5.0, 35.0), rng)
		for index: int in 3:
			LevelKit.prop(baker, "BearTrap_Open", side * rng.randf_range(6.5, 9.0), -rng.randf_range(4.0, 36.0), rng.randf() * TAU, 0.3, LevelKit.SOOT * 1.5)
		for slot: int in 2:
			var z: float = -9.0 - float(slot) * 20.0
			LevelKit.torch(baker, side * 5.2, z, glow)
		for candle: int in 8:
			baker.add_sphere(LevelBaker.GLOW, Transform3D(Basis.IDENTITY, Vector3(side * rng.randf_range(6.5, 11.0), 0.2, -rng.randf_range(2.0, 38.0))), 0.1, Color(1.0, 0.85, 0.45), 2, 4)
	_lamps(baker, glow * 0.8)


## Stone gate across the road. It marks the move from the town into the dark and is the one place the lanes pass between pillars.
static func _gate(baker: LevelBaker, rng: RandomNumberGenerator, glow: float) -> void:
	var gate_z: float = -20.0
	var stone: Color = LevelKit.STONE * 0.8
	for side: float in [-1.0, 1.0]:
		baker.add_box(LevelBaker.COLOR, LevelKit.at(side * 5.2, gate_z, 0.0, 2.6), Vector3(1.3, 5.2, 1.3), stone)
		baker.add_box(LevelBaker.COLOR, LevelKit.at(side * 5.2, gate_z, 0.0, 5.4), Vector3(1.6, 0.4, 1.6), stone * 1.15)
		LevelKit.lantern(baker, side * 4.3, 4.4, gate_z)
		baker.add_disc(LevelBaker.POOL, LevelKit.at(side * 4.3, gate_z, 0.0, 0.07), 3.0, LevelKit.POOL_GLOW * glow)
		LevelKit.fence(baker, side * 7.0, gate_z - 1.0, -39.5, Color(0.12, 0.12, 0.18), rng)
		LevelKit.fence(baker, side * 7.0, -0.5, gate_z + 1.0, Color(0.12, 0.12, 0.18), rng)
		for index: int in 4:
			LevelKit.tree(baker, side * rng.randf_range(9.0, 15.0), -4.0 - float(index) * 10.0, rng, 4.6)
	LevelKit.camp(baker, -7.5, gate_z + 6.0, -1.0, glow, false)
	LevelKit.barricade(baker, 6.0, gate_z - 7.0, PI * 0.5, rng)
	LevelKit.barricade(baker, -6.0, gate_z + 9.0, PI * 0.5, rng)
	for side: float in [-1.0, 1.0]:
		LevelKit.clutter_strip(baker, rng, side, -1.0, -39.0, 3.6, 5.3, 6.4)
	baker.add_box(LevelBaker.COLOR, LevelKit.at(0.0, gate_z, 0.0, 5.0), Vector3(11.0, 0.5, 0.8), stone)
	LevelKit.barrel(baker, 0.0, gate_z)
	baker.add_box(LevelBaker.COLOR, LevelKit.at(0.0, gate_z, 0.0, 5.4), Vector3(11.0, 0.25, 0.4), stone * 1.2)
	LevelKit.lamp(baker, -1.0, -34.0, glow)


## Brighter street that ends the loop. A porch house stands on the left with a big warm door light and sandbags along the path.
static func _porch(baker: LevelBaker, rng: RandomNumberGenerator, glow: float) -> void:
	for slot: int in TILES:
		if slot != 2:
			LevelKit.house(baker, 1.0, -TILE * 0.5 - TILE * float(slot), rng, glow)
		if slot != 1 and slot != 2:
			LevelKit.house(baker, -1.0, -TILE * 0.5 - TILE * float(slot), rng, glow)
	var home_z: float = -20.0
	var wall := Color(0.55, 0.32, 0.38)
	baker.add_box(LevelBaker.COLOR, LevelKit.at(-14.0, home_z, 0.0, 3.2), Vector3(8.0, 6.4, 10.0), wall)
	baker.add_gable(LevelBaker.COLOR, LevelKit.at(-14.0, home_z, 0.0, 6.4), 10.0, 3.0, 9.6, LevelKit.ROOF_COLOR, 0.6)
	baker.add_box(LevelBaker.COLOR, LevelKit.at(-9.5, home_z, 0.0, 0.15), Vector3(2.6, 0.3, 5.0), LevelKit.WOOD)
	baker.add_panel(LevelBaker.GLOW, LevelKit.at(-9.97, home_z, -PI * 0.5, 1.5), Vector2(1.6, 2.8), Color(1.0, 0.82, 0.45) * glow)
	baker.add_disc(LevelBaker.POOL, LevelKit.at(-7.0, home_z, 0.0, 0.07), 6.5, Color(0.8, 0.55, 0.22))
	for window_z: float in [-3.0, 3.0]:
		baker.add_panel(LevelBaker.GLOW, LevelKit.at(-9.97, home_z + window_z, -PI * 0.5, 4.4), Vector2(1.2, 1.4), LevelKit.WINDOW_GLOW * glow)
	for step: int in 5:
		LevelKit.sandbags(baker, -5.8 - float(step) * 0.8, home_z + 1.9)
		LevelKit.sandbags(baker, -5.8 - float(step) * 0.8, home_z - 1.9)
	for slot: int in 5:
		var side: float = 1.0 if slot % 2 == 0 else -1.0
		LevelKit.lamp(baker, side, -3.0 - float(slot) * 8.0, glow)
	for side: float in [-1.0, 1.0]:
		LevelKit.fence(baker, side * 8.0, -0.5, -39.5, Color(0.55, 0.4, 0.3), rng)
		LevelKit.clutter_strip(baker, rng, side, -1.0, -39.0, 4.0, 5.3, 6.8)
	# The home camp: a fire in the yard of the lit house, so the end of the run is warm and lived in.
	LevelKit.camp(baker, -6.8, home_z + 8.5, -1.0, glow * 0.8)
	LevelKit.wreck(baker, 6.4, -8.0, 0.1, rng)
	LevelKit.barricade(baker, 6.4, -31.0, PI * 0.5, rng)
