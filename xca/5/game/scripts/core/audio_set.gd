class_name AudioSet
extends RefCounted
## The sound slots of the game: which files a slot picks from, how loud, how high, and how many play at once.
##
## A slot is a game event, not a file. [method Audio.play] takes a slot name, so swapping a file is one edit here.
## The set lives in code, not in a resource, because a hand-written resource with 40 stream references breaks on a
## renamed file without a clear error, while a path in a test fails by name.

## Folder of every sound file.
const DIR: String = "res://assets/audio/"
## Folder of music loops. The files are optional. A missing file means silence.
const MUSIC_DIR: String = "res://assets/audio/music/"
## Bus names. The layout is in [code]default_bus_layout.tres[/code].
const BUS_SFX: StringName = &"Sfx"
const BUS_UI: StringName = &"Ui"
const BUS_VOICE: StringName = &"Voice"
const BUS_MUSIC: StringName = &"Music"
## Voice priorities. A line plays over a quieter line, never over an equal or louder one.
const VOICE_HYPE: int = 1
const VOICE_CALL: int = 2
const VOICE_RESULT: int = 3
## Countdown numbers and go. They play over everything, so a rate limit or a hype line never drops one.
const VOICE_COUNT: int = 4
## Least time between two hype lines, so a kill streak does not turn into a stream of talk.
const HYPE_GAP_MS: int = 9000
## Music phases. A phase lists variants. Each loop plays the next variant.
const MUSIC_TOPPLE: Array[String] = ["topple_a", "topple_b"]
const MUSIC_FINAL: Array[String] = ["final_a", "final_b"]


## Every slot by name. A slot has files, db, pitch_min, pitch_max, cap, bus, gap_ms and, for voice, priority.
static func slots() -> Dictionary:
	return {
		&"throw": _slot(["impactSoft_heavy_000", "impactSoft_heavy_001"], -6.0, 0.95, 1.10, 3),
		&"hit_block": _slot(["impactWood_medium_000", "impactWood_medium_001", "impactWood_medium_002"], -4.0, 0.9, 1.1, 3),
		&"pass_kill": _slot(["impactPunch_heavy_000", "impactPunch_heavy_001"], -2.0, 0.9, 1.05, 2),
		&"sandal_clack": _slot(["impactWood_heavy_000", "impactWood_heavy_001"], -3.0, 0.9, 1.15, 3, BUS_SFX, 60),
		&"topple": _slot(["impactPlank_medium_000", "impactPlank_medium_001", "impactWood_heavy_000"], -2.0, 0.9, 1.0, 1),
		&"pickup": _slot(["click2"], -10.0, 0.95, 1.05, 2),
		&"place": _slot(["impactWood_medium_000"], -8.0, 1.0, 1.15, 2),
		&"rebuilt": _slot(["impactBell_heavy_004"], -6.0, 1.0, 1.0, 1),
		&"pass": _slot(["impactSoft_medium_000", "impactSoft_medium_001"], -8.0, 1.0, 1.15, 2),
		&"catch": _slot(["impactSoft_heavy_000"], -8.0, 1.05, 1.2, 2),
		&"dash": _slot(["footstep_grass_000", "footstep_grass_001", "footstep_grass_002"], -8.0, 1.4, 1.6, 1),
		&"death": _slot(["impactMetal_light_000", "impactMetal_light_001", "impactPunch_medium_000"], -4.0, 0.85, 1.0, 2),
		&"round_start": _slot(["switch14"], -8.0, 1.0, 1.0, 1),
		&"round_win": _slot(["impactBell_heavy_004"], -6.0, 1.1, 1.1, 1),
		&"round_lose": _slot(["impactSoft_heavy_001"], -6.0, 0.7, 0.7, 1),
		&"coin_tick": _slot(["click1"], -8.0, 0.9, 1.1, 1),
		&"coin_end": _slot(["switch2"], -8.0, 1.0, 1.0, 1),
		&"match_win": _slot(["impactBell_heavy_004"], -4.0, 1.0, 1.25, 1),
		&"match_lose": _slot(["impactSoft_heavy_001"], -4.0, 0.6, 0.6, 1),
		&"ui_tap": _slot(["click1", "click2", "click3"], -10.0, 0.97, 1.03, 2, BUS_UI),
		&"ui_on": _slot(["switch2"], -10.0, 1.0, 1.0, 1, BUS_UI),
		&"ui_off": _slot(["switch14"], -10.0, 1.0, 1.0, 1, BUS_UI),
		&"ui_press": _slot(["mouseclick1"], -16.0, 0.97, 1.03, 1, BUS_UI),
		&"restart_hold": _slot(["rollover1"], -14.0, 1.0, 1.0, 1, BUS_UI),
		&"restart_confirm": _slot(["mouserelease1"], -8.0, 1.0, 1.0, 1, BUS_UI),
		&"voice_prepare": _voice(["voice/prepare_yourself"], VOICE_CALL),
		&"voice_round_1": _voice(["voice/round_1"], VOICE_CALL),
		&"voice_round_2": _voice(["voice/round_2"], VOICE_CALL),
		&"voice_round_3": _voice(["voice/round_3"], VOICE_CALL),
		&"voice_round_4": _voice(["voice/round_4"], VOICE_CALL),
		&"voice_round_5": _voice(["voice/round_5"], VOICE_CALL),
		&"voice_final_round": _voice(["voice/final_round"], VOICE_CALL),
		&"voice_three": _voice(["voice/three"], VOICE_COUNT),
		&"voice_two": _voice(["voice/two"], VOICE_COUNT),
		&"voice_one": _voice(["voice/one"], VOICE_COUNT),
		&"voice_fight": _voice(["voice/fight"], VOICE_COUNT),
		&"voice_you_win": _voice(["voice/you_win"], VOICE_RESULT),
		&"voice_you_lose": _voice(["voice/you_lose"], VOICE_RESULT),
		&"voice_flawless": _voice(["voice/flawless_victory"], VOICE_RESULT),
		&"voice_hype": _voice(["voice/kill_it"], VOICE_HYPE, HYPE_GAP_MS),
		&"voice_combo": _voice(["voice/combo"], VOICE_HYPE, HYPE_GAP_MS),
	}


## Every sound file path the slots name, without duplicates.
static func asset_paths() -> Array[String]:
	var paths: Array[String] = []
	for slot: Dictionary in slots().values():
		for file: String in slot["files"]:
			var path: String = DIR + file + ".ogg"
			if not paths.has(path):
				paths.append(path)
	return paths


## Every music file path, with the folder.
static func music_paths() -> Array[String]:
	var paths: Array[String] = []
	for name: String in MUSIC_TOPPLE + MUSIC_FINAL:
		paths.append(MUSIC_DIR + name + ".ogg")
	return paths


static func _slot(files: Array[String], db: float, pitch_min: float, pitch_max: float, cap: int, bus: StringName = BUS_SFX, gap_ms: int = 0) -> Dictionary:
	return {"files": files, "db": db, "pitch_min": pitch_min, "pitch_max": pitch_max, "cap": cap, "bus": bus, "gap_ms": gap_ms, "priority": 0}


static func _voice(files: Array[String], priority: int, gap_ms: int = 0) -> Dictionary:
	var slot: Dictionary = _slot(files, -4.0, 1.0, 1.0, 1, BUS_VOICE, gap_ms)
	slot["priority"] = priority
	return slot
