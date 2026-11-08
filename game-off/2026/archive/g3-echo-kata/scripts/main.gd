class_name Main
extends Node2D
## Echo Kata: record three takes, then watch all three hitmen clear the room together.

## Game phases. SETTLE holds the Director Cut's last frame while dummies finish falling.
enum Phase { INTRO, TAKE, CUT, SETTLE, RESULT }

const TAKE_TICKS: int = 360
const TAKE_COUNT: int = 3
const COOLDOWN_TICKS: int = 24
const DRAG_SCALE: float = 2.0
const KEY_SPEED: float = 260.0
const ZONE_TOP: float = 576.0
const HERO_START: Vector2 = Vector2(270.0, 510.0)
const TAP_TRAVEL: float = 16.0
const TAP_MSEC: int = 300
const HITSTOP_MSEC: int = 60
const SCREEN_CENTER: Vector2 = Vector2(270.0, 480.0)

## Current phase.
var phase: Phase = Phase.INTRO
## Zero based index of the take being recorded.
var take_index: int = 0
## Tick inside the current take or cut.
var tick: int = 0
## Dummies still standing when take 3 ended.
var take3_left: int = 6
var hero: Figure
var figures: Array[Figure] = []
var track_pos: Array[PackedVector2Array] = []
var track_strike: Array[PackedByteArray] = []
var _rec_pos: PackedVector2Array = PackedVector2Array()
var _rec_strike: PackedByteArray = PackedByteArray()
var _cooldown: int = 0
var _strike_queued: bool = false
var _dragging: bool = false
var _travel: float = 0.0
var _press_msec: int = 0
var _hitstop_until: int = 0
var _phase_timer: float = 0.0
var _slow_tween: Tween
var _punch_tween: Tween
@onready var _arena: Arena = $Arena
@onready var _camera: Camera2D = $Camera2D
@onready var _hud: Hud = $Layer/Hud


func _ready() -> void:
	_arena.dummy_killed.connect(_on_dummy_killed)
	_arena.figures = figures
	_start_take()
	if "--smoke" in OS.get_cmdline_user_args():
		var smoke: Smoke = Smoke.new()
		smoke.game = self
		add_child(smoke)


func _process(delta: float) -> void:
	_arena.frozen = Time.get_ticks_msec() < _hitstop_until
	_phase_timer -= delta
	if phase == Phase.INTRO and _phase_timer <= 0.0:
		phase = Phase.TAKE
		_hud.set_banner("")
	elif phase == Phase.SETTLE and _phase_timer <= 0.0:
		phase = Phase.RESULT
		_hud.set_result("%d / %d FELL" % [_arena.fallen_count(), Arena.DUMMY_SPOTS.size()])
	_hud.take_number = mini(take_index + 1, TAKE_COUNT)
	_hud.tick = tick
	_hud.left = _arena.alive_count()


func _physics_process(_delta: float) -> void:
	if Time.get_ticks_msec() < _hitstop_until:
		return
	if phase == Phase.TAKE:
		_record_tick()
	elif phase == Phase.CUT:
		_cut_tick()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event
		if button.button_index == MOUSE_BUTTON_LEFT:
			if button.pressed:
				_on_press(button.position)
			else:
				_on_release()
	elif event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event
		if _dragging and phase in [Phase.INTRO, Phase.TAKE]:
			_travel += motion.relative.length()
			_move_hero(hero.pos + motion.relative * DRAG_SCALE)
	elif event is InputEventKey:
		var key: InputEventKey = event
		if key.pressed and not key.echo:
			_on_key(key)


func _on_press(at: Vector2) -> void:
	_hud.dismiss_hint()
	if phase == Phase.RESULT:
		_restart()
	elif phase in [Phase.INTRO, Phase.TAKE] and at.y >= ZONE_TOP:
		_dragging = true
		_travel = 0.0
		_press_msec = Time.get_ticks_msec()


func _on_release() -> void:
	var held: int = Time.get_ticks_msec() - _press_msec
	if _dragging and _travel < TAP_TRAVEL and held < TAP_MSEC:
		_strike_queued = true
	_dragging = false


func _on_key(key: InputEventKey) -> void:
	_hud.dismiss_hint()
	if phase == Phase.RESULT:
		_restart()
	elif key.physical_keycode == KEY_SPACE:
		_strike_queued = true


func _move_hero(target: Vector2) -> void:
	hero.move_to(target.clamp(Arena.ROOM.position, Arena.ROOM.end))


func _start_take() -> void:
	phase = Phase.INTRO
	_phase_timer = 0.8
	tick = 0
	_cooldown = 0
	_strike_queued = false
	_rec_pos.resize(TAKE_TICKS)
	_rec_strike.resize(TAKE_TICKS)
	_arena.reset_dummies()
	figures.clear()
	for k: int in take_index:
		var ghost: Figure = Figure.new(Hud.TRACK_COLORS[k], k + 1, k == 1, true)
		ghost.reset(track_pos[k][0])
		figures.append(ghost)
	hero = Figure.new(Palette.CYAN, take_index + 1, false, false)
	hero.reset(HERO_START)
	figures.append(hero)
	_sync_hud_tracks(take_index)
	var ghost_note: String = "" if take_index == 0 else "\n%d ghost%s replay" % [take_index, "" if take_index == 1 else "s"]
	_hud.set_banner("TAKE %d%s" % [take_index + 1, ghost_note])


