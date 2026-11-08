class_name LevelKit
extends RefCounted
## Prop recipes shared by every chunk. Each one draws into a LevelBaker and takes a position on the ground.

const LAMP_GLOW: Color = Color(1.0, 0.82, 0.45)
const POOL_GLOW: Color = Color(0.55, 0.38, 0.14)
const WINDOW_GLOW: Color = Color(1.0, 0.78, 0.38)
const WALL_COLORS: Array[Color] = [
	Color(0.36, 0.24, 0.46), Color(0.25, 0.3, 0.46), Color(0.42, 0.26, 0.34), Color(0.22, 0.36, 0.38),
]
const ROOF_COLOR: Color = Color(0.13, 0.09, 0.2)
const WOOD: Color = Color(0.3, 0.19, 0.12)
const LEAF: Color = Color(0.16, 0.3, 0.24)
const STONE: Color = Color(0.5, 0.52, 0.62)


static func at(x: float, z: float, yaw: float = 0.0, y: float = 0.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw), Vector3(x, y, z))


## Street lamp whose arm reaches over the road from the given side. A warm pool of light lies under the lamp head.
static func lamp(baker: LevelBaker, side: float, z: float, glow: float = 1.0) -> void:
	var reach: float = 2.3
	baker.add_model("StreetLights", at(side * 5.0, z, -side * PI * 0.5), Color.WHITE, LAMP_GLOW * glow)
	var pool_colour: Color = POOL_GLOW * glow
	pool_colour.a = 1.0
	baker.add_disc(LevelBaker.POOL, at(side * (5.0 - reach), z, 0.0, 0.06), 3.6, pool_colour)


## Two storey house with a gable roof, framed windows and a door. The front faces the road.
## The kit has no buildings, so the body stays a box. Every window gets a frame and sill so it reads as a hole in a wall,
## and some are dark or boarded, because a street where every window glows reads as clean.
static func house(baker: LevelBaker, side: float, z: float, rng: RandomNumberGenerator, lit: float = 1.0) -> void:
	var width: float = rng.randf_range(5.0, 6.4)
	var depth: float = rng.randf_range(5.0, 6.5)
	var height: float = rng.randf_range(4.6, 6.6)
	var x: float = side * (8.4 + width * 0.5)
	var wall: Color = WALL_COLORS[rng.randi() % WALL_COLORS.size()] * rng.randf_range(0.55, 0.8)
	baker.add_box(LevelBaker.COLOR, at(x, z, 0.0, height * 0.5), Vector3(width, height, depth), wall)
	# A darker skirt where rain and mud splash the wall.
	baker.add_box(LevelBaker.COLOR, at(x, z, 0.0, 0.5), Vector3(width + 0.06, 1.0, depth + 0.06), wall * 0.6)
	baker.add_gable(LevelBaker.COLOR, at(x, z, 0.0, height), depth, rng.randf_range(1.6, 2.6), width + 0.8, ROOF_COLOR * 0.8, 0.5)
	var facing: float = -side
	var face_x: float = x + facing * (width * 0.5)
	var turn: float = facing * PI * 0.5
	for slot: int in 2:
		var offset: float = -depth * 0.25 + float(slot) * depth * 0.5
		for floor_index: int in 2:
			var roll: float = rng.randf()
			var sill_y: float = 1.5 + float(floor_index) * 2.2
			if roll < 0.45:
				window(baker, face_x, z + offset, facing, sill_y, WINDOW_GLOW * rng.randf_range(0.7, 1.0) * lit, 0)
			elif roll < 0.75:
				window(baker, face_x, z + offset, facing, sill_y, Color(0.02, 0.02, 0.04), 0)
			else:
				window(baker, face_x, z + offset, facing, sill_y, Color(0.02, 0.02, 0.04), 1 + rng.randi() % 2)
	var door_xf := at(face_x + facing * 0.04, z, turn, 0.9)
	if Quality.is_high():
		baker.add_box(LevelBaker.COLOR, at(face_x + facing * 0.06, z, turn, 0.95), Vector3(1.5, 1.9, 0.14), WOOD * 0.6)
	baker.add_panel(LevelBaker.COLOR, door_xf, Vector2(1.1, 1.8), WOOD)
	if rng.randf() < 0.7:
		sandbags(baker, face_x + facing * 0.7, z + 1.1, turn)


