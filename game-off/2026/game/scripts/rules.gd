class_name HotSwapRules
extends RefCounted
## Deterministic rules for one swap, plus a brute-force solver.

## Radius within which a bullet segment hits a gunman.
const BODY_RADIUS: float = 18.0
## Radius within which a bullet segment hits the hero.
const HERO_RADIUS: float = 16.0
## Cosine of half the shield arc. The arc is 120 degrees wide, so a bullet within 60 degrees of the facing is blocked.
const SHIELD_ARC_COS: float = 0.5
## Pixels a cover block grows on every side when it blocks a line of fire. A tracer that grazes a wall edge stops there instead of reading as a shot through the wall.
const COVER_MARGIN: float = 8.0


## One gunman bullet: the segment, and who it hits and when along the segment.
class Shot:
	extends RefCounted
	## Index of the gunman who fires this bullet.
	var shooter: int = -1
	## Segment start.
	var from: Vector2 = Vector2.ZERO
	## Segment end after cover and shield clipping.
	var to: Vector2 = Vector2.ZERO
	## Indices of gunmen hit.
	var victims: Array[int] = []
	## Fraction along the segment where each victim is hit.
	var victim_fracs: Array[float] = []
	## Fraction where the hero is hit, or -1.0 for a miss.
	var hero_frac: float = -1.0
	## Shield gunman who stopped this bullet, or -1.
	var blocked_by: int = -1
	## Fraction where the Bulletproof Coat absorbed this bullet, or -1.0 when it did not.
	var coat_frac: float = -1.0


## Outcome of one swap, in the order the presentation plays it.
class Resolution:
	extends RefCounted
	## Gunman the player tapped.
	var tap: int = -1
	## First gunman the hero shoots, or -1 when the strike is [member wasted].
	var target: int = -1
	## Every gunman the hero shoots, nearest first. Two with Quick Draw.
	var targets: Array[int] = []
	## Targets that died from the strike.
	var struck: Array[int] = []
	## Targets whose shield stopped the strike.
	var blocked_strikes: Array[int] = []
	## True when other gunmen live but cover hides all of them, so the strike kills nothing and [member target] is -1.
	var wasted: bool = false
	## Where a wasted strike stops, on the first cover block between the hero and the nearest gunman.
	var impact: Vector2 = Vector2.ZERO
	## Gunmen who could not fire this turn.
	var jammed: Array[int] = []
	## Hero position before the swap.
	var old_hero: Vector2 = Vector2.ZERO
	## Gunman position before the swap.
	var old_gun: Vector2 = Vector2.ZERO
	## Bullets fired by the remaining gunmen.
	var shots: Array[Shot] = []
	## Gunmen killed by bullets, not counting the hero's targets. A target still fires its shot as it dies.
	var killed: Array[int] = []
	## End-of-turn moves from [method TurnSteps.plan_steps], each a dictionary with gun, from, to, and cause ([code]advance[/code] or [code]knife[/code]). Dead and swapped gunmen do not move.
	var steps: Array[Dictionary] = []
	## Indices of gunmen who appeared at the end of the turn.
	var spawns: Array[int] = []
	## True if any bullet touches the hero, or he ends the turn inside the danger zone of a living knife.
	var hero_dead: bool = false
	## True if the hero ended the turn inside a living knife's danger zone.
	var stabbed: bool = false
	## True if the Bulletproof Coat ignored a bullet this turn.
	var coat_used: bool = false


	## Returns how many gunmen the strike and the bullets killed.
	func kill_count() -> int:
		return struck.size() + killed.size()