func _sync_hud_tracks(rows_full: int) -> void:
	_hud.rows_full = rows_full
	_hud.strikes.clear()
	for flags: PackedByteArray in track_strike:
		_hud.strikes.append(flags)
	if phase != Phase.CUT and phase != Phase.SETTLE:
		_hud.strikes.append(_rec_strike)


func _record_tick() -> void:
	var dir: Vector2 = Vector2(
		float(Input.is_physical_key_pressed(KEY_RIGHT) or Input.is_physical_key_pressed(KEY_D))
		- float(Input.is_physical_key_pressed(KEY_LEFT) or Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_DOWN) or Input.is_physical_key_pressed(KEY_S))
		- float(Input.is_physical_key_pressed(KEY_UP) or Input.is_physical_key_pressed(KEY_W)))
	if dir != Vector2.ZERO:
		_move_hero(hero.pos + dir.normalized() * KEY_SPEED / 60.0)
	if _cooldown > 0:
		_cooldown -= 1
	var fired: bool = _strike_queued and _cooldown == 0
	_strike_queued = false
	_rec_pos[tick] = hero.pos
	_rec_strike[tick] = 1 if fired else 0
	_play_tracks(take_index)
	hero.sample()
	if fired:
		_cooldown = COOLDOWN_TICKS
		hero.strike()
		_arena.strike_at(hero.pos, hero.facing)
	tick += 1
	if tick >= TAKE_TICKS:
		_finish_take()


func _play_tracks(count: int) -> void:
	for k: int in count:
		var ghost: Figure = figures[k]
		ghost.move_to(track_pos[k][tick])
		ghost.sample()
		if track_strike[k][tick] != 0:
			ghost.strike()
			_arena.strike_at(ghost.pos, ghost.facing)


func _finish_take() -> void:
	track_pos.append(_rec_pos.duplicate())
	track_strike.append(_rec_strike.duplicate())
	if take_index < TAKE_COUNT - 1:
		take_index += 1
		_start_take()
	else:
		take3_left = _arena.alive_count()
		_start_cut()


func _start_cut() -> void:
	phase = Phase.CUT
	tick = 0
	_arena.reset_dummies()
	figures.clear()
	for k: int in TAKE_COUNT:
		var fig: Figure = Figure.new(Hud.TRACK_COLORS[k], k + 1, k == 1, k < 2)
		fig.reset(track_pos[k][0])
		figures.append(fig)
	_sync_hud_tracks(TAKE_COUNT)
	_hud.set_banner("DIRECTOR CUT")


func _cut_tick() -> void:
	_play_tracks(TAKE_COUNT)
	tick += 1
	if tick >= TAKE_TICKS:
		phase = Phase.SETTLE
		_phase_timer = 1.0
		_hud.set_banner("")
		_set_time_scale(1.0)


func _restart() -> void:
	_set_time_scale(1.0)
	track_pos.clear()
	track_strike.clear()
	take_index = 0
	_hud.set_result("")
	_start_take()


func _set_time_scale(value: float) -> void:
	if _slow_tween:
		_slow_tween.kill()
	Engine.time_scale = value


func _on_dummy_killed(world_pos: Vector2) -> void:
	if phase == Phase.CUT:
		_hitstop_until = Time.get_ticks_msec() + HITSTOP_MSEC
		_slow_motion_ramp()
		_punch(1.16, world_pos)
	else:
		_punch(1.05, world_pos)


func _slow_motion_ramp() -> void:
	if _slow_tween:
		_slow_tween.kill()
	_slow_tween = create_tween().set_ignore_time_scale(true)
	_slow_tween.tween_property(Engine, "time_scale", 0.2, 0.04)
	_slow_tween.tween_interval(0.12)
	_slow_tween.tween_property(Engine, "time_scale", 1.0, 0.35).set_ease(Tween.EASE_IN)


func _punch(zoom_level: float, focus: Vector2) -> void:
	if _punch_tween:
		_punch_tween.kill()
	_punch_tween = create_tween().set_ignore_time_scale(true)
	_punch_tween.tween_property(_camera, "zoom", Vector2.ONE * zoom_level, 0.04)
	_punch_tween.parallel().tween_property(_camera, "offset", (focus - SCREEN_CENTER) * 0.2, 0.04)
	_punch_tween.tween_property(_camera, "zoom", Vector2.ONE, 0.3).set_ease(Tween.EASE_OUT)
	_punch_tween.parallel().tween_property(_camera, "offset", Vector2.ZERO, 0.3).set_ease(Tween.EASE_OUT)
