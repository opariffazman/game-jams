extends Node
## Plays every sound of the game through pooled players on four buses.
##
## The Sfx, Ui and Voice buses carry one-shot sounds. The Music bus carries the loops. All keep running while
## the tree is paused or frozen by a hit stop, so a sound never cuts short. The sound toggle in settings mutes
## the Master bus. A sound slot with no file loads as silence, so a missing file never stops the game.

## Seconds of equal-power crossfade between two music loops.
const MUSIC_CROSSFADE: float = 1.5
## Music level drop in dB while a voice line plays.
const DUCK_DB: float = -6.0
## How fast the duck moves, in dB per second.
const DUCK_RATE_DB: float = 24.0
## Most players a slot pool creates when its cap is above this.
const MAX_POOL: int = 8

## Times each slot started since the game began. Tests read it.
var play_counts: Dictionary = {}
## Names of the slots whose files did not load. Tests read it.
var missing_files: Array[String] = []

## True when no device hears the sound. A headless run counts plays but never starts a player, because the audio
## server keeps a started playback alive until its next mix and a test quits before that, which leaks the stream.
var _muted_by_host: bool = DisplayServer.get_name() == "headless"
var _slots: Dictionary = {}
var _voice_priority: int = 0
var _voice_player: AudioStreamPlayer
var _music_players: Array[AudioStreamPlayer] = []
var _music_key: String = ""
var _wanted_music: Array[String] = []
var _music_streams: Array[AudioStream] = []
var _music_variant: int = 0
var _current: int = -1
var _outgoing: int = -1
var _current_start_ms: int = 0
var _cross_start_ms: int = 0
var _duck_db: float = 0.0
var _last_process_usec: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_slots()
	for index: int in 2:
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.bus = AudioSet.BUS_MUSIC
		add_child(player)
		_music_players.append(player)
	_apply_sound_setting(SettingsRef.sound_enabled())
	SettingsRef.on_sound_changed(_apply_sound_setting)
	_last_process_usec = Time.get_ticks_usec()


func _process(_delta: float) -> void:
	var now_usec: int = Time.get_ticks_usec()
	var real_delta: float = float(now_usec - _last_process_usec) / 1000000.0
	_last_process_usec = now_usec
	if _voice_player != null and _voice_priority > 0 and not _busy(_voice_player):
		_voice_priority = 0
	var duck_target: float = DUCK_DB if _voice_priority > 0 else 0.0
	_duck_db = move_toward(_duck_db, duck_target, DUCK_RATE_DB * real_delta)
	_update_music(Time.get_ticks_msec())


## Plays [param slot_name]. [param volume_offset_db] adds to the slot level and [param pitch_override] above zero
## replaces the random pitch. Returns the length in seconds of the sound started, or 0.0 when nothing played.
func play(slot_name: StringName, volume_offset_db: float = 0.0, pitch_override: float = 0.0) -> float:
	var slot: Dictionary = _slots.get(slot_name, {})
	if slot.is_empty() or not SettingsRef.sound_enabled():
		return 0.0
	var streams: Array = slot["streams"]
	if streams.is_empty():
		return 0.0
	var now_ms: int = Time.get_ticks_msec()
	if now_ms - int(slot["last_ms"]) < int(slot["gap_ms"]):
		return 0.0
	var player: AudioStreamPlayer
	if slot["bus"] == AudioSet.BUS_VOICE:
		if _voice_priority >= int(slot["priority"]) and _busy(_voice_player):
			return 0.0
		player = _voice_player
		_voice_priority = int(slot["priority"])
	else:
		player = _pick_player(slot)
	slot["last_ms"] = now_ms
	var stream: AudioStream = streams[randi() % streams.size()]
	player.stream = stream
	player.bus = slot["bus"]
	player.volume_db = float(slot["db"]) + volume_offset_db
	player.pitch_scale = pitch_override if pitch_override > 0.0 else randf_range(float(slot["pitch_min"]), float(slot["pitch_max"]))
	_start(player)
	play_counts[slot_name] = int(play_counts.get(slot_name, 0)) + 1
	return stream.get_length()


## Plays the loops of a music phase. [param names] are file names without folder or extension.
## One variant plays, and on each loop the next one crossfades in. Missing files are skipped, so with no file
## the music stays silent. An empty list fades the music out. Calling again with the same list does nothing.
func play_music(names: Array[String]) -> void:
	_wanted_music = names
	var key: String = ",".join(names)
	if key == _music_key:
		return
	_music_key = key
	_music_streams.clear()
	for name: String in names:
		var path: String = AudioSet.MUSIC_DIR + name + ".ogg"
		if ResourceLoader.exists(path):
			_music_streams.append(load(path) as AudioStream)
	var now_ms: int = Time.get_ticks_msec()
	if _outgoing >= 0:
		_halt(_music_players[_outgoing])
	_outgoing = _current
	_current = -1
	_cross_start_ms = now_ms
	if _music_streams.is_empty() or not SettingsRef.sound_enabled():
		return
	_music_variant = randi() % _music_streams.size()
	_start_variant(now_ms)


