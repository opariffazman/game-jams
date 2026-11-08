class_name AudioRef
extends RefCounted
## Reads the [code]Audio[/code] autoload by node path, so scripts compile in a test run and a scene run alike.
##
## A script run through [code]--script[/code] compiles before autoloads register, so naming the autoload fails there.
## Every call does nothing when the autoload is missing.

const NODE_PATH: String = "/root/Audio"


## The autoload node, or null.
static func node() -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null(NODE_PATH)


## Starts the music phase [param names]. See [method Audio.play_music]. Does nothing when the autoload is missing.
static func play_music(names: Array[String]) -> void:
	var audio: Node = node()
	if audio != null:
		audio.call("play_music", names)


## Plays [param slot]. Returns the length in seconds of the sound started, or 0.0 when nothing played.
static func play(slot: StringName, volume_offset_db: float = 0.0, pitch_override: float = 0.0) -> float:
	var audio: Node = node()
	if audio == null:
		return 0.0
	return float(audio.call("play", slot, volume_offset_db, pitch_override))