## Applies one tap to [param state] in place and returns what happened. [param boons] adds the run perks.
static func resolve(state: RoomState, tap: int, boons: BoonSet = null) -> Resolution:
	var res: Resolution = Resolution.new()
	var plan: Array[Dictionary] = TurnSteps.plan_steps(state)
	res.tap = tap
	res.old_hero = state.hero
	res.old_gun = state.guns[tap]
	var aim: Vector2 = state.hero
	state.guns[tap] = res.old_hero
	state.hero = res.old_gun
	for event: Dictionary in state.events_now("jam"):
		var params: Dictionary = event["params"]
		res.jammed.append(int(params["gun"]))
	res.targets = _strike_targets(state, tap, 2 if boons != null and boons.quick_draw else 1, res)
	res.target = res.targets[0] if not res.targets.is_empty() else -1
	for shooter: int in state.guns.size():
		if state.alive[shooter] and shooter != tap and state.kinds[shooter] != RoomState.Kind.KNIFE and shooter not in res.jammed:
			res.shots.append(_build_shot(state, shooter, aim))
	for target: int in res.targets:
		if _blocks(state, target, state.hero - state.guns[target]):
			res.blocked_strikes.append(target)
		else:
			state.alive[target] = false
			res.struck.append(target)
	for shot: Shot in res.shots:
		for victim: int in shot.victims:
			if state.alive[victim]:
				state.alive[victim] = false
				res.killed.append(victim)
		if shot.hero_frac >= 0.0:
			if boons != null and boons.coat and not state.coat_spent:
				state.coat_spent = true
				res.coat_used = true
				shot.coat_frac = shot.hero_frac
				shot.hero_frac = -1.0
			else:
				res.hero_dead = true
	if not res.hero_dead:
		for i: int in state.guns.size():
			if state.alive[i] and state.kinds[i] == RoomState.Kind.KNIFE and TurnSteps.in_knife_zone(state.guns[i], state.hero):
				res.stabbed = true
				res.hero_dead = true
	if not res.hero_dead:
		_end_of_turn(state, res, plan)
	state.turn += 1
	return res


## Returns the shortest winning tap sequence, or an empty array if none within [param max_depth].
static func solve(state: RoomState, max_depth: int = 6, boons: BoonSet = null) -> Array[int]:
	for depth: int in range(1, max_depth + 1):
		var path: Array[int] = []
		if _search(state, depth, path, boons):
			return path
	return []


## Returns true when a shield gunman [param index] stops a bullet that arrives from the direction [param arrival].
static func blocks(state: RoomState, index: int, arrival: Vector2) -> bool:
	return _blocks(state, index, arrival)


static func _search(state: RoomState, depth: int, path: Array[int], boons: BoonSet) -> bool:
	for tap: int in state.guns.size():
		if not state.alive[tap]:
			continue
		var next: RoomState = state.clone()
		var res: Resolution = resolve(next, tap, boons)
		if res.hero_dead:
			continue
		path.append(tap)
		if next.alive_count() == 0:
			return true
		if depth > 1 and _search(next, depth - 1, path, boons):
			return true
		path.pop_back()
	return false


## Picks the nearest living gunmen with a clear line from the hero. Cover hides a gunman from the strike as it does from a bullet.
## With no other gunman alive the swapped gunman is the target. When others live but all are hidden, marks [member Resolution.wasted].
static func _strike_targets(state: RoomState, tap: int, count: int, res: Resolution) -> Array[int]:
	var living: Array[int] = []
	var visible: Array[int] = []
	for i: int in state.guns.size():
		if i == tap or not state.alive[i]:
			continue
		living.append(i)
		if cover_fraction(state.covers, state.hero, state.guns[i]) >= 1.0:
			visible.append(i)
	if living.is_empty():
		return [tap] as Array[int]
	if visible.is_empty():
		var nearest: int = _nearest_of(state, living, 1)[0]
		res.wasted = true
		res.impact = clip_to_cover(state.covers, state.hero, state.guns[nearest])
		return [] as Array[int]
	return _nearest_of(state, visible, count)


static func _nearest_of(state: RoomState, pool: Array[int], count: int) -> Array[int]:
	var out: Array[int] = []
	for pick: int in mini(count, pool.size()):
		var best: int = -1
		var best_dist: float = INF
		for i: int in pool:
			if i in out:
				continue
			var dist: float = state.hero.distance_to(state.guns[i])
			if dist < best_dist - 0.01:
				best_dist = dist
				best = i
		out.append(best)
	return out


static func _blocks(state: RoomState, index: int, arrival: Vector2) -> bool:
	if state.kinds[index] != RoomState.Kind.SHIELD or arrival.length_squared() < 0.001:
		return false
	return RoomState.facing_vector(state.facings[index]).dot(arrival.normalized()) >= SHIELD_ARC_COS - 0.001