## Window in a wall that faces `facing` along x. The frame sticks out of the wall, the pane sits inside it and a sill underneath.
## Board mode 0 is open, 1 has two crossed planks, 2 has three horizontal planks.
static func window(baker: LevelBaker, wall_x: float, z: float, facing: float, sill_y: float, pane: Color, boards: int) -> void:
	var turn: float = facing * PI * 0.5
	var centre_y: float = sill_y + 0.55
	var frame: Color = WOOD * 0.55
	var out: float = facing * 0.06
	baker.add_box(LevelBaker.COLOR, at(wall_x + out, z, turn, centre_y), Vector3(1.2, 1.4, 0.14), frame)
	var pane_group: int = LevelBaker.GLOW if pane.r > 0.2 else LevelBaker.COLOR
	baker.add_panel(pane_group, at(wall_x + facing * 0.14, z, turn, centre_y), Vector2(0.9, 1.1), pane)
	baker.add_box(LevelBaker.COLOR, at(wall_x + facing * 0.15, z, turn, sill_y - 0.02), Vector3(1.5, 0.1, 0.3), frame * 1.2)
	if not Quality.is_high():
		return
	baker.add_box(LevelBaker.COLOR, at(wall_x + facing * 0.12, z, turn, centre_y), Vector3(1.0, 0.07, 0.1), frame)
	baker.add_box(LevelBaker.COLOR, at(wall_x + facing * 0.12, z, turn, centre_y), Vector3(0.07, 1.2, 0.1), frame)
	if boards == 1:
		for tilt: float in [0.6, -0.6]:
			var plank := Transform3D(Basis(Vector3.UP, turn) * Basis(Vector3.BACK, tilt), Vector3(wall_x + facing * 0.2, centre_y, z))
			baker.add_box(LevelBaker.COLOR, plank, Vector3(1.7, 0.18, 0.07), WOOD * 1.1)
	elif boards == 2:
		for step: int in 3:
			baker.add_box(LevelBaker.COLOR, at(wall_x + facing * 0.2, z, turn, centre_y - 0.4 + float(step) * 0.4), Vector3(1.4, 0.2, 0.07), WOOD * (1.0 + float(step) * 0.08))


## Bare spooky tree with a thin trunk and two dark crown cones. It leans a little so no two match.
static func tree(baker: LevelBaker, x: float, z: float, rng: RandomNumberGenerator, height: float = 4.0) -> void:
	var xf := at(x, z, rng.randf() * TAU)
	baker.add_column(LevelBaker.COLOR, xf, 0.28, 0.14, height, WOOD, 5)
	var crown := Transform3D(xf.basis, xf.origin + Vector3.UP * height * 0.55)
	baker.add_column(LevelBaker.COLOR, crown, 1.5, 0.0, height * 0.7, LEAF, 6)
	crown.origin += Vector3.UP * height * 0.4
	baker.add_column(LevelBaker.COLOR, crown, 1.0, 0.0, height * 0.55, LEAF * 1.15, 6)