## True while a music loop plays or fades.
func music_active() -> bool:
	return _current >= 0 or _outgoing >= 0


## Sets the Master bus mute to match the sound setting.
func _apply_sound_setting(enabled: bool) -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index(&"Master"), not enabled)
	if not enabled:
		for player: AudioStreamPlayer in _music_players:
			_halt(player)
		_current = -1
		_outgoing = -1
		_music_key = ""
	elif not _wanted_music.is_empty():
		play_music(_wanted_music)
	if _voice_player != null and not enabled:
		_halt(_voice_player)


func _load_slots() -> void:
	var pool_root: Node = Node.new()
	pool_root.name = "Pools"
	add_child(pool_root)
	for slot_name: StringName in AudioSet.slots():
		var slot: Dictionary = AudioSet.slots()[slot_name]
		var streams: Array[AudioStream] = []
		for file: String in slot["files"]:
			var path: String = AudioSet.DIR + file + ".ogg"
			if ResourceLoader.exists(path):
				streams.append(load(path) as AudioStream)
			else:
				missing_files.append(path)
		slot["streams"] = streams
		slot["players"] = []
		slot["next"] = 0
		slot["last_ms"] = -1000000
		_slots[slot_name] = slot
	_voice_player = AudioStreamPlayer.new()
	_voice_player.name = "Voice"
	_voice_player.bus = AudioSet.BUS_VOICE
	pool_root.add_child(_voice_player)


func _halt(player: AudioStreamPlayer) -> void:
	player.set_meta(&"end_ms", 0)
	player.stop()


func _start(player: AudioStreamPlayer) -> void:
	player.set_meta(&"end_ms", Time.get_ticks_msec() + int(player.stream.get_length() * 1000.0 / maxf(player.pitch_scale, 0.1)))
	if not _muted_by_host:
		player.play()


func _busy(player: AudioStreamPlayer) -> bool:
	if _muted_by_host:
		return Time.get_ticks_msec() < int(player.get_meta(&"end_ms", 0))
	return player.playing


func _pick_player(slot: Dictionary) -> AudioStreamPlayer:
	var players: Array = slot["players"]
	for player: AudioStreamPlayer in players:
		if not _busy(player):
			return player
	if players.size() < mini(int(slot["cap"]), MAX_POOL):
		var created: AudioStreamPlayer = AudioStreamPlayer.new()
		get_node("Pools").add_child(created)
		players.append(created)
		return created
	var index: int = int(slot["next"]) % players.size()
	slot["next"] = index + 1
	return players[index]


func _start_variant(now_ms: int) -> void:
	_current = 0 if _outgoing != 0 else 1
	var player: AudioStreamPlayer = _music_players[_current]
	var stream: AudioStream = _music_streams[_music_variant % _music_streams.size()]
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = false
	player.stream = stream
	player.volume_db = -80.0
	_start(player)
	_current_start_ms = now_ms
	_cross_start_ms = now_ms


func _update_music(now_ms: int) -> void:
	if _current >= 0:
		var current_player: AudioStreamPlayer = _music_players[_current]
		var length_ms: float = current_player.stream.get_length() * 1000.0
		var crossfade_ms: float = MUSIC_CROSSFADE * 1000.0
		if float(now_ms - _current_start_ms) >= length_ms - crossfade_ms or not _busy(current_player):
			if _outgoing >= 0:
				_halt(_music_players[_outgoing])
			_outgoing = _current
			_music_variant = (_music_variant + 1) % _music_streams.size()
			_start_variant(now_ms)
			current_player = _music_players[_current]
		var progress: float = clampf(float(now_ms - _cross_start_ms) / crossfade_ms, 0.0, 1.0)
		current_player.volume_db = linear_to_db(sin(progress * PI * 0.5)) + _duck_db
		if _outgoing >= 0:
			var outgoing_player: AudioStreamPlayer = _music_players[_outgoing]
			if progress >= 1.0 or not _busy(outgoing_player):
				_halt(outgoing_player)
				_outgoing = -1
			else:
				outgoing_player.volume_db = linear_to_db(cos(progress * PI * 0.5)) + _duck_db
	elif _outgoing >= 0:
		var fade: float = clampf(float(now_ms - _cross_start_ms) / (MUSIC_CROSSFADE * 1000.0), 0.0, 1.0)
		var fading_player: AudioStreamPlayer = _music_players[_outgoing]
		if fade >= 1.0 or not _busy(fading_player):
			_halt(fading_player)
			_outgoing = -1
		else:
			fading_player.volume_db = linear_to_db(cos(fade * PI * 0.5)) + _duck_db
