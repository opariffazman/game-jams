class_name OneEuroFilter
extends RefCounted
## One Euro filter (Casiez et al. 2012) for a 2D point. It smooths hard while the hand rests and follows fast moves.
##
## Speed is the length of the velocity vector, so both axes share one cutoff and the filtered path keeps its direction.

var min_cutoff: float = 1.0
var beta: float = 1.5
var derivative_cutoff: float = 1.0

var _value: Vector2 = Vector2.ZERO
var _derivative: Vector2 = Vector2.ZERO
var _raw: Vector2 = Vector2.ZERO
var _primed: bool = false


func _init(new_min_cutoff: float = 1.0, new_beta: float = 1.5) -> void:
	min_cutoff = new_min_cutoff
	beta = new_beta


## Forgets the history, so the next sample passes through unchanged.
func reset() -> void:
	_primed = false


## Filters one sample that arrived delta seconds after the previous one.
func filter(sample: Vector2, delta: float) -> Vector2:
	if not _primed:
		_primed = true
		_value = sample
		_raw = sample
		_derivative = Vector2.ZERO
		return sample
	var step: float = maxf(delta, 0.001)
	var rate: Vector2 = (sample - _raw) / step
	_raw = sample
	_derivative = _derivative.lerp(rate, _alpha(derivative_cutoff, step))
	var cutoff: float = min_cutoff + beta * _derivative.length()
	_value = _value.lerp(sample, _alpha(cutoff, step))
	return _value


static func _alpha(cutoff: float, step: float) -> float:
	var time_constant: float = 1.0 / (TAU * cutoff)
	return 1.0 / (1.0 + time_constant / step)
