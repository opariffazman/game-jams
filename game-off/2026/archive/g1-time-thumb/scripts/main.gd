class_name Main
extends Node2D
## Time Thumb core loop. Drag speed is the world clock: stop the thumb and bullets hang.

## Play state.
enum State { PLAYING, LOST }

const ZONE_TOP: float = 576.0
const DRAG_SCALE: float = 2.0
## Thumb speed in px/s that gives full world time.
const REF_SPEED: float = 450.0
## Gauge loss per second. Gives a freeze in about 0.1 s and rides over input gaps.
const FLOW_DECAY: float = 10.0
const KEY_SPEED: float = 520.0
const MAX_DT: float = 0.05
const HERO_START := Vector2(270.0, 820.0)
const HERO_BOUNDS := Rect2(24.0, 330.0, 492.0, 600.0)
const BODY_OFFSET := Vector2(0.0, -26.0)
const HERO_HIT_RADIUS: float = 9.0
const GUNMAN_HIT_RADIUS: float = 22.0
const BULLET_RADIUS: float = 4.0
const HERO_BULLET_SPEED: float = 760.0
const GUNMAN_BULLET_SPEED: float = 170.0
const FIRE_COOLDOWN: float = 0.3
const START_GUNMEN: int = 3
const MAX_GUNMEN: int = 5
const HIT_STOP: float = 0.06
const MAGENTA := Color("ff2e88")
const CYAN := Color("19e3ff")
const AMBER := Color("ffb020")
const INK := Color("f6f6f8")
const KILL_PUNCH_ZOOM: float = 1.07

## Current play state.
var state: State = State.PLAYING
## World speed multiplier in 0..1. Scales bullets, gunmen, and cooldowns only.
var time_flow: float = 0.0
## Current wave, starting at 1.
var wave: int = 1
## The player figure.
var hero: StickFigure
## Live and fallen gunmen of the current wave.
var gunmen: Array[Gunman] = []
## Bullets in flight or hanging.
var bullets: Array[Bullet] = []

var _dragging: bool = false
var _drag_px: float = 0.0
var _fire_cooldown: float = 0.0
var _wave_clearing: bool = false

@onready var _camera: Camera2D = $Camera
@onready var _hud: Hud = $Hud


func _ready() -> void:
	hero = StickFigure.new()
	hero.color = CYAN
	add_child(hero)
	_restart()
	if "--smoke" in OS.get_cmdline_user_args():
		var bot := SmokeBot.new()
		bot.main = self
		add_child(bot)


func _process(delta: float) -> void:
	var dt: float = minf(delta, MAX_DT)
	_update_flow(dt)
	_hud.set_flow(time_flow)
	if state != State.PLAYING:
		return
	var world_dt: float = dt * time_flow
	_tick_gunmen(world_dt)
	_tick_hero_fire(world_dt)
	_tick_bullets(world_dt)
	_check_wave_clear()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index != MOUSE_BUTTON_LEFT:
			return
		if button.pressed and state == State.LOST:
			_restart()
		elif button.pressed and button.position.y >= ZONE_TOP:
			_dragging = true
			_hud.dismiss_hint()
		elif not button.pressed:
			_dragging = false
	elif event is InputEventMouseMotion and _dragging and state == State.PLAYING:
		var motion := event as InputEventMouseMotion
		_move_hero(motion.relative * DRAG_SCALE)
		_drag_px += motion.relative.length()
	elif event is InputEventKey and event.pressed and not event.echo and state == State.LOST:
		_restart()


## Kills a gunman with hit stop, camera punch, and a particle burst.
func kill_gunman(gunman: Gunman) -> void:
	gunman.die()
	_burst(gunman.position + BODY_OFFSET)
	_hit_stop()
	_punch(KILL_PUNCH_ZOOM, 0.2)


func _update_flow(dt: float) -> void:
	var target: float = clampf(_drag_px / dt / REF_SPEED, 0.0, 1.0)
	_drag_px = 0.0
	var key_dir: Vector2 = _read_key_dir()
	if key_dir != Vector2.ZERO and state == State.PLAYING:
		_move_hero(key_dir * KEY_SPEED * dt)
		_hud.dismiss_hint()
		target = 1.0
	# Rise instantly so the thumb feels direct. Fall fast so a stop reads as a freeze.
	time_flow = target if target > time_flow else maxf(target, time_flow - FLOW_DECAY * dt)
	if state != State.PLAYING:
		time_flow = 0.0


func _read_key_dir() -> Vector2:
	var dir := Vector2.ZERO
	dir.x = float(Input.is_physical_key_pressed(KEY_RIGHT) or Input.is_physical_key_pressed(KEY_D)) \
		- float(Input.is_physical_key_pressed(KEY_LEFT) or Input.is_physical_key_pressed(KEY_A))
	dir.y = float(Input.is_physical_key_pressed(KEY_DOWN) or Input.is_physical_key_pressed(KEY_S)) \
		- float(Input.is_physical_key_pressed(KEY_UP) or Input.is_physical_key_pressed(KEY_W))
	return dir.normalized()


func _move_hero(offset: Vector2) -> void:
	var moved: Vector2 = hero.position + offset
	hero.position = moved.clamp(HERO_BOUNDS.position, HERO_BOUNDS.end)


