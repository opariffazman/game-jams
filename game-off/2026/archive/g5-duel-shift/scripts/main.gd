class_name Main
extends Node2D
## Duel Shift core loop. The boss tells, the hero shifts stance, clean dodges build a counter.

## Round flow states.
enum Phase { TELL, FIRE, GAP, COUNTER, WIN, LOSE }

## Hero hip height.
const HERO_Y: float = 490.0
## Boss hip position.
const BOSS_POS: Vector2 = Vector2(270.0, 170.0)
## Screen y of the HIGH SHOT beam, at standing head height.
const BEAM_Y: float = 408.0
## Lane x per [enum DuelRules.Tell].
const TELL_X: Array[float] = [120.0, 420.0, 270.0, 270.0]
## Hero x per [enum DuelRules.Stance].
const STANCE_X: Array[float] = [270.0, 120.0, 420.0, 270.0]
## Hero pose per [enum DuelRules.Stance].
const STANCE_POSE: Array[StringName] = [&"stand", &"left", &"right", &"duck"]
## Seconds a bullet takes to cross.
const FIRE_TIME: float = 0.16
## Pause between rounds.
const GAP_TIME: float = 0.55
## Counter lunge length in slow-motion seconds.
const LUNGE_TIME: float = 0.3
## Counter return length.
const RETURN_TIME: float = 0.3
## Hit stop in real seconds.
const STOP_TIME: float = 0.06
## Time scale during the lunge.
const SLOW_SCALE: float = 0.4
## Focus pips that trigger a counter.
const PIPS_TO_COUNTER: int = 3
## First tell sequence seed. Each restart adds one.
const BASE_SEED: int = 5
## Hero position when the counter lands.
const IMPACT_POS: Vector2 = Vector2(270.0, 290.0)

## Current flow state.
var phase: Phase = Phase.TELL
## Seconds in the current phase, scaled by game speed.
var phase_t: float = 0.0
## Current telegraph.
var tell: int = DuelRules.Tell.LEFT
## Length of the current tell.
var tell_len: float = 0.7
## Zero-based round counter.
var round_index: int = 0
## Hero stance.
var stance: int = DuelRules.Stance.CENTER
## Hero hearts left.
var hearts: int = 3
## Boss health left.
var boss_hp: int = 3
## Focus pips held.
var pips: int = 0
## Hero figure.
var hero: Figure
## Hero position before stagger shake.
var hero_base: Vector2 = Vector2(270.0, HERO_Y)
## Where the counter lunge started.
var lunge_from: Vector2 = Vector2.ZERO
## Counter lunge progress, 0 to 1.
var lunge_p: float = 0.0
## Seconds of smear arc left.
var smear_t: float = 0.0
## Popup text near the hero.
var popup_text: String = ""
## Seconds of popup left.
var popup_t: float = 0.0
## Popup color.
var popup_color: Color = Palette.AMBER

var _boss: Figure
var _rules: DuelRules
var _run_count: int = 0
var _time_scale: float = 1.0
var _will_hit: bool = false
var _resolved: bool = false
var _counter_stage: int = 0
var _stop_left: float = 0.0
var _stagger_t: float = 0.0
var _shake: float = 0.0
var _drag_pad: int = -1
var _hint_done: bool = false
var _trail: Line2D
var _burst: CPUParticles2D
var _zoom_tween: Tween

@onready var _camera: Camera2D = $Camera2D
@onready var _hud: Hud = $Ui/Hud


func _ready() -> void:
	_boss = _make_figure(Palette.MAGENTA, 1.5)
	_boss.position = BOSS_POS
	hero = _make_figure(Palette.CYAN, 1.0)
	_trail = Line2D.new()
	_trail.width = 12.0
	_trail.default_color = Palette.AMBER
	_trail.gradient = Gradient.new()
	_trail.gradient.colors = PackedColorArray([Color(Palette.AMBER, 0.0), Palette.AMBER])
	add_child(_trail)
	_burst = _make_burst()
	var fx: Fx = Fx.new()
	fx.main = self
	add_child(fx)
	if "--smoke" in OS.get_cmdline_user_args():
		var bot: SmokeBot = SmokeBot.new()
		bot.main = self
		add_child(bot)
	_restart()


