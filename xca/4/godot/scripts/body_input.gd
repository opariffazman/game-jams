class_name BodyInput
extends PlayerInput
## Turns the aim point that page JavaScript publishes on window.railsBridge into a relative "air trackpad" reticle.
##
## The page sends the raw point where the index finger points, and the hand pose as an action code. This node applies
## the gain first, then smooths with a One Euro filter, then interpolates the roughly 12 per second updates to the frame rate.
## The first sight of a hand sets an anchor. After that the reticle moves by the hand movement from the anchor times a gain.
## The anchor stays put when the hand drops out, so a returning hand slides back instead of snapping.

## Name of the object on window that the page script fills.
const BRIDGE_NAME: String = "railsBridge"
## Seconds between the numbers this node writes back for the page readout.
const READOUT_INTERVAL: float = 0.25
## Reticle travel per unit of aim travel.
const DEFAULT_GAIN_X: float = 2.0
## Default vertical gain. Higher because the hand moves less up and down.
const DEFAULT_GAIN_Y: float = 2.4
## Seconds a lost hand keeps its last aim before the hand counts as gone.
const HOLD_SECONDS: float = 0.5
## Seconds the aim takes to slide to a hand that comes back after a dropout.
const SLIDE_SECONDS: float = 0.3
## Seconds the aim takes to settle after the hand leaves a palm or fist pose.
const POSE_SETTLE_SECONDS: float = 0.2
## One Euro tuning in screen units. A low cutoff hides the jitter while the hand rests, and beta lets a fast swipe through.
const FILTER_MIN_CUTOFF: float = 1.0
const FILTER_BETA: float = 1.5
## Bounds on the span of one interpolation segment, so a late update does not stall or rush the reticle.
const MIN_SEGMENT_SECONDS: float = 0.05
const MAX_SEGMENT_SECONDS: float = 0.25
## Consecutive tracker updates a pose must hold to trigger, and consecutive updates without it to arm again.
const POSE_HOLD_UPDATES: int = 3
const POSE_RELEASE_UPDATES: int = 2
## Starting value of the lost timer, large so a slot counts as lost until its first hand.
const NEVER_SEEN_SECONDS: float = 99.0
const CENTRE: Vector2 = Vector2(0.5, 0.5)

## How the lane follows the hand. A flick moves one lane per flick. A slide follows the hand position.
enum SteerMode { FLICK, SLIDE }

## Hand pose codes the page sends. They match ACTION_* in tracker.js.
enum Pose { NONE, PALM, FIST }

## Emitted once when an open palm has been held for a few updates. It rearms after the palm goes away.
signal palm_triggered(slot: int)
## Emitted once when a fist has been held for a few updates. It rearms after the fist opens.
signal fist_triggered(slot: int)
## Emitted when a hand appears after none, or all hands disappear, for the found and lost chimes.
signal hand_seen_changed(seen: bool)
## Emitted for each flick event of the tracker. Direction is -1 for left or up and 1 for right or down.
signal flick_horizontal(direction: int)
signal flick_vertical(direction: int)

## Hand slide position from 0 (left) to 1 (right), already mirrored, or -1 when no hand is seen. Slide mode reads it.
var slide: float = -1.0
## Two-hand data [distance, angle, midX, midY] of the latest update, or empty when fewer than two hands are seen.
var two_hand: Array = []
## True while the tracker sees two open palms facing the camera. It needs the tracker in two-hand mode.
var two_palms: bool = false
## Scrub reversal counter of the tracker. A rise means a back-and-forth scrub.
var scrub_count: int = 0
## Flick events counted since start, for the readout and tests.
var flicks_received: int = 0
## Margin in slide units a hand must cross past a lane border before the lane changes. It stops flutter on the border.
const SLIDE_HYSTERESIS: float = 0.06

