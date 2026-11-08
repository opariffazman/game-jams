extends SceneTree
## Regression test for bug 1 on the real human path: a human attacker at full drag power aims at the stack.
## Stack.is_down is the ground truth. DIAGNOSE_DEFENDERS=0 removes the orbiting defenders to isolate the throw.
##
## Builds the real RoundManager and HumanController with scheme A or D. The human attacks. The probe
## pushes real InputEventScreenTouch and InputEventScreenDrag events at the aim stick or fire button,
## as a phone does, then reads Stack.is_down. The bots on the human's team stay idle so only the human's
## throw can topple. The defenders orbit as in the game. Writes nothing to the game.
## Run: DIAGNOSE_SCHEME=A godot --headless --path game --fixed-fps 60 --script res://tests/human_topple_test.gd
## DIAGNOSE_VIEW=iso turns the tilted projection on, so the drag bearing is the screen direction of the ground bearing.
## Set DIAGNOSE_ERRORS=0,4,8 for the angular errors in degrees and DIAGNOSE_TRIALS for trials per error.

const ARENA_SCENE: String = "res://scenes/arena.tscn"
const FLIGHT_FRAMES: int = 150

var scheme_name: String = "A"
var errors: Array[float] = [0.0]
var trials: int = 10
var manager: RoundManager
var arena: Arena
var tuning: Tuning
var stage: Node2D
var _frames_left: int = 0


func _initialize() -> void:
	var env_scheme: String = OS.get_environment("DIAGNOSE_SCHEME")
	if env_scheme != "":
		scheme_name = env_scheme
	var env_errors: String = OS.get_environment("DIAGNOSE_ERRORS")
	if env_errors != "":
		errors.clear()
		for part: String in env_errors.split(","):
			errors.append(float(part))
	var env_trials: String = OS.get_environment("DIAGNOSE_TRIALS")
	if env_trials != "":
		trials = int(env_trials)
	ViewProjection.active = OS.get_environment("DIAGNOSE_VIEW") == "iso"
	_run()


func _frames(count: int) -> void:
	for _i: int in count:
		await physics_frame


func _build(seed_value: int) -> bool:
	if stage != null:
		root.remove_child(stage)
		stage.free()
	seed(seed_value)
	stage = Node2D.new()
	root.add_child(stage)
	tuning = Tuning.load_default().duplicate() as Tuning
	tuning.match_countdown = false
	tuning.human_team = 0
	arena = (load(ARENA_SCENE) as PackedScene).instantiate() as Arena
	arena.tuning = tuning
	stage.add_child(arena)
	manager = RoundManager.new()
	manager.tuning = tuning
	manager.arena = arena
	stage.add_child(manager)
	return true


func _human_attacks() -> bool:
	return manager.attacking_team == tuning.human_team


func _touch(position: Vector2, pressed: bool, index: int = 7) -> void:
	var event: InputEventScreenTouch = InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = pressed
	root.push_input(event, true)


func _drag(position: Vector2, index: int = 7) -> void:
	var event: InputEventScreenDrag = InputEventScreenDrag.new()
	event.index = index
	event.position = position
	root.push_input(event, true)


func _run() -> void:
	await physics_frame
	SettingsRef.set_scheme(SettingsRef.SCHEME_AIM_STICK if scheme_name == "A" else SettingsRef.SCHEME_LOCK_FIRE)
	print("scheme %s, %s view, %d trials per error, defenders orbit, only the human throws" % [scheme_name, "iso" if ViewProjection.active else "flat", trials])
	for error_degrees: float in errors:
		var toppled: int = 0
		var thrown: int = 0
		var sample: String = ""
		var seed_value: int = 100
		var done: int = 0
		while done < trials and seed_value < 100 + trials * 6:
			seed_value += 1
			_build(seed_value)
			await _frames(3)
			if not _human_attacks():
				continue
			# Wait for the topple phase and the sandal in the human's hands.
			var wait: int = 0
			while (manager.phase != RoundManager.TOPPLE or manager.human.character == null or manager.human.character.carried == null) and wait < 400:
				await physics_frame
				wait += 1
			var body: Character = manager.human.character
			if body == null or body.carried == null or manager.phase != RoundManager.TOPPLE:
				continue
			# Silence the two bot attackers so only the human can topple.
			for entry: Variant in arena.get_characters(0):
				var other: Character = entry as Character
				if other != body:
					var bot: BotController = manager._bots.get(other) as BotController
					if bot != null:
						bot.detach()
			# The queue starts with attacker 0. Make sure it is the human, otherwise skip this seed.
			if arena.get_characters(0)[0] != body:
				continue
			if OS.get_environment("DIAGNOSE_DEFENDERS") == "0":
				for entry: Variant in arena.get_characters(1):
					(entry as Character).global_position = arena.centre_spot + Vector2(2000.0, 0.0)
			done += 1
			var origin: Vector2 = body.global_position
			var to_stack: Vector2 = (arena.centre_spot - origin).normalized()
			var bearing: Vector2 = ViewProjection.world_dir_to_screen(to_stack.rotated(deg_to_rad(error_degrees)))
			if scheme_name == "A":
				var stick: AimStick = manager.human.scheme.stick
				var centre: Vector2 = stick.hit_centre()
				_touch(centre, true)
				await physics_frame
				for step: int in range(1, 9):
					_drag(centre + bearing * stick.hit_radius() * float(step) / 8.0)
					await physics_frame
				await _frames(3)
				_touch(centre + bearing * stick.hit_radius(), false)
			else:
				var fire: Variant = manager.human.scheme.get("fire_button")
				var fire_centre: Vector2 = fire.hit_centre() if fire != null else Vector2.ZERO
				_touch(fire_centre, true)
				await _frames(4)
				_touch(fire_centre, false)
			await physics_frame
			var launched: bool = body.carried == null
			if launched:
				thrown += 1
			await _frames(FLIGHT_FRAMES)
			var down: bool = arena.stack.is_down
			if down:
				toppled += 1
			if sample.length() < 400:
				sample += "[seed %d launched=%s down=%s] " % [seed_value, str(launched), str(down)]
		print("aim error %+5.1f deg: launched %d of %d, toppled %d of %d  %s" % [error_degrees, thrown, done, toppled, done, sample])
	quit(0)
