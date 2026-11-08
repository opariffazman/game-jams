class_name TurnEvents
extends RefCounted
## Re-simulates a room from its data and the tapped gunmen, and records what happens as an ordered event list per turn.
##
## Each turn is a dictionary with [code]tap[/code], [code]plan[/code] (the telegraph lines before the swap) and
## [code]events[/code]. Events are dictionaries keyed by [code]type[/code]:[br]
## [code]swap[/code]: gun, hero_from, gun_from, crosses_cover (the straight dash would cross a wall).[br]
## [code]jam[/code]: gun.[br]
## [code]hero_shot[/code]: from, to, victim, blocked.[br]
## [code]shot[/code]: shooter, from, to, victims (in hit order), fracs, blocked_by.[br]
## [code]hero_hit[/code]: shooter, from, to, frac (the bullet that kills the hero).[br]
## [code]coat_block[/code]: shooter, from, to, frac (the Bulletproof Coat absorbs the bullet).[br]
## [code]knife_contact[/code]: gun (a living knife has the hero inside its danger zone).[br]
## [code]death[/code]: gun, cause ([code]hero[/code] or [code]shot[/code]), shooter, frac.[br]
## [code]step[/code]: gun, from, to, cause ([code]advance[/code] or [code]knife[/code]).[br]
## [code]spawn[/code]: gun, pos.
## The rules run through [HotSwapRules.resolve] only, so no outcome changes.

## Turns in play order.
var turns: Array[Dictionary] = []
## Room state after the last turn.
var final_state: RoomState
## Room dictionary the first turn starts from. It has an [code]alive[/code] array when earlier turns were skipped.
var start_room: Dictionary = {}


## Builds the timeline of [param taps] played on [param room], with the perks in [param boons].
## The first [param skip] taps run through the rules without events, and the timeline starts from the state they leave.
static func build(room: Dictionary, taps: Array[int], boons: BoonSet = null, skip: int = 0) -> TurnEvents:
	var timeline: TurnEvents = TurnEvents.new()
	var state: RoomState = RoomState.from_room(room)
	for tap: int in taps.slice(0, skip):
		HotSwapRules.resolve(state, tap, boons)
	timeline.start_room = room if skip == 0 else _room_of(state, room)
	for tap: int in taps.slice(skip):
		var plan: Array[Dictionary] = _plan_lines(state)
		var res: HotSwapRules.Resolution = HotSwapRules.resolve(state, tap, boons)
		timeline.turns.append({"tap": tap, "plan": plan, "events": _events_of(res, state)})
	timeline.final_state = state
	return timeline


## Returns the live-outcome style summary of the final state after [param swap_count] swaps.
func outcome(swap_count: int, hero_dead: bool) -> Dictionary:
	return {"swaps": swap_count, "alive": final_state.alive_count(), "hero": final_state.hero, "guns": final_state.guns, "dead": hero_dead}


## Returns every gunman index that dies in the timeline, in death order.
func dead_guns() -> Array[int]:
	var dead: Array[int] = []
	for turn: Dictionary in turns:
		for event: Dictionary in turn["events"]:
			if event["type"] == "death":
				dead.append(int(event["gun"]))
	return dead


## Returns [param room] with the hero, gunmen and alive flags of [param state], so a stage can start mid-room.
static func _room_of(state: RoomState, room: Dictionary) -> Dictionary:
	var out: Dictionary = room.duplicate()
	out["hero"] = state.hero
	out["guns"] = state.guns.duplicate()
	out["kinds"] = state.kinds.duplicate()
	out["facings"] = state.facings.duplicate()
	out["alive"] = state.alive.duplicate()
	return out


static func _plan_lines(state: RoomState) -> Array[Dictionary]:
	var lines: Array[Dictionary] = []
	var jammed: Array[int] = []
	for event: Dictionary in state.events_now("jam"):
		var params: Dictionary = event["params"]
		jammed.append(int(params["gun"]))
	for i: int in state.guns.size():
		if state.alive[i] and state.kinds[i] != RoomState.Kind.KNIFE and i not in jammed:
			lines.append({"gun": i, "from": state.guns[i], "to": HotSwapRules.clip_to_cover(state.covers, state.guns[i], state.hero)})
	return lines


static func _events_of(res: HotSwapRules.Resolution, state: RoomState) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	events.append({"type": "swap", "gun": res.tap, "hero_from": res.old_hero, "gun_from": res.old_gun, "crosses_cover": HotSwapRules.crosses_cover(state.covers, res.old_hero, res.old_gun)})
	for gun: int in res.jammed:
		events.append({"type": "jam", "gun": gun})
	if res.wasted:
		events.append({"type": "hero_shot", "from": res.old_gun, "to": res.impact, "victim": -1, "blocked": false, "wasted": true})
	for target: int in res.targets:
		events.append({"type": "hero_shot", "from": res.old_gun, "to": _pos_before_steps(res, state, target), "victim": target, "blocked": target in res.blocked_strikes, "wasted": false})
		if target in res.struck:
			events.append({"type": "death", "gun": target, "cause": "hero", "shooter": -1, "frac": 0.0})
	for shot: HotSwapRules.Shot in res.shots:
		events.append({"type": "shot", "shooter": shot.shooter, "from": shot.from, "to": shot.to, "victims": shot.victims.duplicate(), "fracs": shot.victim_fracs.duplicate(), "blocked_by": shot.blocked_by})
	for shot: HotSwapRules.Shot in res.shots:
		if shot.hero_frac >= 0.0:
			events.append({"type": "hero_hit", "shooter": shot.shooter, "from": shot.from, "to": shot.to, "frac": shot.hero_frac})
		if shot.coat_frac >= 0.0:
			events.append({"type": "coat_block", "shooter": shot.shooter, "from": shot.from, "to": shot.to, "frac": shot.coat_frac})
	if res.stabbed:
		for i: int in state.guns.size():
			if state.alive[i] and state.kinds[i] == RoomState.Kind.KNIFE and TurnSteps.in_knife_zone(state.guns[i], state.hero):
				events.append({"type": "knife_contact", "gun": i})
				break
	var seen: Array[int] = res.struck.duplicate()
	for shot: HotSwapRules.Shot in res.shots:
		for v: int in shot.victims.size():
			var victim: int = shot.victims[v]
			if victim in res.killed and victim not in seen:
				seen.append(victim)
				events.append({"type": "death", "gun": victim, "cause": "shot", "shooter": shot.shooter, "frac": shot.victim_fracs[v]})
	for step: Dictionary in res.steps:
		events.append({"type": "step", "gun": step["gun"], "from": step["from"], "to": step["to"], "cause": step["cause"]})
	for gun: int in res.spawns:
		events.append({"type": "spawn", "gun": gun, "pos": state.guns[gun]})
	return events


## Returns where gunman [param gun] stood while the turn's shots flew, before any end-of-turn step.
static func _pos_before_steps(res: HotSwapRules.Resolution, state: RoomState, gun: int) -> Vector2:
	for step: Dictionary in res.steps:
		if int(step["gun"]) == gun:
			return step["from"]
	return state.guns[gun]