## Count of hands the tracker sees right now.
var hand_count: int = 0
## Count of tracker updates that reached this node since start.
var updates_received: int = 0
## Whether camera control is switched on. Touch and mouse aim work either way.
var magic: bool = false
## Name of the browser error when the camera could not open, such as NotAllowedError inside an iframe without camera permission. Empty when there is none.
var camera_error: String = ""
## Whether a hand has been seen since camera control was switched on, for the "show your hand" guide.
var hands_ever_seen: bool = false
## Reticle gain per axis.
var gain_x: float = DEFAULT_GAIN_X
var gain_y: float = DEFAULT_GAIN_Y
## Palm size, gesture scores and finger ratios of slot 0 from the latest update.
var palm_size: float = 0.0
var fist_score: float = 0.0
var fist_ratio: float = 0.0
var palm_score: float = 0.0
var palm_ratio: float = 0.0
## Pose of slot 0 in the latest update.
var current_pose: Pose = Pose.NONE
## Counters and positions the scene sets so the page readout can show them.
var shots_fired: int = 0
var shots_hit: int = 0
var zombies_active: int = 0
var assist_locked: bool = false
var reticle_point: Vector2 = CENTRE
## Seconds left on the grenade and melee cooldowns, set by the scene for the page readout.
var grenade_cooldown: float = 0.0
var melee_cooldown: float = 0.0
## Name of the intro step, for the readout and tests.
var flow: String = ""
## Id of the hero shown or picked, for the readout and tests.
var hero_id: String = ""
## Hearts left, for the readout and tests.
var hearts: int = 0
## Lane, weapon, distance and chain of the run, for the readout and tests.
var lane: int = 0
var weapon_id: String = ""
var run_distance: float = 0.0
var combo: int = 0
## Play calls counted by the audio node, for the readout.
## Current volume of each music layer in dB, for the readout and tests.
var audio_layers: String = ""
## Station state for the page readout and tests: open flag, grime of the weapon in hand, viewer zoom and yaw.
var inspect_open: bool = false
var grime_level: float = 0.0
var inspect_zoom: float = 1.0
var inspect_yaw: float = 0.0
var audio_plays: int = 0
## Largest and mean reticle step in pixels per frame over the last second.
var step_max: float = 0.0
var step_mean: float = 0.0

var _bridge: JavaScriptObject
var _last_seq: int = -1
var _last_frame: int = -1
var _last_gesture_count: int = -1
var _steer_mode: SteerMode = SteerMode.FLICK
var _readout_timer: float = 0.0
var _anchors: Array[Vector2] = [CENTRE, CENTRE, CENTRE, CENTRE]
var _hand_raw: Array[Vector2] = [CENTRE, CENTRE, CENTRE, CENTRE]
var _filters: Array[OneEuroFilter] = []
var _since_update: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _slide_left: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _segment_from: Array[Vector2] = [CENTRE, CENTRE, CENTRE, CENTRE]
var _segment_to: Array[Vector2] = [CENTRE, CENTRE, CENTRE, CENTRE]
var _segment_elapsed: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _segment_length: Array[float] = [MIN_SEGMENT_SECONDS, MIN_SEGMENT_SECONDS, MIN_SEGMENT_SECONDS, MIN_SEGMENT_SECONDS]
var _aim_points: Array[Vector2] = [CENTRE, CENTRE, CENTRE, CENTRE]
var _anchored: Array[bool] = [false, false, false, false]
var _lost_seconds: Array[float] = [NEVER_SEEN_SECONDS, NEVER_SEEN_SECONDS, NEVER_SEEN_SECONDS, NEVER_SEEN_SECONDS]
var _poses: Array[Pose] = [Pose.NONE, Pose.NONE, Pose.NONE, Pose.NONE]
var _pose_streak: Array[int] = [0, 0, 0, 0]
var _release_streak: Array[int] = [0, 0, 0, 0]
var _triggered_pose: Array[Pose] = [Pose.NONE, Pose.NONE, Pose.NONE, Pose.NONE]
var _streak_pose: Array[Pose] = [Pose.NONE, Pose.NONE, Pose.NONE, Pose.NONE]
var _was_seen: bool = false
var _packed_palm_size: float = 0.0
var _packed_fist_score: float = 0.0
var _packed_fist_ratio: float = 0.0
var _packed_palm_score: float = 0.0
var _packed_palm_ratio: float = 0.0


func _init() -> void:
	for _slot: int in MAX_SLOTS:
		_filters.append(OneEuroFilter.new(FILTER_MIN_CUTOFF, FILTER_BETA))


