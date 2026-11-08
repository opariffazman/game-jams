class_name AudioBus
extends Node
## Plays every sound of the game by name, through the Sfx and Music buses.
##
## Web audio stays locked until the first tap, so nothing plays before unlock() runs. A missing file warns once and is skipped.
## Godot web builds default to sample playback, so pitch_scale is checked on the page by the readout counters, not by ear (unconfirmed).

## Folder that holds the audio files.
const AUDIO_DIR: String = "res://assets/audio/"
const SFX_BUS: StringName = &"Sfx"
const MUSIC_BUS: StringName = &"Music"
## Sound names with their file stems. A name maps to one file, or to several for a random pick.
const SOUNDS: Dictionary[StringName, Array] = {
	&"shot": ["sfx_shot_pistol"], &"shot_pistol": ["sfx_shot_pistol"], &"shot_shotgun": ["sfx_shot_shotgun"],
	&"shot_smg": ["sfx_shot_smg"], &"bat_swing": ["sfx_bat_swing"], &"bat_hit": ["sfx_bat_hit"],
	&"hit": ["sfx_hit"], &"zombie_hurt": ["sfx_zombie_hurt"], &"poof": ["sfx_poof"],
	&"heart_lost": ["sfx_hurt"], &"wave_clear": ["sfx_wave_clear"], &"wave_start": ["sfx_wave_start"],
	&"groan": ["sfx_groan_1", "sfx_groan_2", "sfx_groan_3"], &"ui_click": ["sfx_ui_click"],
	&"hand_found": ["sfx_hand_found"], &"hand_lost": ["sfx_hand_lost"],
	&"hurt": ["sfx_hurt"], &"run_over": ["sfx_run_over"], &"camp_reached": ["sfx_camp_reached"],
	&"lane_change": ["sfx_lane_change"], &"flick": ["sfx_flick"],
	&"weapon_cycle": ["sfx_weapon_cycle"], &"weapon_equip": ["sfx_weapon_equip"],
	&"combo_tick": ["sfx_combo_tick"], &"combo_milestone": ["sfx_combo_milestone"], &"pickup": ["sfx_pickup"],
	&"inspect_open": ["sfx_inspect_open"], &"inspect_close": ["sfx_inspect_close"],
	&"clean_sparkle": ["sfx_clean_sparkle"], &"grime_warning": ["sfx_grime_warning"], &"scrub": ["sfx_scrub"],
}
## Sounds that repeat fast get a small pitch and volume change so they do not sound mechanical.
const VARIED: Array[StringName] = [&"shot", &"shot_pistol", &"shot_shotgun", &"shot_smg", &"bat_swing", &"bat_hit", &"hit", &"zombie_hurt", &"poof", &"groan", &"combo_tick", &"lane_change"]
## Most sound effects that play at once. A new sound beyond it is dropped.
const POLYPHONY: int = 8
## Most groans that play at once.
const MAX_GROANS: int = 2
## Seconds between groans.
const GROAN_INTERVAL: float = 2.5
## Share of pitch and volume spread for varied sounds.
const PITCH_SPREAD: float = 0.08
const VOLUME_SPREAD_DB: float = 2.0
## Music sits this far below the ambience and effects mix.
const MUSIC_VOLUME_DB: float = -12.0
const AMBIENT_VOLUME_DB: float = -6.0
## Looping layers: file stem and bus. Every layer plays from unlock so a fade never restarts a track.
const LAYERS: Dictionary[StringName, Array] = {
	&"menu": ["music_menu", &"Music"], &"camp": ["amb_camp", &"Sfx"],
	&"run_base": ["run_base", &"Music"], &"run_tension": ["run_tension", &"Music"], &"road": ["amb_road", &"Sfx"],
}
## File stem of the scrub loop.
const SCRUB_LOOP: String = "sfx_scrub_loop"
## Highest level the master bus lets through.
const LIMITER_CEILING_DB: float = -1.0
## Sound effects sit below the music so a run of shots never hides the loops.
const SFX_BUS_DB: float = -6.0
## Fade speed of a layer in dB per second.
const LAYER_FADE_DB_PER_SECOND: float = 40.0
## Volume in dB at which a bus counts as muted.
const MUTED_DB: float = -80.0

