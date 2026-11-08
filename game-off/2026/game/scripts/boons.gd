class_name BoonSet
extends RefCounted
## The run-long perks the hero owns. Passed to [method HotSwapRules.resolve], so the simulation stays pure.

## Boon ids.
enum Boon { QUICK_DRAW, SPARE_CLIP, COAT }

## Boons in the game.
const COUNT: int = 3
## Display names, indexed by [enum Boon].
const NAMES: Array[String] = ["QUICK DRAW", "SPARE CLIP", "BULLETPROOF COAT"]
## One-line effects, indexed by [enum Boon].
const EFFECTS: Array[String] = ["Strike hits 2 visible foes", "+1 shift in every room", "Ignore the 1st hit per room"]
## One-letter marks for the HUD, indexed by [enum Boon].
const INITIALS: Array[String] = ["Q", "S", "B"]

## The hero's strike kills the two nearest living gunmen with a clear line.
var quick_draw: bool = false
## Every room budget has one more swap.
var spare_clip: bool = false
## The first bullet that would hit the hero in each room is ignored.
var coat: bool = false


## Builds a set from the owned boon ids.
static func from_owned(owned: Array[int]) -> BoonSet:
	var set: BoonSet = BoonSet.new()
	set.quick_draw = Boon.QUICK_DRAW in owned
	set.spare_clip = Boon.SPARE_CLIP in owned
	set.coat = Boon.COAT in owned
	return set