func _process(delta: float) -> void:
	var dt: float = minf(delta * _time_scale, 0.1)
	phase_t += dt
	_hud.hint_alpha = move_toward(_hud.hint_alpha, 0.0 if _hint_done else 1.0, delta * 2.0)
	smear_t = maxf(smear_t - delta, 0.0)
	popup_t = maxf(popup_t - delta, 0.0)
	_shake = maxf(_shake - delta * 4.0, 0.0)
	_tick_stagger(delta)
	match phase:
		Phase.TELL:
			if phase_t >= tell_len:
				_fire()
		Phase.FIRE:
			_tick_fire()
		Phase.GAP:
			if phase_t >= GAP_TIME:
				_start_tell()
		Phase.COUNTER:
			_tick_counter(delta)
	hero.position = hero_base + Vector2(sin(_stagger_t * 70.0) * 12.0 * _stagger_t / 0.3, 0.0)
	_boss.position = BOSS_POS + Vector2(randf_range(-1.0, 1.0) * _shake * 14.0, 0.0)
	_sync_hud()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var click: InputEventMouseButton = event
		if click.button_index != MOUSE_BUTTON_LEFT:
			return
		_drag_pad = -1
		if click.pressed:
			_press(Hud.pad_at(click.position))
			_drag_pad = Hud.pad_at(click.position)
	elif event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event
		var pad: int = Hud.pad_at(motion.position)
		if motion.button_mask & MOUSE_BUTTON_MASK_LEFT and pad >= 0 and pad != _drag_pad:
			_drag_pad = pad
			_set_stance(Hud.PAD_STANCES[pad])
	elif event is InputEventKey:
		var key: InputEventKey = event
		if key.pressed and not key.echo:
			_press(["A", "S", "D"].find(OS.get_keycode_string(key.keycode)))


func _press(pad: int) -> void:
	if phase == Phase.WIN or phase == Phase.LOSE:
		_restart()
		return
	if pad < 0:
		return
	var wanted: int = Hud.PAD_STANCES[pad]
	_set_stance(DuelRules.Stance.CENTER if wanted == stance else wanted)


func _set_stance(new_stance: int) -> void:
	stance = new_stance
	_hint_done = true
	_apply_stance()


func _apply_stance() -> void:
	if phase == Phase.COUNTER or phase == Phase.WIN or phase == Phase.LOSE:
		return
	hero_base = Vector2(STANCE_X[stance], HERO_Y)
	hero.set_pose(STANCE_POSE[stance])


func _restart() -> void:
	_rules = DuelRules.new(BASE_SEED + _run_count)
	_run_count += 1
	stance = DuelRules.Stance.CENTER
	hearts = 3
	boss_hp = 3
	pips = 0
	round_index = 0
	_time_scale = 1.0
	_stagger_t = 0.0
	smear_t = 0.0
	_hud.end_text = ""
	_start_tell()
	_apply_stance()


func _start_tell() -> void:
	tell = _rules.next_tell()
	tell_len = DuelRules.tell_duration(round_index)
	phase = Phase.TELL
	phase_t = 0.0
	_boss.set_pose(&"charge")
	_apply_stance()


func _fire() -> void:
	phase = Phase.FIRE
	phase_t = 0.0
	_will_hit = DuelRules.is_hit(tell as DuelRules.Tell, stance as DuelRules.Stance)
	_resolved = false
	_boss.set_pose(&"recoil")
	_trail.clear_points()


func _tick_fire() -> void:
	var p: float = clampf(phase_t / FIRE_TIME, 0.0, 1.0)
	if tell != DuelRules.Tell.HIGH:
		_trail.add_point(Vector2(TELL_X[tell], lerpf(215.0, 700.0, p)))
		if _trail.get_point_count() > 6:
			_trail.remove_point(0)
	if not _resolved and p >= 0.6:
		_resolved = true
		_resolve_shot()
	if phase == Phase.FIRE and phase_t >= FIRE_TIME:
		_trail.clear_points()
		round_index += 1
		if pips >= PIPS_TO_COUNTER:
			_start_counter()
		else:
			phase = Phase.GAP
			phase_t = 0.0
			_boss.set_pose(&"stand")


