extends SceneTree
## Tests whether GameFeel.hit_stop (Engine.time_scale = 0 for a moment) turns a flying sandal into NaN.
## Run: godot --headless --path game --fixed-fps 60 --script res://tests/diagnose_hitstop.gd

func _initialize() -> void:
	_run()


func _run() -> void:
	var tuning: Tuning = Tuning.load_default().duplicate() as Tuning
	tuning.match_countdown = false
	var bad: int = 0
	var trials: int = 30
	for trial: int in trials:
		var stage: Node2D = Node2D.new()
		root.add_child(stage)
		var arena: Arena = (load("res://scenes/arena.tscn") as PackedScene).instantiate() as Arena
		arena.tuning = tuning
		stage.add_child(arena)
		await physics_frame
		await physics_frame
		var sandal: Sandal = Sandal.new()
		sandal.tuning = tuning
		sandal.is_pass_sandal = true
		sandal.position = arena.centre_spot + Vector2(-240.0, float(trial % 7) * 4.0 - 12.0)
		arena.add_child(sandal)
		await physics_frame
		sandal.launch(Vector2.RIGHT, 1.0)
		var stop_frame: int = 4 + trial % 9
		var nan_frame: int = -1
		for frame: int in 70:
			if frame == stop_frame:
				get_root().get_node("GameFeel").call("hit_stop", 0.06)
			await physics_frame
			if is_nan(sandal.global_position.x) or is_nan(sandal.linear_velocity.x):
				nan_frame = frame
				break
		if nan_frame >= 0:
			bad += 1
		Engine.time_scale = 1.0
		root.remove_child(stage)
		stage.free()
	print("hit_stop NaN in %d of %d trials (time_scale is %.1f)" % [bad, trials, Engine.time_scale])
	quit(0)
