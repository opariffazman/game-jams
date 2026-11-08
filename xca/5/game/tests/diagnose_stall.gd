extends SceneTree
## Diagnosis probe for bug 2: scatter phases where the defenders lose the pass sandal and stall.
##
## Plays full 3v3 matches with the real round manager. The human seat is a scripted attacker that
## either idles or rebuilds. A stall is a scatter phase older than STALL_SECONDS in which no defender
## carries the pass sandal and none is in flight. At the first stall frame the probe logs where the
## pass sandal is. Run: godot --headless --path game --fixed-fps 60 --script res://tests/diagnose_stall.gd
## Set DIAGNOSE_MODE=idle or rebuild, and DIAGNOSE_SCATTERS for the number of scatter phases.

const ARENA_SCENE: String = "res://scenes/arena.tscn"
const STALL_SECONDS: float = 20.0
const MAX_SCATTER_SECONDS: float = 60.0

var mode: String = "idle"
var target_scatters: int = 25
var scatters: int = 0
var stalls: int = 0
var scatter_age: float = 0.0
var stall_logged: bool = false
var stall_reports: Array[String] = []
var rounds_by_end: Dictionary = {"rebuilt": 0, "all_mati": 0, "timeout": 0}
var manager: RoundManager
var arena: Arena
var tuning: Tuning
var _last_phase: int = -1
var _scatter_started_frame: int = 0
var frame: int = 0


func _initialize() -> void:
	var env_mode: String = OS.get_environment("DIAGNOSE_MODE")
	if env_mode != "":
		mode = env_mode
	var env_count: String = OS.get_environment("DIAGNOSE_SCATTERS")
	if env_count != "":
		target_scatters = int(env_count)
	Engine.time_scale = 4.0
	Engine.physics_ticks_per_second = 60
	Engine.max_physics_steps_per_frame = 16
	seed(int(OS.get_environment("DIAGNOSE_SEED")) if OS.get_environment("DIAGNOSE_SEED") != "" else 20261107)
	tuning = Tuning.load_default().duplicate() as Tuning
	tuning.match_countdown = false
	tuning.human_team = 0
	# DIAGNOSE_HUMAN_ROLE=attacker lets the human's seat decide the round. defender makes the bots attack, so scatter always happens.
	arena = (load(ARENA_SCENE) as PackedScene).instantiate() as Arena
	arena.tuning = tuning
	root.add_child(arena)
	manager = RoundManager.new()
	manager.tuning = tuning
	manager.arena = arena
	root.add_child(manager)
	var driver: Node = (load("res://tests/diagnose_stall_driver.gd") as GDScript).new() as Node
	driver.set("owner_probe", self)
	root.add_child(driver)
	print("driver attached: ", driver.get_script() != null, " owner_probe set: ", driver.get("owner_probe") != null)


func finish() -> void:
	print("DONE mode=%s scatter_phases=%d stalls=%d ends=%s" % [mode, scatters, stalls, str(rounds_by_end)])
	for line: String in stall_reports:
		print(line)
	Engine.time_scale = 1.0
	quit(0)
