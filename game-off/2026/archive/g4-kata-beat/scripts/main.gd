class_name Main
extends Node2D
## Kata Beat core loop: audio clock, input, judging, score and state.
##
## Note positions come from the audio playback position, so taps stay locked to the sound.

## Added to the audio clock in milliseconds. Lower it when taps judge late, raise it when early.
const LATENCY_OFFSET_MS: float = 0.0
## Tap gap in seconds for a Perfect.
const PERFECT_WINDOW: float = 0.05
## Tap gap in seconds for a Good.
const GOOD_WINDOW: float = 0.11
## Tap gap in seconds beyond which a tap is a free tap, not a miss.
const MISS_WINDOW: float = 0.2
## Visual freeze in seconds on a hit. Audio and the clock keep running.
const HIT_STOP: float = 0.03
## Milliseconds after the results open before a tap restarts. Stops a stray tap skipping them.
const RESTART_GUARD_MSEC: int = 400
## Song seconds per frame in smoke mode.
const SMOKE_STEP: float = 0.02
## Combos that trigger a finisher.
const FINISHER_COMBOS: Array[int] = [8, 16, 24]
const KEY_LANES: Dictionary = {
	KEY_A: 0, KEY_S: 1, KEY_D: 2, KEY_J: 0, KEY_K: 1, KEY_L: 2,
}

## Run states.
enum State { WAITING, PLAYING, DONE }
## Per-note status bytes.
enum Status { PENDING, HIT, MISSED }

## Current run state.
var state: State = State.WAITING
## Song time in seconds. Negative values are possible just after the start.
var song_time: float = 0.0
## Current combo.
var combo: int = 0
## Best combo of this run.
var max_combo: int = 0
## Score of this run.
var score: int = 0
## Note times in seconds.
var times: PackedFloat32Array = PackedFloat32Array()
## Note lanes.
var lanes: PackedInt32Array = PackedInt32Array()
## Note [enum Status] bytes.
var status: PackedByteArray = PackedByteArray()

var _clock: float = 0.0
var _start_usec: int = 0
var _done_msec: int = 0
var _hit_stop: float = 0.0
var _smoke: bool = false
var _smoke_clock: float = 0.0
var _music: AudioStreamPlayer
var _sfx: Array[AudioStreamPlayer] = []
var _hud: Hud
var _punch_tween: Tween

@onready var _field: Playfield = $Playfield
@onready var _stage: Stage = $Stage
@onready var _camera: Camera2D = $Camera


func _ready() -> void:
	Kata.build(times, lanes)
	status.resize(times.size())
	_field.times = times
	_field.lanes = lanes
	_field.status = status
	_hud = Hud.new()
	add_child(_hud)
	_music = AudioStreamPlayer.new()
	_music.stream = Synth.make_backing()
	_music.volume_db = -4.0
	add_child(_music)
	for sound in 4:
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.stream = Synth.make_hit(sound)
		player.max_polyphony = 4
		add_child(player)
		_sfx.append(player)
	_smoke = OS.get_cmdline_user_args().has("--smoke")
	if _smoke:
		var test: SmokeTest = SmokeTest.new()
		test.main = self
		add_child(test)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var click: InputEventMouseButton = event
		if click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
			_on_tap(Playfield.lane_at(click.position))
	elif event is InputEventKey:
		var key: InputEventKey = event
		if key.pressed and not key.echo:
			_on_tap(KEY_LANES.get(key.physical_keycode, -1))


func _process(delta: float) -> void:
	if _smoke and state == State.PLAYING:
		_smoke_clock += SMOKE_STEP
	song_time = _now()
	if state == State.PLAYING:
		_expire_late_notes()
		if song_time >= Kata.RESULT_TIME:
			_finish()
	if _hit_stop > 0.0:
		_hit_stop -= delta
	else:
		_stage.advance(delta)
	_stage.beat_phase = song_time / Kata.BEAT
	_field.song_time = song_time
	_field.advance(delta)