## Picket fence along z. Each board is one panel that faces the road, because nobody sees the back.
## With a generator the fence is broken: boards are missing or lean over, as in a street nobody repairs.
static func fence(baker: LevelBaker, x: float, z_from: float, z_to: float, colour: Color = Color(0.4, 0.3, 0.22), rng: RandomNumberGenerator = null) -> void:
	var length: float = absf(z_to - z_from)
	var mid: float = (z_from + z_to) * 0.5
	var facing: float = PI * 0.5 if x < 0.0 else -PI * 0.5
	baker.add_panel(LevelBaker.COLOR, at(x, mid, facing, 0.55), Vector2(length, 0.12), colour * 0.8)
	var boards: int = int(length / 0.7)
	for index: int in boards:
		var board_z: float = minf(z_from, z_to) + 0.35 + float(index) * 0.7
		var lean := Basis.IDENTITY
		var height: float = 1.0
		if rng != null:
			if rng.randf() < 0.22:
				continue
			if rng.randf() < 0.2:
				lean = Basis(Vector3.BACK, rng.randf_range(-0.5, 0.5))
				height = rng.randf_range(0.5, 1.0)
		var xf := Transform3D(Basis(Vector3.UP, facing) * lean, Vector3(x, 0.5 * height, board_z))
		baker.add_panel(LevelBaker.COLOR, xf, Vector2(0.3, height), colour * (rng.randf_range(0.7, 1.0) if rng != null else 1.0))


const CARS: Array[String] = ["Vehicle_Pickup", "Vehicle_Sports", "Vehicle_Truck"]
## Pivot offset along z so the body, not the bumper, sits on the given spot. Measured from the glTF bounds.
const CAR_CENTRE_Z: Dictionary = {"Vehicle_Pickup": 0.1, "Vehicle_Sports": 0.11, "Vehicle_Truck": -0.43}


## Parked kit car. The model faces +z, so a yaw of PI points the nose down the road with the player.
static func car(baker: LevelBaker, x: float, z: float, yaw: float, colour: Color, model_index: int = 0) -> void:
	var model: String = CARS[model_index % CARS.size()]
	var xf := at(x, z, yaw + PI)
	xf.origin += xf.basis * Vector3(0.0, 0.0, -CAR_CENTRE_Z[model] * CAR_SCALES[model])
	xf.basis = xf.basis * Basis.from_scale(Vector3.ONE * CAR_SCALES[model])
	baker.add_model(model, xf, colour.lerp(Color.WHITE, 0.35))


static func tombstone(baker: LevelBaker, x: float, z: float, rng: RandomNumberGenerator) -> void:
	var yaw: float = rng.randf_range(-0.4, 0.4) + PI * 0.5
	var xf := at(x, z, yaw)
	var tall: float = rng.randf_range(0.9, 1.4)
	baker.add_box(LevelBaker.COLOR, Transform3D(xf.basis, xf.origin + Vector3.UP * tall * 0.5), Vector3(0.9, tall, 0.3), STONE)
	baker.add_box(LevelBaker.COLOR, Transform3D(xf.basis, xf.origin + Vector3.UP * (tall + 0.1)), Vector3(0.6, 0.25, 0.28), STONE * 1.1)


## Hanging bulb that gives a warm dot of light, used for stalls and the gate.
static func lantern(baker: LevelBaker, x: float, y: float, z: float, colour: Color = LAMP_GLOW) -> void:
	baker.add_sphere(LevelBaker.GLOW, Transform3D(Basis.IDENTITY, Vector3(x, y, z)), 0.2, colour, 3, 6)


static func barrel(baker: LevelBaker, x: float, z: float, colour: Color = Color(1.0, 1.0, 1.0)) -> void:
	baker.add_model("Barrel", at(x, z), colour)


static func hydrant(baker: LevelBaker, x: float, z: float) -> void:
	baker.add_model("FireHydrant", at(x, z))


static func cone(baker: LevelBaker, x: float, z: float) -> void:
	baker.add_model("TrafficCone_1", at(x, z))


## Stacked sandbag mound from squashed low-poly spheres. It costs about 40 triangles, so it works on every tier where a 1000 triangle trash bag does not.
static func sandbags(baker: LevelBaker, x: float, z: float, yaw: float = 0.0) -> void:
	var burlap := Color(0.36, 0.31, 0.22)
	for index: int in 3:
		var along: float = (float(index) - 1.0) * 0.5
		var base := Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(0.62, 0.3, 0.38)), Vector3(x, 0.15, z) + Basis(Vector3.UP, yaw) * Vector3(along, 0.0, 0.0))
		baker.add_sphere(LevelBaker.COLOR, base, 0.5, burlap * (0.9 + 0.1 * float(index)), 3, 6)
	var top := Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(0.62, 0.3, 0.38)), Vector3(x, 0.42, z))
	baker.add_sphere(LevelBaker.COLOR, top, 0.5, burlap, 3, 6)