## Counts of play calls per sound name, for the readout and tests. Headless builds cannot play sound.
var play_counts: Dictionary[StringName, int] = {}
## Whether the first tap has unlocked audio.
var unlocked: bool = false
## Whether sound is muted.
var muted: bool = false

var _streams: Dictionary[String, AudioStream] = {}
var _missing: Dictionary[String, bool] = {}
var _pool: Array[AudioStreamPlayer] = []
var _groan_players: Array[AudioStreamPlayer] = []
var _groan_cooldown: float = 0.0
var _layers: Dictionary[StringName, AudioStreamPlayer] = {}
var _scrub_player: AudioStreamPlayer
var _layer_target: Dictionary[StringName, float] = {}
var _scene: StringName = &""
var _tension: bool = false
var _volumes: Dictionary[StringName, float] = {SFX_BUS: 1.0, MUSIC_BUS: 1.0}


func _ready() -> void:
	_ensure_bus(SFX_BUS)
	_ensure_bus(MUSIC_BUS)
	_add_master_limiter()
	for index: int in POLYPHONY:
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.bus = SFX_BUS
		add_child(player)
		_pool.append(player)
	for layer: StringName in LAYERS:
		var spec: Array = LAYERS[layer]
		_layers[layer] = _make_loop_player(spec[0], spec[1], MUTED_DB)
		_layer_target[layer] = MUTED_DB
	_scrub_player = _make_loop_player(SCRUB_LOOP, SFX_BUS, 0.0)


func _process(delta: float) -> void:
	_groan_cooldown = maxf(_groan_cooldown - delta, 0.0)
	for layer: StringName in _layers:
		var player: AudioStreamPlayer = _layers[layer]
		player.volume_db = move_toward(player.volume_db, _layer_target[layer], delta * LAYER_FADE_DB_PER_SECOND)


## Starts the loops. The first tap on the start screen calls this, so web audio is unlocked by a real gesture.
func unlock() -> void:
	if unlocked:
		return
	unlocked = true
	for layer: StringName in _layers:
		var player: AudioStreamPlayer = _layers[layer]
		if player.stream != null:
			player.play()
	_apply_scene()


## Switches between the menu mix and the run mix with a crossfade. The run layers start together so they stay on the same beat.
func set_scene(scene: StringName) -> void:
	if scene == _scene:
		return
	_scene = scene
	_apply_scene()


## Fades the tension layer in for a horde and out afterwards. Both groove layers share tempo and key, so the blend never clashes.
func set_tension(on: bool) -> void:
	_tension = on
	_apply_scene()


## Returns each layer as name:volume:playing, for the readout and tests.
func layer_report() -> String:
	var parts: PackedStringArray = []
	for layer: StringName in _layers:
		var player: AudioStreamPlayer = _layers[layer]
		parts.append("%s:%d:%d:%.1f" % [layer, roundi(player.volume_db), 1 if player.playing else 0, player.get_playback_position()])
	return ",".join(parts)


## Plays a named sound once. Nothing plays before unlock().
func play(sound: StringName, pitch_scale: float = 1.0) -> void:
	if not unlocked or muted or not SOUNDS.has(sound):
		return
	var names: Array = SOUNDS[sound]
	var stem: String = names[randi() % names.size()]
	var stream: AudioStream = _load_stream(stem)
	play_counts[sound] = play_counts.get(sound, 0) + 1
	if stream == null:
		return
	var player: AudioStreamPlayer = _free_player()
	if player == null:
		return
	player.stream = stream
	player.pitch_scale = pitch_scale + (randf_range(-PITCH_SPREAD, PITCH_SPREAD) if sound in VARIED else 0.0)
	player.volume_db = randf_range(-VOLUME_SPREAD_DB, 0.0) if sound in VARIED else 0.0
	player.play()
	if sound == &"groan":
		_groan_players.append(player)


