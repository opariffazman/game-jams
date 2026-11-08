extends SceneTree
## Prints, every 2 simulated seconds of a scatter phase, who holds the pass sandal and where it is.
## The human is a scripted attacker that throws once and then idles. Run:
## godot --headless --path game --fixed-fps 60 --script res://tests/diagnose_scatter_trace.gd

var manager: RoundManager
var arena: Arena
var frames: int = 0
var scatter_frames: int = 0
var thrown: bool = false


func _initialize() -> void:
	seed(int(OS.get_environment("DIAGNOSE_SEED")) if OS.get_environment("DIAGNOSE_SEED") != "" else 20261107)
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
	print("human team 0, attacking team at start: ", manager.attacking_team)


func _physics_process(_delta: float) -> bool:
	frames += 1
	var human: Character = manager.human.character if manager.human != null else null
	if human != null and human.alive and manager.phase == RoundManager.TOPPLE and human.role == Character.Role.ATTACKER and human.carried != null and not thrown:
		human.throw_sandal((arena.centre_spot - human.global_position).normalized(), 1.0)
		thrown = true
	if manager.phase == RoundManager.SCATTER:
		scatter_frames += 1
		if scatter_frames % 240 == 1:
			_report()
	if scatter_frames > 60 * 70 or frames > 60 * 120:
		quit(0)
	return false


func _report() -> void:
	var pass_sandal: Sandal = null
	for node: Node in get_nodes_in_group(Sandal.GROUP):
		var sandal: Sandal = node as Sandal
		if sandal != null and sandal.is_pass_sandal:
			pass_sandal = sandal
	var line: String = "scatter t=%2ds attacking=%d" % [scatter_frames / 60, manager.attacking_team]
	if pass_sandal == null:
		print(line, " NO PASS SANDAL")
		return
	var holder: String = "nobody"
	for team: int in 2:
		for entry: Variant in arena.get_characters(team):
			var character: Character = entry as Character
			if character != null and character.carried == pass_sandal:
				holder = "team%d %s alive=%s" % [team, "ATT" if character.role == Character.Role.ATTACKER else "DEF", str(character.alive)]
	print("%s pass_sandal holder=%s pos=(%.0f,%.0f) speed=%.0f flight=%s frozen=%s loose=%s" % [line, holder, pass_sandal.global_position.x, pass_sandal.global_position.y, pass_sandal.linear_velocity.length(), str(pass_sandal.in_flight), str(pass_sandal.freeze), str(arena.get_loose_sandals().has(pass_sandal))])
	var alive: Array[String] = []
	for team: int in 2:
		for entry: Variant in arena.get_characters(team):
			var c: Character = entry as Character
			if c != null:
				alive.append("t%d%s%s@(%.0f,%.0f)" % [team, "A" if c.role == Character.Role.ATTACKER else "D", "" if c.alive else "x", c.global_position.x, c.global_position.y])
	print("    chars: ", " ".join(alive))