static func bag(baker: LevelBaker, x: float, z: float) -> void:
	baker.add_model("TrashBag_1", at(x, z))


## The model's pole is sunk 0.58 m below its origin, so it is lifted to stand on the ground.
static func torch(baker: LevelBaker, x: float, z: float, glow: float) -> void:
	baker.add_model("WoodenTorch_Fire", at(x, z, 0.0, 0.58), Color.WHITE, Color(1.0, 0.55, 0.15) * glow)


## The pole sits at the origin and the arm reaches along +x, so yaw 0 points the arm toward a road on the +x side.
static func traffic_light(baker: LevelBaker, x: float, z: float, yaw: float, glow: float) -> void:
	baker.add_model("TrafficLight_1", at(x, z, yaw), Color.WHITE, Color(1.0, 0.3, 0.2) * glow)


## Models above this many triangles are skipped on the low tier, which has no room for them.
const LOW_TIER_MAX_TRIANGLES: int = 300
## The high tier also skips the very heavy models (chest, couch, big trash bag, tire stack), which cost more than the street around them.
const HIGH_TIER_MAX_TRIANGLES: int = 1100
const RUST: Color = Color(0.55, 0.32, 0.2)
const SOOT: Color = Color(0.26, 0.24, 0.25)
const DIRT: Color = Color(0.6, 0.55, 0.48)
const BLOOD: Color = Color(0.5, 0.12, 0.1)
const FIRE_GLOW: Color = Color(1.0, 0.5, 0.14)
## Hero is 1.68 m in the model and drawn at RailsHero.MODEL_SCALE, so a 1.8 m person reads as 1.8 * 1.26 = 2.27 m. Cars follow the same ratio.
## Scale per model gives a 2.27 m wide body, which fits a 2.4 m lane, and a car length of about 4.8 to 5.5 m.
const CAR_SCALES: Dictionary[String, float] = {"Vehicle_Pickup": 1.0, "Vehicle_Sports": 0.85, "Vehicle_Truck": 0.9}
const WRECK_TINTS: Array[Color] = [Color(0.2, 0.18, 0.18), Color(0.5, 0.3, 0.2), Color(0.33, 0.38, 0.42), Color(0.42, 0.4, 0.3)]


## Places any model with a uniform scale. `lift` is in model units, for models whose origin sits above or below their base.
## Returns false when the low tier skipped it, so a caller can place a cheaper stand-in. `force` keeps landmarks on every tier.
static func prop(baker: LevelBaker, model: String, x: float, z: float, yaw: float = 0.0, scale: float = 1.0, tint: Color = Color.WHITE, lift: float = 0.0, glow: Color = Color(0.0, 0.0, 0.0, 0.0), force: bool = false) -> bool:
	var limit: int = HIGH_TIER_MAX_TRIANGLES if Quality.is_high() else LOW_TIER_MAX_TRIANGLES
	if not force and LevelBaker.model_triangles(model) > limit:
		return false
	var xf := Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3.ONE * scale), Vector3(x, lift * scale, z))
	baker.add_model(model, xf, tint, glow)
	return true