## Returns true once a tap on the results screen restarts the run.
func can_restart() -> bool:
	return state == State.DONE and Time.get_ticks_msec() - _done_msec >= RESTART_GUARD_MSEC


func _on_tap(lane: int) -> void:
	if lane < 0:
		return
	_hud.dismiss_hint()
	if state == State.DONE:
		if can_restart():
			_start()
		return
	if state == State.WAITING:
		_start()
	_field.pad_flash[lane] = 1.0
	_judge(lane)


func _start() -> void:
	status.fill(Status.PENDING)
	combo = 0
	max_combo = 0
	score = 0
	_clock = -1.0
	_smoke_clock = 0.0
	song_time = 0.0
	_start_usec = Time.get_ticks_usec()
	state = State.PLAYING
	_music.play()
	_stage.reset()
	_hud.hide_results()
	_hud.set_score(0)
	_hud.set_combo(0)


func _finish() -> void:
	state = State.DONE
	_done_msec = Time.get_ticks_msec()
	_music.stop()
	_hud.show_results(score, max_combo)


## Reads the audio clock. Falls back to wall time when the player is not running.
func _now() -> float:
	if state != State.PLAYING:
		return song_time
	var raw: float
	if _smoke:
		raw = _smoke_clock
	elif _music.playing:
		raw = _music.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()
	else:
		raw = (Time.get_ticks_usec() - _start_usec) / 1000000.0
	_clock = maxf(_clock, raw + LATENCY_OFFSET_MS / 1000.0)
	return _clock


func _judge(lane: int) -> void:
	var now: float = _now()
	var best: int = -1
	var best_gap: float = MISS_WINDOW
	for i in times.size():
		if times[i] > now + MISS_WINDOW:
			break
		if status[i] != Status.PENDING or lanes[i] != lane:
			continue
		var gap: float = absf(now - times[i])
		if gap <= best_gap:
			best = i
			best_gap = gap
	if best < 0:
		_play_sfx(lane, -10.0)
	elif best_gap <= GOOD_WINDOW:
		status[best] = Status.HIT
		_register_hit(lane, best_gap <= PERFECT_WINDOW, now - times[best])
	else:
		status[best] = Status.MISSED
		_register_miss()


func _expire_late_notes() -> void:
	var missed: bool = false
	for i in times.size():
		if times[i] >= song_time - GOOD_WINDOW:
			break
		if status[i] == Status.PENDING:
			status[i] = Status.MISSED
			missed = true
	if missed:
		_register_miss()


func _register_hit(lane: int, perfect: bool, signed_gap: float) -> void:
	combo += 1
	max_combo = maxi(max_combo, combo)
	score += int((100 if perfect else 50) * (1.0 + combo / 8.0))
	var finisher: bool = combo in FINISHER_COMBOS
	_play_sfx(lane, 0.0)
	_stage.perform(lane, finisher)
	_hit_stop = HIT_STOP
	if finisher:
		_punch_camera()
		_hud.flash_verdict("FINISHER!", Kata.AMBER)
	elif perfect:
		_hud.flash_verdict("PERFECT", Kata.INK)
	else:
		_hud.flash_verdict("GOOD (%s)" % ("late" if signed_gap > 0.0 else "early"), Color(Kata.INK, 0.8))
	_hud.set_score(score)
	_hud.set_combo(combo)


func _register_miss() -> void:
	combo = 0
	_play_sfx(Synth.MISS_SOUND, 0.0)
	_stage.stumble()
	_hud.flash_verdict("MISS", Kata.MAGENTA)
	_hud.set_combo(0)


func _play_sfx(sound: int, volume_db: float) -> void:
	_sfx[sound].volume_db = volume_db
	_sfx[sound].play()


func _punch_camera() -> void:
	_camera.zoom = Vector2.ONE * 1.08
	if _punch_tween:
		_punch_tween.kill()
	_punch_tween = create_tween()
	_punch_tween.tween_property(_camera, "zoom", Vector2.ONE, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