func _ready() -> void:
	auto_fire = true
	if OS.has_feature("web"):
		_bridge = JavaScriptBridge.get_interface(BRIDGE_NAME)


func _process(delta: float) -> void:
	if _bridge == null:
		return
	var seq: int = int(_bridge.seq)
	if seq != _last_seq:
		_last_seq = seq
		updates_received += 1
		_read_packed(String(_bridge.packed))
	advance(delta)
	_readout_timer -= delta
	if _readout_timer <= 0.0:
		_readout_timer = READOUT_INTERVAL
		_write_readout(delta)


## Moves the aim along its segment and ages the lost timers. Called every frame, and by tests with a fixed step.
func advance(delta: float) -> void:
	var seen: bool = is_any_aiming()
	if seen != _was_seen:
		_was_seen = seen
		hand_seen_changed.emit(seen)
	for slot: int in MAX_SLOTS:
		_lost_seconds[slot] = minf(_lost_seconds[slot] + delta, NEVER_SEEN_SECONDS)
		_since_update[slot] += delta
		_slide_left[slot] = maxf(_slide_left[slot] - delta, 0.0)
		if _anchored[slot]:
			_segment_elapsed[slot] += delta
			var progress: float = clampf(_segment_elapsed[slot] / _segment_length[slot], 0.0, 1.0)
			_aim_points[slot] = _segment_from[slot].lerp(_segment_to[slot], progress)


## Tells the tracker how to report steering. Flick is the default. Slide reports the hand position in thirds.
func set_steer_mode(mode: SteerMode) -> void:
	_steer_mode = mode
	if _bridge != null:
		_bridge.setSteerMode("slide" if mode == SteerMode.SLIDE else "flick")


## Returns the current steer mode.
func get_steer_mode() -> SteerMode:
	return _steer_mode


## Returns the lane a slide position selects. The current lane holds until the hand passes its border by the hysteresis margin.
## Returns the current lane when no hand is seen, so losing the hand never moves the hero.
static func slide_to_lane(slide_value: float, current: int, lane_count: int) -> int:
	if slide_value < 0.0:
		return current
	var lane_width: float = 1.0 / float(lane_count)
	var low: float = float(current) * lane_width - SLIDE_HYSTERESIS
	var high: float = float(current + 1) * lane_width + SLIDE_HYSTERESIS
	if slide_value >= low and slide_value <= high:
		return current
	return clampi(int(slide_value / lane_width), 0, lane_count - 1)


## Switches camera control on or off. The page starts or pauses the tracker.
func set_magic(on: bool) -> void:
	if on == magic:
		return
	magic = on
	hands_ever_seen = false
	recenter()
	if _bridge != null:
		_bridge.setMagic(on)


## Drops every anchor so the next sighting anchors on the hand, as the Recenter button does.
func recenter() -> void:
	reset_anchors()


## Drops every anchor.
func reset_anchors() -> void:
	for slot: int in MAX_SLOTS:
		_reset_slot(slot)
		_lost_seconds[slot] = NEVER_SEEN_SECONDS


## Returns whether any slot has a hand to aim with.
func is_any_aiming() -> bool:
	for slot: int in MAX_SLOTS:
		if is_aiming(slot):
			return true
	return false


## Returns the camera-space aim point of the slot hand, mirrored like the preview, for the corner mini-map.
func get_hand_position(slot: int) -> Vector2:
	return _hand_raw[slot]


## Returns the aim point before aim assist, for the readout and tests.
func get_raw_aim(slot: int) -> Vector2:
	return _aim_points[slot]


## One player means one reticle. The slot arrays stay MAX_SLOTS long so the shared per-slot code needs no special case.
func get_slot_count() -> int:
	return 1


func is_aiming(slot: int) -> bool:
	return magic and _anchored[slot] and _lost_seconds[slot] < HOLD_SECONDS


func get_aim_point(slot: int) -> Vector2:
	return _aim_points[slot]


## Hands never fire by pose. They auto-fire on a lock, and the palm and fist poses trigger the extra attacks.
func is_firing(_slot: int) -> bool:
	return false