func _tick_gunmen(world_dt: float) -> void:
	for gunman: Gunman in gunmen:
		if not gunman.alive:
			continue
		if gunman.tick(world_dt, hero.position + BODY_OFFSET):
			var muzzle: Vector2 = gunman.position + Vector2(0.0, -32.0) + Vector2.from_angle(gunman.aim_angle) * 26.0
			var aim: Vector2 = (hero.position + BODY_OFFSET - muzzle).normalized()
			_spawn_bullet(muzzle, aim * GUNMAN_BULLET_SPEED, AMBER, true)


func _tick_hero_fire(world_dt: float) -> void:
	var target: Gunman = _nearest_gunman()
	if target == null:
		return
	var origin: Vector2 = hero.position + Vector2(0.0, -32.0)
	var aim: Vector2 = target.position + BODY_OFFSET - origin
	hero.aim_at(aim.angle())
	_fire_cooldown -= world_dt
	if _fire_cooldown <= 0.0 and time_flow > 0.05:
		_fire_cooldown = FIRE_COOLDOWN
		_spawn_bullet(origin + aim.normalized() * 26.0, aim.normalized() * HERO_BULLET_SPEED, CYAN, false)


func _tick_bullets(world_dt: float) -> void:
	var bounds := Rect2(-40.0, -40.0, 620.0, 1040.0)
	for bullet: Bullet in bullets.duplicate():
		bullet.step(world_dt)
		if not bounds.has_point(bullet.position):
			_remove_bullet(bullet)
		elif bullet.hostile:
			if bullet.position.distance_to(hero.position + BODY_OFFSET) < HERO_HIT_RADIUS + BULLET_RADIUS:
				_lose()
				return
		else:
			for gunman: Gunman in gunmen:
				if gunman.alive and bullet.position.distance_to(gunman.position + BODY_OFFSET) < GUNMAN_HIT_RADIUS + BULLET_RADIUS:
					kill_gunman(gunman)
					_remove_bullet(bullet)
					break


func _check_wave_clear() -> void:
	if _wave_clearing or _nearest_gunman() != null:
		return
	_wave_clearing = true
	await get_tree().create_timer(0.7, true, false, true).timeout
	if state != State.PLAYING:
		return
	wave += 1
	_start_wave()


func _start_wave() -> void:
	_wave_clearing = false
	for gunman: Gunman in gunmen:
		gunman.queue_free()
	gunmen.clear()
	for bullet: Bullet in bullets.duplicate():
		_remove_bullet(bullet)
	var count: int = mini(START_GUNMEN + wave - 1, MAX_GUNMEN)
	var slots: Array[float] = [90.0, 180.0, 270.0, 360.0, 450.0]
	slots.shuffle()
	for i: int in count:
		var gunman := Gunman.new()
		gunman.color = MAGENTA
		add_child(gunman)
		gunman.setup(Vector2(slots[i], randf_range(150.0, 520.0)))
		gunmen.append(gunman)
	_hud.set_wave(wave)


func _restart() -> void:
	state = State.PLAYING
	wave = 1
	hero.position = HERO_START
	hero.set_pose(StickFigure.Pose.AIM)
	hero.aim_angle = -PI * 0.5
	_fire_cooldown = 0.0
	_dragging = false
	_drag_px = 0.0
	_hud.show_over(false)
	_start_wave()


func _lose() -> void:
	state = State.LOST
	hero.set_pose(StickFigure.Pose.FALL)
	_hud.show_over(true)
	_hit_stop()
	_punch(1.04, 0.3)


func _nearest_gunman() -> Gunman:
	var best: Gunman = null
	var best_dist: float = INF
	for gunman: Gunman in gunmen:
		var dist: float = gunman.position.distance_to(hero.position)
		if gunman.alive and dist < best_dist:
			best = gunman
			best_dist = dist
	return best


func _spawn_bullet(at: Vector2, velocity: Vector2, color: Color, hostile: bool) -> void:
	var bullet := Bullet.new()
	bullet.setup(at, velocity, color, hostile)
	add_child(bullet)
	bullets.append(bullet)


func _remove_bullet(bullet: Bullet) -> void:
	bullets.erase(bullet)
	bullet.queue_free()


func _hit_stop() -> void:
	Engine.time_scale = 0.05
	get_tree().create_timer(HIT_STOP, true, false, true).timeout.connect(func() -> void: Engine.time_scale = 1.0)


func _punch(zoom: float, duration: float) -> void:
	var tween := create_tween().set_ignore_time_scale(true)
	_camera.zoom = Vector2.ONE * zoom
	tween.tween_property(_camera, "zoom", Vector2.ONE, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _burst(at: Vector2) -> void:
	var particles := CPUParticles2D.new()
	particles.position = at
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.amount = 16
	particles.lifetime = 0.5
	particles.direction = Vector2.UP
	particles.spread = 180.0
	particles.initial_velocity_min = 90.0
	particles.initial_velocity_max = 260.0
	particles.gravity = Vector2(0.0, 500.0)
	particles.scale_amount_min = 2.0
	particles.scale_amount_max = 4.0
	particles.color = MAGENTA
	add_child(particles)
	particles.emitting = true
	get_tree().create_timer(1.0, true, false, true).timeout.connect(particles.queue_free)


func _draw() -> void:
	draw_line(Vector2(0.0, ZONE_TOP), Vector2(540.0, ZONE_TOP), Color(INK, 0.12), 2.0)
