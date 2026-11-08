extends SceneTree
## Headless test of the audio autoload, the sound setting and the particle layer.
##
## Run: godot --headless --path game --script res://tests/audio_test.gd

var _failures: int = 0
var _audio: Node
var _settings: Node


func _initialize() -> void:
	await _run()
	print("audio_test: %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(_failures)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   ", label)
	else:
		print("  FAIL ", label)
		_failures += 1


func _frames(count: int) -> void:
	for _i: int in count:
		await process_frame


func _run() -> void:
	await process_frame
	_audio = root.get_node_or_null("Audio")
	_settings = root.get_node_or_null("Settings")
	_check(_audio != null and _settings != null, "autoloads Audio and Settings exist")
	if _audio == null or _settings == null:
		return
	_settings.path = "user://audio_test_settings.cfg"
	_settings.sound_enabled = true
	_test_files()
	_test_buses()
	await _test_play()
	await _test_voice()
	await _test_music()
	_test_mute_persists()
	await _test_fx()
	await _test_no_orphans()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://audio_test_settings.cfg"))


func _test_files() -> void:
	for path: String in AudioSet.asset_paths():
		_check(ResourceLoader.exists(path) and load(path) is AudioStream, "sound file loads: %s" % path)
	for path: String in AudioSet.music_paths():
		_check(ResourceLoader.exists(path) and load(path) is AudioStream, "music file loads: %s" % path)
	_check(_audio.missing_files.is_empty(), "no slot reports a missing file")
	for slot_name: StringName in AudioSet.slots():
		_check(not (AudioSet.slots()[slot_name]["files"] as Array).is_empty(), "slot has files: %s" % slot_name)
	for path: String in FxLayer.KINDS.values().map(func(recipe: Dictionary) -> String: return FxLayer.DIR + recipe["texture"] + ".png"):
		_check(ResourceLoader.exists(path), "particle texture loads: %s" % path)


func _test_buses() -> void:
	for bus: StringName in [&"Sfx", &"Ui", &"Voice", &"Music"]:
		_check(AudioServer.get_bus_index(bus) >= 0, "bus exists: %s" % bus)


func _test_play() -> void:
	var length: float = _audio.play(&"throw")
	_check(length > 0.0, "a slot plays and returns its length")
	_check(_audio.play(&"no_such_slot") == 0.0, "an unknown slot plays nothing")
	for _i: int in 30:
		_audio.play(&"hit_block")
	var players: int = 0
	for pool: Node in _audio.get_node("Pools").get_children():
		players += 1
	_check(players <= 120, "pools stay small after a burst of 30 plays (%d players)" % players)
	var before: int = _audio.get_node("Pools").get_child_count()
	for _i: int in 30:
		_audio.play(&"hit_block")
	_check(_audio.get_node("Pools").get_child_count() == before, "a repeated burst creates no new players")
	_check(AudioRef.play(&"ui_tap") > 0.0, "AudioRef reaches the autoload")


func _test_voice() -> void:
	_audio.call("_halt", _audio.get_node("Pools/Voice"))
	_audio.set("_voice_priority", 0)
	_check(_audio.play(&"voice_round_1") > 0.0, "a voice line plays")
	_check(_audio.play(&"voice_final_round") == 0.0, "an equal voice line does not cut the first")
	_check(_audio.play(&"voice_you_win") > 0.0, "a higher voice line takes over")
	_audio.call("_halt", _audio.get_node("Pools/Voice"))
	_audio.set("_voice_priority", 0)
	var first: float = _audio.play(&"voice_hype")
	_audio.call("_halt", _audio.get_node("Pools/Voice"))
	_audio.set("_voice_priority", 0)
	_check(first > 0.0 and _audio.play(&"voice_hype") == 0.0, "hype lines are rate limited")
	_audio.call("_halt", _audio.get_node("Pools/Voice"))


func _test_music() -> void:
	_audio.play_music(AudioSet.MUSIC_TOPPLE)
	await _frames(5)
	_check(_audio.music_active(), "a music phase starts when the files exist")
	_audio.play_music([] as Array[String])
	await create_timer(AudioServerFadeSeconds()).timeout
	await _frames(3)
	_check(not _audio.music_active(), "an empty phase fades the music out")
	_audio.play_music(["no_such_loop"] as Array[String])
	await _frames(3)
	_check(not _audio.music_active(), "a missing loop stays silent")
	_audio.play_music([] as Array[String])


func AudioServerFadeSeconds() -> float:
	return 1.8


func _test_mute_persists() -> void:
	_settings.set_sound(false)
	_check(AudioServer.is_bus_mute(AudioServer.get_bus_index(&"Master")), "sound off mutes the Master bus")
	_check(_audio.play(&"throw") == 0.0, "sound off plays nothing")
	var file: ConfigFile = ConfigFile.new()
	_check(file.load("user://audio_test_settings.cfg") == OK and file.get_value("controls", "sound", true) == false, "sound off is saved")
	_settings.sound_enabled = true
	_settings.load_settings()
	_check(_settings.sound_enabled == false, "sound off loads back from the file")
	_settings.set_sound(true)
	_check(not AudioServer.is_bus_mute(AudioServer.get_bus_index(&"Master")), "sound on unmutes the Master bus")
	_check(_audio.play(&"throw") > 0.0, "sound on plays again")


func _test_fx() -> void:
	var layer: FxLayer = FxLayer.new()
	root.add_child(layer)
	for _i: int in 100:
		layer.burst(&"hit", Vector2(100.0, 100.0))
	_check(layer.live_count() <= FxLayer.MAX_LIVE, "live emitters stay under the cap (%d)" % layer.live_count())
	_check(layer.get_child_count() <= FxLayer.MAX_LIVE, "pool never grows past the cap (%d)" % layer.get_child_count())
	layer.burst(&"no_such_kind", Vector2.ZERO)
	_check(FxRef.node() == layer, "FxRef finds the layer by group")
	await create_timer(1.5).timeout
	_check(layer.live_count() == 0, "bursts end on their own")
	root.remove_child(layer)
	layer.free()


func _test_no_orphans() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _frames(20)
	_check(FxRef.node() != null, "the match scene holds a particle layer")
	root.remove_child(main)
	main.free()
	await _frames(5)
	var orphans: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_check(orphans <= 3, "no orphan nodes after unloading the match (%d)" % orphans)