## Burnt-out car that leans toward the curb. The tint hides the cheerful paint of the kit.
static func wreck(baker: LevelBaker, x: float, z: float, yaw: float, rng: RandomNumberGenerator, tipped: bool = false) -> void:
	var model: String = CARS[rng.randi() % CARS.size()]
	var tint: Color = WRECK_TINTS[rng.randi() % WRECK_TINTS.size()]
	var xf := at(x, z, yaw + PI)
	xf.origin += xf.basis * Vector3(0.0, 0.0, -CAR_CENTRE_Z[model] * CAR_SCALES[model])
	xf.basis = xf.basis * Basis.from_scale(Vector3.ONE * CAR_SCALES[model])
	if tipped:
		# Rolling about the car's long axis puts the roof on one side, so the lift keeps the new low side on the ground.
		xf = xf * Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(1.2, 1.2, 0.0))
	if Quality.is_high():
		baker.add_model(model, xf, tint)
		prop(baker, "Wheel", x + 1.7, z + 2.4, rng.randf() * TAU, 1.0, SOOT)
		decal(baker, x, z + 3.4, rng, SOOT)


## Flat stain on the ground. The model is a thin slab, so it is lifted above the ground slab to avoid z fighting.
static func decal(baker: LevelBaker, x: float, z: float, rng: RandomNumberGenerator, tint: Color = BLOOD) -> void:
	var model: String = "Blood_%d" % (1 + rng.randi() % 3)
	prop(baker, model, x, z, rng.randf() * TAU, rng.randf_range(0.5, 0.9), tint, 0.06 / 0.7)


## One piece of street rubbish picked by the generator. Heavy pieces drop out on the low tier and leave a gap.
static func debris(baker: LevelBaker, rng: RandomNumberGenerator, x: float, z: float) -> void:
	var yaw: float = rng.randf() * TAU
	match rng.randi() % 15:
		0:
			prop(baker, "Pallet", x, z, yaw, 1.0, DIRT * 0.8)
		1:
			prop(baker, "Pallet_Broken", x, z, yaw, 1.0, DIRT * 0.7)
			prop(baker, "Pallet", x + 0.3, z - 1.0, yaw + 1.0, 1.0, DIRT * 0.6)
		2:
			prop(baker, "TrashBag_1", x, z, yaw, 1.0, SOOT * 1.6)
			prop(baker, "TrashBag_1", x + 0.5, z - 0.4, yaw + 1.0, 0.9, SOOT * 1.3)
		3:
			prop(baker, "TrashBag_2", x, z, yaw, 1.0, DIRT * 0.5)
		4:
			prop(baker, "Wheels_Stack", x, z, yaw, 1.0, SOOT)
		5:
			prop(baker, "Wheel", x, z, yaw, 1.0, SOOT)
			prop(baker, "Wheel", x + 0.9, z + 0.4, yaw + 2.0, 1.0, SOOT * 1.2)
		6:
			prop(baker, "CinderBlock", x, z, yaw, 1.3, DIRT * 0.7)
			prop(baker, "CinderBlock", x + 0.6, z + 0.2, yaw + 0.7, 1.3, DIRT * 0.6)
			prop(baker, "CinderBlock", x + 0.3, z + 0.1, yaw + 1.7, 1.3, DIRT * 0.65, 0.23)
		7:
			prop(baker, "Barrel", x, z, yaw, 1.0, RUST * 1.2)
			prop(baker, "Barrel", x + 0.9, z - 0.3, yaw, 1.0, SOOT * 1.8)
		8:
			prop(baker, "Can_Broken", x, z, yaw, 1.0, Color.WHITE * 0.8)
			prop(baker, "Can_Open", x + 0.5, z + 0.3, yaw, 1.0, Color.WHITE * 0.7)
			decal(baker, x, z - 0.8, rng)
		9:
			prop(baker, "Trashcan", x, z, yaw, 0.17, SOOT * 1.8)
			prop(baker, "TrashBag_1", x + 0.8, z + 0.2, yaw, 1.0, SOOT * 1.5)
		10:
			prop(baker, "TrafficBarrier_2", x, z, yaw * 0.15 + PI * 0.5, 1.0, DIRT * 0.8)
		11:
			decal(baker, x, z, rng)
		12:
			prop(baker, "PropaneTank", x, z, yaw, 0.4, RUST, 1.36)
			prop(baker, "GasCan", x + 0.8, z, yaw, 0.3, RUST * 1.3)
		13:
			if not prop(baker, "Couch", x, z, yaw * 0.2 + PI * 0.5, 1.0, Color(0.45, 0.4, 0.35)):
				prop(baker, "CinderBlock", x, z, yaw, 1.3, DIRT * 0.7)
		14:
			if not prop(baker, "Chest", x, z, yaw, 1.4, WOOD * 2.0):
				prop(baker, "Pallet", x, z, yaw, 1.0, DIRT * 0.8)