## Starts or stops the scrub loop of the cleaning station. It only plays while the hand rubs.
func set_scrubbing(on: bool) -> void:
	if not unlocked or muted or _scrub_player.stream == null or _scrub_player.playing == on:
		return
	if on:
		_scrub_player.play()
	else:
		_scrub_player.stop()


## Plays a groan at most every few seconds, and never more than two at once.
func play_groan() -> void:
	if _groan_cooldown > 0.0:
		return
	_groan_players = _groan_players.filter(func(player: AudioStreamPlayer) -> bool: return player.playing)
	if _groan_players.size() >= MAX_GROANS:
		return
	_groan_cooldown = GROAN_INTERVAL
	play(&"groan")


## Sets the linear volume of the Sfx or Music bus, from 0 to 1.
func set_volume(bus: StringName, linear: float) -> void:
	_volumes[bus] = clampf(linear, 0.0, 1.0)
	_apply_volume(bus)


## Returns the linear volume of a bus.
func get_volume(bus: StringName) -> float:
	return _volumes[bus]


## Mutes or unmutes everything.
func set_muted(value: bool) -> void:
	muted = value
	AudioServer.set_bus_mute(AudioServer.get_bus_index(&"Master"), value)


## Returns the total number of play calls, for the readout.
func total_plays() -> int:
	var total: int = 0
	for count: int in play_counts.values():
		total += count
	return total


## Effects peaked at full scale and clipped, which buried the music. The limiter holds the sum under the ceiling.
func _add_master_limiter() -> void:
	var master: int = AudioServer.get_bus_index(&"Master")
	var limiter: AudioEffectHardLimiter = AudioEffectHardLimiter.new()
	limiter.ceiling_db = LIMITER_CEILING_DB
	AudioServer.add_bus_effect(master, limiter)
	_apply_volume(SFX_BUS)


func _apply_scene() -> void:
	var run: bool = _scene == &"run"
	_layer_target[&"menu"] = MUTED_DB if run else MUSIC_VOLUME_DB
	_layer_target[&"camp"] = MUTED_DB if run else AMBIENT_VOLUME_DB
	_layer_target[&"run_base"] = MUSIC_VOLUME_DB if run and not _tension else (MUSIC_VOLUME_DB - 8.0 if run else MUTED_DB)
	_layer_target[&"run_tension"] = MUSIC_VOLUME_DB if run and _tension else MUTED_DB
	_layer_target[&"road"] = AMBIENT_VOLUME_DB if run else MUTED_DB


func _apply_volume(bus: StringName) -> void:
	var linear: float = _volumes[bus]
	var offset: float = SFX_BUS_DB if bus == SFX_BUS else 0.0
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(bus), MUTED_DB if linear <= 0.0 else linear_to_db(linear) + offset)


func _ensure_bus(bus: StringName) -> void:
	if AudioServer.get_bus_index(bus) != -1:
		return
	AudioServer.add_bus()
	var index: int = AudioServer.get_bus_count() - 1
	AudioServer.set_bus_name(index, bus)
	AudioServer.set_bus_send(index, &"Master")


func _make_loop_player(stem: String, bus: StringName, volume_db: float) -> AudioStreamPlayer:
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.bus = bus
	player.volume_db = volume_db
	var stream: AudioStream = _load_stream(stem)
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	player.stream = stream
	add_child(player)
	return player


func _load_stream(stem: String) -> AudioStream:
	if _streams.has(stem):
		return _streams[stem]
	if _missing.has(stem):
		return null
	var path: String = AUDIO_DIR + stem + ".ogg"
	if not ResourceLoader.exists(path):
		push_warning("AudioBus: missing audio file %s" % path)
		_missing[stem] = true
		return null
	var stream: AudioStream = load(path)
	_streams[stem] = stream
	return stream


func _free_player() -> AudioStreamPlayer:
	for player: AudioStreamPlayer in _pool:
		if not player.playing:
			return player
	return null