## Replaces the pose thresholds with the player's own. Scores are model scores, ratios are finger reach ratios.
func apply_pose_tuning(new_fist_score: float, new_fist_ratio: float, new_palm_score: float, new_palm_ratio: float) -> void:
	if _bridge != null:
		_bridge.setTuning(new_fist_score, new_fist_ratio, new_palm_score, new_palm_ratio)


## Feeds one packed update. Tests call it without a bridge.
func feed(packed: String) -> void:
	_read_packed(packed)


## One call per tracker update replaces about ten bridge reads per frame, which are slow in single-threaded web builds.
func _read_packed(packed: String) -> void:
	if packed.is_empty():
		return
	var data: Variant = JSON.parse_string(packed)
	if not data is Dictionary:
		return
	camera_error = String(data.get("ce", ""))
	var page_magic: bool = int(data.get("m", 0)) == 1
	if page_magic != magic:
		magic = page_magic
		hands_ever_seen = false
		recenter()
	tracking_ok = bool(data.get("ok", false))
	var frame: int = int(data.get("f", 0))
	if frame == _last_frame:
		return
	_last_frame = frame
	_packed_palm_size = float(data.get("ps", 0.0))
	_packed_fist_score = float(data.get("gs", 0.0))
	_packed_fist_ratio = float(data.get("fr", 0.0))
	_packed_palm_score = float(data.get("pg", 0.0))
	_packed_palm_ratio = float(data.get("pr", 0.0))
	hand_count = clampi(int(data.get("n", 0)), 0, MAX_SLOTS)
	_read_gestures(data)
	if not magic:
		return
	var slots: Array = data.get("s", [])
	for slot: int in MAX_SLOTS:
		if slot >= hand_count or slot >= slots.size():
			_pose_streak[slot] = 0
			_release_streak[slot] = 0
			if slot == 0:
				current_pose = Pose.NONE
			continue
		var entry: Array = slots[slot]
		_on_hand(slot, Vector2(float(entry[0]), float(entry[1])), int(entry[2]) as Pose)


## Tolerates a tracker that does not send the gesture fields yet. A missing field keeps the old value.
func _read_gestures(data: Dictionary) -> void:
	slide = float(data.get("sl", -1.0))
	var thumb: Variant = data.get("th", null)
	two_hand = thumb if thumb is Array and (thumb as Array).size() >= 4 else []
	scrub_count = int(data.get("sr", scrub_count))
	two_palms = int(data.get("tp", 0)) == 1
	if not data.has("gn"):
		return
	var count: int = int(data["gn"])
	# The first update only sets the baseline, so events from before this session never fire.
	if _last_gesture_count < 0:
		_last_gesture_count = count
		return
	if count <= _last_gesture_count:
		_last_gesture_count = count
		return
	_last_gesture_count = count
	flicks_received += 1
	match String(data.get("gk", "")):
		"l":
			flick_horizontal.emit(-1)
		"r":
			flick_horizontal.emit(1)
		"u":
			flick_vertical.emit(-1)
		"d":
			flick_vertical.emit(1)


func _on_hand(slot: int, hand: Vector2, pose: Pose) -> void:
	_hand_raw[slot] = hand
	if slot == 0:
		palm_size = _packed_palm_size
		fist_score = _packed_fist_score
		fist_ratio = _packed_fist_ratio
		palm_score = _packed_palm_score
		palm_ratio = _packed_palm_ratio
		current_pose = pose
	var interval: float = clampf(_since_update[slot], MIN_SEGMENT_SECONDS, MAX_SEGMENT_SECONDS)
	_since_update[slot] = 0.0
	var returning: bool = _anchored[slot] and _lost_seconds[slot] >= HOLD_SECONDS
	_lost_seconds[slot] = 0.0
	hands_ever_seen = true
	if not _anchored[slot]:
		_anchor_slot(slot, hand)
	var from_anchor: Vector2 = hand - _anchors[slot]
	var gained: Vector2 = (CENTRE + Vector2(from_anchor.x * gain_x, from_anchor.y * gain_y)).clamp(Vector2.ZERO, Vector2.ONE)
	# The filter runs after the gain, so its cutoff is in screen units and matches what the player sees.
	if returning:
		_filters[slot].reset()
	var smooth: Vector2 = _filters[slot].filter(gained, interval)
	# A slide keeps its remaining time across updates, so the next update retargets it instead of cutting it short.
	if returning:
		_slide_left[slot] = SLIDE_SECONDS
	elif _poses[slot] != Pose.NONE and pose == Pose.NONE:
		_slide_left[slot] = maxf(_slide_left[slot], POSE_SETTLE_SECONDS)
	var length: float = maxf(interval, _slide_left[slot])
	_poses[slot] = pose
	_segment_from[slot] = _aim_points[slot]
	_segment_to[slot] = smooth
	_segment_elapsed[slot] = 0.0
	_segment_length[slot] = length
	_track_pose(slot, pose)


