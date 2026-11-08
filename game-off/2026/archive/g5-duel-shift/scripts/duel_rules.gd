class_name DuelRules
extends RefCounted
## Pure duel rules: stances, tells, hit test, seeded tell order, tell timing.

## Hero stance. CENTER is neutral.
enum Stance { CENTER, LEFT, RIGHT, DUCK }
## Boss telegraph kinds.
enum Tell { LEFT, RIGHT, CENTER, HIGH }

## Telegraph words, indexed by [enum Tell].
const TELL_WORDS: Array[String] = ["LEFT SHOT", "RIGHT SHOT", "CENTER SHOT", "HIGH SHOT"]
## Longest run of identical tells.
const MAX_REPEAT: int = 2
## Tell time on the first round, seconds.
const TELL_SLOWEST: float = 0.7
## Tell time from round 6 on, seconds.
const TELL_FASTEST: float = 0.4

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _last: Array[int] = []


func _init(seed_value: int = 1) -> void:
	_rng.seed = seed_value


## Returns true when [param tell] hits a hero in [param stance].
static func is_hit(tell: Tell, stance: Stance) -> bool:
	match tell:
		Tell.LEFT:
			return stance == Stance.LEFT
		Tell.RIGHT:
			return stance == Stance.RIGHT
		Tell.CENTER:
			return stance == Stance.CENTER
		_:
			return stance != Stance.DUCK


## Returns a stance that dodges [param tell].
static func safe_stance(tell: Tell) -> Stance:
	match tell:
		Tell.LEFT:
			return Stance.RIGHT
		Tell.RIGHT:
			return Stance.LEFT
		_:
			return Stance.DUCK


## Returns a stance that is hit by [param tell].
static func hit_stance(tell: Tell) -> Stance:
	match tell:
		Tell.LEFT:
			return Stance.LEFT
		Tell.RIGHT:
			return Stance.RIGHT
		_:
			return Stance.CENTER


## Returns the tell time for a zero-based [param round_index].
static func tell_duration(round_index: int) -> float:
	return lerpf(TELL_SLOWEST, TELL_FASTEST, clampf(round_index / 5.0, 0.0, 1.0))


## Returns the next tell. Never more than [constant MAX_REPEAT] identical in a row.
func next_tell() -> Tell:
	var pick: int = _rng.randi_range(0, Tell.size() - 1)
	while _last.size() >= MAX_REPEAT and _last.all(func(t: int) -> bool: return t == pick):
		pick = _rng.randi_range(0, Tell.size() - 1)
	_last.append(pick)
	if _last.size() > MAX_REPEAT:
		_last.pop_front()
	return pick as Tell
