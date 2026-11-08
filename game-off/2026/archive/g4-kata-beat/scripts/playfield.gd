class_name Playfield
extends Node2D
## Lower half: lanes, falling notes, the hit line and the three big pads.

## Y of the hit line, just above the pads.
const HIT_Y: float = 548.0
## Y where notes appear.
const SPAWN_Y: float = 340.0
## Top of the pads. The bottom 40 percent of the screen.
const PAD_TOP: float = 576.0
## Width of one lane.
const LANE_W: float = 180.0
## Seconds a note takes to fall from spawn to the hit line.
const APPROACH: float = 1.0
const PAD_NAMES: PackedStringArray = ["PUNCH", "KICK", "SHOOT"]
const PAD_KEYS: PackedStringArray = ["A / J", "S / K", "D / L"]

## Current song time in seconds. Set by the main script each frame.
var song_time: float = 0.0
## Note times in seconds. Shared with the main script.
var times: PackedFloat32Array = PackedFloat32Array()
## Note lanes. Shared with the main script.
var lanes: PackedInt32Array = PackedInt32Array()
## Note status bytes, 0 means pending. Shared with the main script.
var status: PackedByteArray = PackedByteArray()
## Pad flash strength per lane, 1 right after a tap.
var pad_flash: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0])


## Decays the pad flashes and redraws.
func advance(delta: float) -> void:
	for lane in 3:
		pad_flash[lane] = maxf(0.0, pad_flash[lane] - delta * 6.0)
	queue_redraw()


## Returns the lane under [param pos], or -1 outside the pads.
static func lane_at(pos: Vector2) -> int:
	if pos.y < PAD_TOP or pos.x < 0.0 or pos.x >= LANE_W * 3.0:
		return -1
	return int(pos.x / LANE_W)


func _draw() -> void:
	draw_rect(Rect2(0, SPAWN_Y - 10.0, 540, 960), Color("0e0e15"))
	for lane in 3:
		var cx: float = lane * LANE_W + LANE_W * 0.5
		if lane > 0:
			draw_line(Vector2(lane * LANE_W, SPAWN_Y - 10.0), Vector2(lane * LANE_W, 960), Color(1, 1, 1, 0.08), 2.0)
		_draw_lane_shape(lane, Vector2(cx, HIT_Y), 24.0, Kata.lane_colors[lane], false, 3.0)
	var beat_pulse: float = exp(-fposmod(song_time / Kata.BEAT, 1.0) * 7.0)
	draw_line(Vector2(0, HIT_Y), Vector2(540, HIT_Y), Color(Kata.INK, 0.45 + 0.4 * beat_pulse), 3.0 + 2.0 * beat_pulse)
	_draw_notes()
	_draw_pads()


func _draw_notes() -> void:
	var travel: float = HIT_Y - SPAWN_Y
	for i in times.size():
		var dt: float = times[i] - song_time
		if dt > APPROACH:
			break
		if status[i] != 0 or dt < -0.2:
			continue
		var y: float = HIT_Y - dt / APPROACH * travel
		var alpha: float = clampf((y - SPAWN_Y) / 40.0, 0.0, 1.0)
		var center: Vector2 = Vector2(lanes[i] * LANE_W + LANE_W * 0.5, y)
		_draw_lane_shape(lanes[i], center, 22.0, Color(Kata.lane_colors[lanes[i]], alpha), true)
		_draw_lane_shape(lanes[i], center, 22.0, Color(Kata.INK, alpha * 0.9), false, 2.5)


func _draw_pads() -> void:
	var font: Font = ThemeDB.fallback_font
	for lane in 3:
		var color: Color = Kata.lane_colors[lane]
		var rect: Rect2 = Rect2(lane * LANE_W + 6.0, PAD_TOP, LANE_W - 12.0, 960.0 - PAD_TOP - 6.0)
		draw_rect(rect, Color(color, 0.14 + 0.5 * pad_flash[lane]))
		draw_rect(rect, color, false, 3.0)
		var cx: float = rect.position.x + rect.size.x * 0.5
		_draw_lane_shape(lane, Vector2(cx, 690.0), 44.0, Color(color, 0.6 + 0.4 * pad_flash[lane]), true)
		draw_string(font, Vector2(rect.position.x, 818.0), PAD_NAMES[lane], HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 28, Kata.INK)
		draw_string(font, Vector2(rect.position.x, 856.0), PAD_KEYS[lane], HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 20, Color(Kata.INK, 0.7))


func _draw_lane_shape(lane: int, center: Vector2, radius: float, color: Color, filled: bool, width: float = 3.0) -> void:
	match lane:
		Kata.Lane.PUNCH:
			if filled:
				draw_circle(center, radius, color)
			else:
				draw_arc(center, radius, 0.0, TAU, 32, color, width, true)
		Kata.Lane.KICK:
			var rect: Rect2 = Rect2(center - Vector2(radius, radius), Vector2(radius, radius) * 2.0)
			if filled:
				draw_rect(rect, color)
			else:
				draw_rect(rect, color, false, width)
		_:
			var points: PackedVector2Array = PackedVector2Array([
				center + Vector2(0, -radius), center + Vector2(radius, radius * 0.8), center + Vector2(-radius, radius * 0.8)])
			if filled:
				draw_colored_polygon(points, color)
			else:
				points.append(points[0])
				draw_polyline(points, color, width, true)
