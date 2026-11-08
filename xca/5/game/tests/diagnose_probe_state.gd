extends SceneTree
## Prints the round manager phase, throws left and loose sandals every second of simulated time.
## Run: godot --headless --path game --fixed-fps 60 --script res://tests/diagnose_probe_state.gd

var manager: RoundManager
var arena: Arena
var frames: int = 0


func _initialize() -> void:
	var tuning: Tuning = Tuning.load_default().duplicate() as Tuning
	tuning.match_countdown = false
	tuning.human_team = 0
	arena = (load("res://scenes/arena.tscn") as PackedScene).instantiate() as Arena
	arena.tuning = tuning
	root.add_child(arena)
	manager = RoundManager.new()
	manager.tuning = tuning
	manager.arena = arena
	root.add_child(manager)


func _physics_process(_delta: float) -> bool:
	frames += 1
	if frames % 60 == 0:
		var human: Character = manager.human.character if manager.human != null else null
		print("t=%2ds phase=%d throws_left=%d attacking=%d human=%s" % [frames / 60, manager.phase, manager.throws_left, manager.attacking_team, "none" if human == null else "role=%d carried=%s" % [human.role, str(human.carried != null)]])
	if frames > 60 * 14:
		quit(0)
	return false