static func _end_of_turn(state: RoomState, res: Resolution, plan: Array[Dictionary]) -> void:
	for step: Dictionary in plan:
		var gun: int = int(step["gun"])
		if gun != res.tap and state.alive[gun]:
			state.guns[gun] = step["to"]
			res.steps.append(step)
	for event: Dictionary in state.events_now("reinforce"):
		var params: Dictionary = event["params"]
		res.spawns.append(state.add_gun(TurnSteps.spawn_position(state, params["pos"]), RoomState.Kind.PISTOL, RoomState.Facing.UP))


static func _build_shot(state: RoomState, shooter: int, aim: Vector2) -> Shot:
	var shot: Shot = Shot.new()
	shot.shooter = shooter
	shot.from = state.guns[shooter]
	var end: Vector2 = clip_to_cover(state.covers, shot.from, aim)
	var cut: float = 1.0
	for i: int in state.guns.size():
		if i == shooter or not state.alive[i] or state.kinds[i] != RoomState.Kind.SHIELD:
			continue
		var frac: float = _hit_fraction(shot.from, end, state.guns[i], BODY_RADIUS)
		if frac >= 0.0 and frac < cut and _blocks(state, i, shot.from - end):
			cut = frac
			shot.blocked_by = i
	shot.to = shot.from.lerp(end, cut)
	for i: int in state.guns.size():
		if i == shooter or i == shot.blocked_by or not state.alive[i]:
			continue
		var frac: float = _hit_fraction(shot.from, shot.to, state.guns[i], BODY_RADIUS)
		if frac >= 0.0:
			shot.victims.append(i)
			shot.victim_fracs.append(frac)
	shot.hero_frac = _hit_fraction(shot.from, shot.to, state.hero, HERO_RADIUS)
	return shot


static func _hit_fraction(from: Vector2, to: Vector2, point: Vector2, radius: float) -> float:
	var seg: Vector2 = to - from
	var len_sq: float = seg.length_squared()
	if len_sq < 0.001:
		return 0.0 if from.distance_to(point) <= radius else -1.0
	var frac: float = clampf((point - from).dot(seg) / len_sq, 0.0, 1.0)
	if from.lerp(to, frac).distance_to(point) <= radius:
		return frac
	return -1.0


## Returns where the segment from [param from] to [param to] ends, stopped by the first cover block.
static func clip_to_cover(covers: Array[Rect2], from: Vector2, to: Vector2) -> Vector2:
	return from + (to - from) * cover_fraction(covers, from, to)


## Returns the fraction along the segment from [param from] to [param to] where the first cover block starts, or 1.0 for a clear line.
## Every line of fire goes through here. A block counts as its rect grown by [constant COVER_MARGIN].
## A block whose margin holds an endpoint counts as its real rect, so a body next to cover stays reachable from the open side.
static func cover_fraction(covers: Array[Rect2], from: Vector2, to: Vector2) -> float:
	var best: float = 1.0
	for block: Rect2 in covers:
		var cover: Rect2 = block.grow(COVER_MARGIN)
		if cover.has_point(from) or cover.has_point(to):
			cover = block
		best = minf(best, _entry_fraction(cover, from, to))
	return best


## Returns true when the segment from [param from] to [param to] touches a real cover rect, with no margin. The swap dash uses it to know a smear would cross a wall.
static func crosses_cover(covers: Array[Rect2], from: Vector2, to: Vector2) -> bool:
	for cover: Rect2 in covers:
		if _entry_fraction(cover, from, to) <= 1.0:
			return true
	return false


## Returns the fraction where the segment enters [param rect], or 2.0 when it misses.
static func _entry_fraction(rect: Rect2, from: Vector2, to: Vector2) -> float:
	var dir: Vector2 = to - from
	var t_min: float = 0.0
	var t_max: float = 1.0
	for axis: int in 2:
		var start: float = from[axis]
		var delta: float = dir[axis]
		var lo: float = rect.position[axis]
		var hi: float = rect.end[axis]
		if absf(delta) < 0.0001:
			if start < lo or start > hi:
				return 2.0
			continue
		var t1: float = (lo - start) / delta
		var t2: float = (hi - start) / delta
		t_min = maxf(t_min, minf(t1, t2))
		t_max = minf(t_max, maxf(t1, t2))
	return t_min if t_min <= t_max else 2.0
