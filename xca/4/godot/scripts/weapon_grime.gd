class_name WeaponGrime
extends RefCounted
## Dirt on each weapon. Shots add it, scrubbing at the calm station removes it.
##
## Dirt slows the weapon, so cleaning pays back at once. A full clean gives a short bonus, so the station feels like a reward and not a chore.

## Grime a shot or swing adds, on a scale from 0 (clean) to 1 (filthy). A pistol is full in about 45 s of steady fire.
const PER_SHOT: float = 0.006
## Extra seconds a filthy weapon waits between shots, as a share of the base interval. 0.667 cuts the fire rate by 40 percent.
const MAX_SLOWDOWN: float = 0.667
## Grime one scrub reversal (one stroke back or forth) removes. A full clean takes about 15 strokes.
const PER_REVERSAL: float = 0.07
## Seconds the full-power bonus lasts.
const BONUS_SECONDS: float = 8.0
## Interval scale during the bonus. Below 1 means faster than a new weapon.
const BONUS_SCALE: float = 0.8
## Grime a weapon needs before a clean earns a bonus, so a spotless weapon cannot farm it.
const BONUS_MIN_GRIME: float = 0.3

## Weapon that holds the bonus, or empty.
var bonus_weapon: StringName = &""
## Seconds of bonus left.
var bonus_remaining: float = 0.0

var _levels: Dictionary[StringName, float] = {}


## Returns the grime of a weapon from 0 to 1.
func level(id: StringName) -> float:
	return _levels.get(id, 0.0)


## Adds the grime of one shot or swing.
func add_shot(id: StringName) -> void:
	_levels[id] = minf(level(id) + PER_SHOT, 1.0)


## Removes grime for a number of scrub reversals. Returns true when this call made the weapon spotless.
## A weapon that was dirty enough starts the bonus.
func scrub(id: StringName, reversals: int) -> bool:
	var before: float = level(id)
	if before <= 0.0 or reversals <= 0:
		return false
	var after: float = maxf(before - PER_REVERSAL * float(reversals), 0.0)
	_levels[id] = after
	if after > 0.0:
		return false
	if before >= BONUS_MIN_GRIME or bonus_weapon == id:
		bonus_weapon = id
		bonus_remaining = BONUS_SECONDS
	return true


## Returns the factor that multiplies the wait between shots of a weapon.
func interval_scale(id: StringName) -> float:
	if bonus_remaining > 0.0 and bonus_weapon == id:
		return BONUS_SCALE
	return 1.0 + MAX_SLOWDOWN * level(id)


## Ages the bonus. The shooter calls it every frame, so the bonus holds while the run is paused.
func tick(delta: float) -> void:
	if bonus_remaining > 0.0:
		bonus_remaining = maxf(bonus_remaining - delta, 0.0)


## Cleans every weapon and ends the bonus, for a new run.
func reset() -> void:
	_levels.clear()
	bonus_weapon = &""
	bonus_remaining = 0.0
