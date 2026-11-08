class_name Kata
extends RefCounted
## Shared constants and the looping note pattern for Kata Beat.
##
## One pattern character is one sixteenth note.
## [code]P[/code] punch, [code]K[/code] kick, [code]S[/code] shoot, [code].[/code] rest.

## Lane indices, left to right.
enum Lane { PUNCH, KICK, SHOOT }

## Tempo in beats per minute. Fixed, 4/4.
const BPM: float = 120.0
## Seconds per beat.
const BEAT: float = 60.0 / BPM
## Seconds per bar.
const BAR: float = BEAT * 4.0
## Seconds per sixteenth note.
const STEP: float = BEAT / 4.0
## Empty bars before the first note. Gives the player time to feel the pulse.
const LEAD_IN_BARS: int = 1
## Bars of backing track after the last pattern bar.
const OUTRO_BARS: int = 1
## Song time in seconds when the results screen opens.
const RESULT_TIME: float = (LEAD_IN_BARS + 16) * BAR + 0.5
## Total bars in the backing track.
const TRACK_BARS: int = LEAD_IN_BARS + 16 + OUTRO_BARS

## Background color.
const BG: Color = Color("08080c")
## Kick lane and enemy color.
const MAGENTA: Color = Color("ff2e88")
## Punch lane color.
const CYAN: Color = Color("19e3ff")
## Shoot lane color.
const AMBER: Color = Color("ffb020")
## Text and hero color.
const INK: Color = Color("f6f6f8")
## Four reusable bars. Adjacent sixteenths never share a lane.
const BARS: Dictionary = {
	"A": "P.S.K.S.P.S.K.S.",
	"B": "P.PSK.S.P.PSK.S.",
	"C": "K.S.P.K.S.P.K.S.",
	"D": "PKS.PKS.P.K.S.SK",
}
## The 16-bar song as bar letters.
const ORDER: String = "AABAABCBCCDCABDD"

## Lane colors indexed by [enum Lane].
static var lane_colors: PackedColorArray = PackedColorArray([CYAN, MAGENTA, AMBER])


## Fills [param times] with note times in seconds and [param lanes] with [enum Lane] values.
static func build(times: PackedFloat32Array, lanes: PackedInt32Array) -> void:
	times.clear()
	lanes.clear()
	for bar in ORDER.length():
		var shape: String = BARS[ORDER[bar]]
		for step in shape.length():
			var lane: int = "PKS".find(shape[step])
			if lane < 0:
				continue
			times.append((LEAD_IN_BARS + bar) * BAR + step * STEP)
			lanes.append(lane)