## Fills a strip beside the road with debris. The low tier gets a fraction of the pieces pieces, since each piece also costs triangles there.
static func clutter_strip(baker: LevelBaker, rng: RandomNumberGenerator, side: float, z_from: float, z_to: float, spacing: float, x_near: float = 5.3, x_far: float = 7.6) -> void:
	var step: float = spacing * 2.6 if Quality.is_high() else spacing * 14.0
	var z: float = z_from
	while z > z_to:
		debris(baker, rng, side * rng.randf_range(x_near, x_far), z + rng.randf_range(-0.6, 0.6))
		z -= step * rng.randf_range(0.8, 1.2)


## Camp with a fire. The fire glows warm and throws a pool of light on the ground, like the lamps do.
## The kit's tent and raft are building-sized in model units, so they are scaled down to fit a person.
static func camp(baker: LevelBaker, x: float, z: float, away_from_road: float, glow: float, big: bool = true) -> void:
	var fire: Color = FIRE_GLOW * glow
	baker.add_disc(LevelBaker.POOL, at(x, z, 0.0, 0.07), 4.6, POOL_GLOW * glow * 1.5 + Color(0.0, 0.0, 0.0, 1.0))
	prop(baker, "Bonfire", x, z, 0.0, 0.7, Color.WHITE * 0.9, 0.03)
	prop(baker, "Bonfire_Fire", x, z, 0.0, 0.7, Color.WHITE, 0.0, fire)
	for index: int in 3:
		var angle: float = float(index) * TAU / 3.0 + 0.4
		prop(baker, "WoodLog", x + cos(angle) * 1.7, z + sin(angle) * 1.7, -angle + PI * 0.5, 0.5, Color.WHITE * 0.9)
	prop(baker, "Pot", x + 0.9, z - 0.5, 0.0, 0.3, Color.WHITE * 0.8)
	if big:
		prop(baker, "Tent", x + away_from_road * 3.4, z + 0.5, PI * 0.5, 0.15, Color(0.8, 0.75, 0.7), 0.18)
		prop(baker, "Backpack", x + 1.2, z + 1.9, 2.0, 0.28, Color.WHITE, 1.46)
		prop(baker, "Radio", x - 1.2, z - 1.6, 0.5, 0.35, Color.WHITE * 0.8)
		prop(baker, "GasCan", x + 2.3, z - 0.4, 1.0, 0.3, RUST)
		prop(baker, "Pan", x + 0.4, z + 1.0, 0.8, 0.35, Color.WHITE * 0.8, 0.27)


## Roadblock beside the lanes made of kit barriers, sandbag-like cinder blocks and pallets.
static func barricade(baker: LevelBaker, x: float, z: float, yaw: float, rng: RandomNumberGenerator) -> void:
	var high: bool = Quality.is_high()
	if high:
		prop(baker, "TrafficBarrier_1", x, z, yaw, 1.0, DIRT * 0.75)
		prop(baker, "PlasticBarrier", x - 0.3, z + 1.3, yaw - 0.2, 1.3, DIRT * 0.8)
	prop(baker, "TrafficBarrier_2", x + 0.2, z - 1.5, yaw + 0.15, 1.0, RUST * 1.1)
	prop(baker, "Pallet_Broken", x + 0.9, z + 0.4, rng.randf() * TAU, 1.0, DIRT * 0.7)
	for index: int in (3 if high else 0):
		prop(baker, "CinderBlock", x + 1.1 + float(index % 2) * 0.5, z - 0.8 + float(index) * 0.45, yaw + float(index), 1.3, DIRT * 0.6)