func _resolve_shot() -> void:
	if _will_hit:
		hearts -= 1
		pips = 0
		_stagger_t = 0.3
		hero.set_pose(&"stagger")
		_popup("HIT", Palette.MAGENTA)
		_emit_burst(hero.position + Vector2(0, -40), Palette.MAGENTA, 12)
		if hearts <= 0:
			phase = Phase.LOSE
			_hud.end_text = "tap to retry"
			hero.set_pose(&"down")
	else:
		pips = mini(pips + 1, PIPS_TO_COUNTER)
		_popup("DODGE", Palette.AMBER)


func _start_counter() -> void:
	phase = Phase.COUNTER
	_counter_stage = 0
	phase_t = 0.0
	_time_scale = SLOW_SCALE
	lunge_from = hero_base
	hero.set_pose(&"lunge")
	_boss.set_pose(&"charge")


func _tick_counter(delta: float) -> void:
	match _counter_stage:
		0:
			lunge_p = clampf(phase_t / LUNGE_TIME, 0.0, 1.0)
			hero_base = lunge_from.lerp(IMPACT_POS, lunge_p * lunge_p)
			if lunge_p >= 1.0:
				_impact()
		1:
			_stop_left -= delta
			if _stop_left <= 0.0:
				_counter_stage = 2
				phase_t = 0.0
				_time_scale = 1.0
		_:
			var p: float = clampf(phase_t / RETURN_TIME, 0.0, 1.0)
			hero_base = IMPACT_POS.lerp(lunge_from, p)
			if p >= 1.0:
				_finish_counter()


func _impact() -> void:
	_counter_stage = 1
	_stop_left = STOP_TIME
	_time_scale = 0.0
	boss_hp -= 1
	pips = 0
	smear_t = 0.3
	_shake = 1.0
	_boss.set_pose(&"down" if boss_hp <= 0 else &"recoil")
	_emit_burst(BOSS_POS + Vector2(0, 40), Palette.INK, 36)
	if _zoom_tween:
		_zoom_tween.kill()
	_zoom_tween = create_tween()
	_zoom_tween.tween_property(_camera, "zoom", Vector2(1.18, 1.18), 0.04)
	_zoom_tween.tween_property(_camera, "zoom", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _finish_counter() -> void:
	lunge_p = 0.0
	if boss_hp <= 0:
		phase = Phase.WIN
		_hud.end_text = "tap to duel again"
		hero_base = Vector2(270.0, HERO_Y)
		hero.set_pose(&"stand")
		return
	phase = Phase.GAP
	phase_t = 0.0
	_boss.set_pose(&"stand")
	_apply_stance()


func _tick_stagger(delta: float) -> void:
	if _stagger_t <= 0.0:
		return
	_stagger_t = maxf(_stagger_t - delta, 0.0)
	if _stagger_t == 0.0 and phase != Phase.LOSE:
		_apply_stance()


func _popup(text: String, tint: Color) -> void:
	popup_text = text
	popup_color = tint
	popup_t = 0.6


func _emit_burst(at: Vector2, tint: Color, count: int) -> void:
	_burst.position = at
	_burst.color = tint
	_burst.amount = count
	_burst.restart()


func _sync_hud() -> void:
	_hud.boss_hp = boss_hp
	_hud.hearts = hearts
	_hud.pips = pips
	_hud.stance = stance


func _make_figure(tint: Color, figure_scale: float) -> Figure:
	var figure: Figure = Figure.new()
	figure.color = tint
	figure.scale = Vector2.ONE * figure_scale
	add_child(figure)
	return figure


func _make_burst() -> CPUParticles2D:
	var burst: CPUParticles2D = CPUParticles2D.new()
	burst.one_shot = true
	burst.emitting = false
	burst.explosiveness = 1.0
	burst.lifetime = 0.5
	burst.spread = 180.0
	burst.gravity = Vector2.ZERO
	burst.initial_velocity_min = 120.0
	burst.initial_velocity_max = 340.0
	burst.scale_amount_min = 3.0
	burst.scale_amount_max = 6.0
	add_child(burst)
	return burst
