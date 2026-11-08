class_name AnimUtil
extends RefCounted
## Shared helpers for the character animation state machines.

## Blend time in seconds between two clips.
const BLEND_SECONDS: float = 0.15
## Clip name prefixes that loop. Every other clip plays once.
const LOOPING_PREFIXES: Array[String] = ["Walk", "Run", "Idle", "Crawl"]


## Returns the first AnimationPlayer under a model, or null.
static func find_player(model: Node) -> AnimationPlayer:
	var found: Array[Node] = model.find_children("*", "AnimationPlayer")
	return found[0] if not found.is_empty() else null


## Sets loop mode on every clip: looping for movement and idle clips, one-shot for the rest.
static func configure_loops(player: AnimationPlayer) -> void:
	for clip_name: StringName in player.get_animation_list():
		var animation: Animation = player.get_animation(clip_name)
		var loops: bool = false
		for prefix: String in LOOPING_PREFIXES:
			if String(clip_name).begins_with(prefix):
				loops = true
		# Run_Slash and Run_Stab are one-shot swings that start with "Run".
		if String(clip_name).begins_with("Run_S"):
			loops = false
		animation.loop_mode = Animation.LOOP_LINEAR if loops else Animation.LOOP_NONE


## Plays a clip with a blend. Skips a clip that already plays unless restart is set.
## Randomises the start time of looping clips so a crowd does not move in lockstep.
static func play(player: AnimationPlayer, clip: StringName, restart: bool = false) -> void:
	if player == null or not player.has_animation(clip):
		return
	if not restart and player.current_animation == clip and player.is_playing():
		return
	player.play(clip, BLEND_SECONDS)
	if player.get_animation(clip).loop_mode == Animation.LOOP_LINEAR:
		player.seek(randf() * player.current_animation_length, true)