## Sets the anchor on the first sight, so the hand starts at the centre of the aim.
func _anchor_slot(slot: int, hand: Vector2) -> void:
	_anchors[slot] = hand
	_anchored[slot] = true
	_filters[slot].reset()
	var start: Vector2 = CENTRE
	_aim_points[slot] = start
	_segment_from[slot] = start
	_segment_to[slot] = start


## A pose triggers after a few updates in a row and rearms only after the hand leaves it for a few updates.
func _track_pose(slot: int, pose: Pose) -> void:
	if pose != Pose.NONE and pose == _triggered_pose[slot]:
		_release_streak[slot] = 0
		return
	_release_streak[slot] += 1
	if _release_streak[slot] >= POSE_RELEASE_UPDATES:
		_triggered_pose[slot] = Pose.NONE
	if pose == Pose.NONE:
		_pose_streak[slot] = 0
		return
	_pose_streak[slot] = _pose_streak[slot] + 1 if pose == _streak_pose[slot] else 1
	_streak_pose[slot] = pose
	if _pose_streak[slot] < POSE_HOLD_UPDATES or _triggered_pose[slot] != Pose.NONE:
		return
	_triggered_pose[slot] = pose
	_release_streak[slot] = 0
	if pose == Pose.PALM:
		palm_triggered.emit(slot)
	else:
		fist_triggered.emit(slot)


func _reset_slot(slot: int) -> void:
	_anchored[slot] = false
	_aim_points[slot] = CENTRE
	_segment_from[slot] = CENTRE
	_segment_to[slot] = CENTRE
	_poses[slot] = Pose.NONE
	_slide_left[slot] = 0.0
	_pose_streak[slot] = 0
	_streak_pose[slot] = Pose.NONE
	_triggered_pose[slot] = Pose.NONE
	_filters[slot].reset()


func _write_readout(delta: float) -> void:
	_bridge.godotSeenSeq = _last_seq
	_bridge.godotFps = Engine.get_frames_per_second()
	_bridge.godotFrameMs = delta * 1000.0
	_bridge.godotShots = shots_fired
	_bridge.godotFlow = flow
	_bridge.godotAudioLayers = audio_layers
	_bridge.godotInspect = 1 if inspect_open else 0
	_bridge.godotGrime = grime_level
	_bridge.godotInspectZoom = inspect_zoom
	_bridge.godotInspectYaw = inspect_yaw
	_bridge.godotHero = hero_id
	_bridge.godotHearts = hearts
	_bridge.godotAudio = audio_plays
	_bridge.godotStepMax = step_max
	_bridge.godotStepMean = step_mean
	_bridge.godotHits = shots_hit
	_bridge.godotZombies = zombies_active
	_bridge.godotAssist = 1 if assist_locked else 0
	_bridge.godotAimX = _aim_points[0].x
	_bridge.godotAimY = _aim_points[0].y
	_bridge.godotAssistX = reticle_point.x
	_bridge.godotAssistY = reticle_point.y
	_bridge.godotGrenadeCd = grenade_cooldown
	_bridge.godotPunchCd = melee_cooldown
	_bridge.godotFlicks = flicks_received
	_bridge.godotLane = lane
	_bridge.godotWeapon = weapon_id
	_bridge.godotDistance = run_distance
	_bridge.godotCombo = combo
