class_name Synth
extends RefCounted
## Builds every sound in code as [AudioStreamWAV]. No audio files are imported.

## Sample rate in Hz. Low on purpose so the build stays fast on web.
const RATE: int = 22050
## Sound index for a miss. Lane sounds use the [enum Kata.Lane] values.
const MISS_SOUND: int = 3


## Builds the whole backing track: a kick on every beat and a hi-hat on every off-beat.
static func make_backing() -> AudioStreamWAV:
	var bar: PackedFloat32Array = PackedFloat32Array()
	bar.resize(int(Kata.BAR * RATE))
	var kick: PackedFloat32Array = _tone(0.22, 150.0, 45.0, 28.0, 14.0, 0, 0.0, 0.9)
	var hat: PackedFloat32Array = _tone(0.05, 100.0, 100.0, 1.0, 70.0, 0, 1.0, 0.5)
	for beat in 4:
		_mix(bar, kick, int(beat * Kata.BEAT * RATE))
		_mix(bar, hat, int((beat + 0.5) * Kata.BEAT * RATE))
	var bar_bytes: PackedByteArray = _to_bytes(bar)
	var track: PackedByteArray = PackedByteArray()
	for i in Kata.TRACK_BARS:
		track.append_array(bar_bytes)
	return _to_stream(track)


## Builds the short sound for a [enum Kata.Lane] hit, or [constant MISS_SOUND].
static func make_hit(sound: int) -> AudioStreamWAV:
	var samples: PackedFloat32Array
	match sound:
		Kata.Lane.PUNCH:
			samples = _tone(0.1, 340.0, 90.0, 22.0, 26.0, 0, 0.35, 0.8)
		Kata.Lane.KICK:
			samples = _tone(0.14, 260.0, 70.0, 16.0, 20.0, 1, 0.1, 0.45)
		Kata.Lane.SHOOT:
			samples = _tone(0.16, 1900.0, 260.0, 16.0, 17.0, 2, 0.4, 0.5)
		_:
			samples = _tone(0.14, 110.0, 60.0, 8.0, 18.0, 0, 0.0, 0.7)
	return _to_stream(_to_bytes(samples))


## Wave 0 is sine, 1 is square, 2 is saw. [param noise] blends in high-passed noise.
static func _tone(seconds: float, f_start: float, f_end: float, sweep: float, decay: float, wave: int, noise: float, gain: float) -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(int(seconds * RATE))
	var phase: float = 0.0
	var prev_noise: float = 0.0
	for i in out.size():
		var t: float = float(i) / RATE
		phase += TAU * (f_end + (f_start - f_end) * exp(-t * sweep)) / RATE
		var tone: float
		match wave:
			1:
				tone = signf(sin(phase))
			2:
				tone = fmod(phase / TAU, 1.0) * 2.0 - 1.0
			_:
				tone = sin(phase)
		var raw: float = randf() * 2.0 - 1.0
		var hiss: float = (raw - prev_noise) * 0.5
		prev_noise = raw
		out[i] = (tone * (1.0 - noise) + hiss * noise) * exp(-t * decay) * gain
	return out


static func _mix(dst: PackedFloat32Array, src: PackedFloat32Array, offset: int) -> void:
	for i in mini(src.size(), dst.size() - offset):
		dst[offset + i] += src[i]


static func _to_bytes(samples: PackedFloat32Array) -> PackedByteArray:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	return bytes


static func _to_stream(bytes: PackedByteArray) -> AudioStreamWAV:
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = bytes
	return stream
