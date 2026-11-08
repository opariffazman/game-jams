class_name TurnSteps
extends RefCounted
## Grid movement for the end of a turn: knife and advance steps, the knife danger zone, and where a reinforcement lands. Pure.


## Manhattan reach in cells of a living knife: one step plus one cell of contact.
const KNIFE_REACH: int = 2


## Returns the end-of-turn moves of the turn being planned, from the state at the start of the turn. Pure.
## Each move is a dictionary with gun, from, to, and cause ([code]advance[/code] or [code]knife[/code]).
## Every knife and, on an advance turn, every non-knife gunman steps one cell toward the hero's start-of-turn cell.
## The plan never depends on the tapped gunman, so the telegraph is true for every tap. The swapped gunman does not step.
## Cover, every start-of-turn gunman cell, the hero's cell, and cells another move already took block a step.
static func plan_steps(state: RoomState) -> Array[Dictionary]:
	var plan: Array[Dictionary] = []
	var advancing: bool = not state.events_now("advance").is_empty()
	var movers: Array[int] = []
	for i: int in state.guns.size():
		if state.alive[i] and (advancing or state.kinds[i] == RoomState.Kind.KNIFE):
			movers.append(i)
	if movers.is_empty():
		return plan
	var goal: Vector2i = Rooms.cell_of(state.hero)
	var taken: Dictionary = {goal: true}
	for i: int in state.guns.size():
		if state.alive[i]:
			taken[Rooms.cell_of(state.guns[i])] = true
	for i: int in movers:
		var here: Vector2i = Rooms.cell_of(state.guns[i])
		var dest: Vector2i = _step_cell(state, here, goal, taken)
		if dest != here:
			taken[dest] = true
			plan.append({"gun": i, "from": state.guns[i], "to": Rooms.cell_center(dest), "cause": "knife" if state.kinds[i] == RoomState.Kind.KNIFE else "advance"})
	return plan


## Returns true when [param pos] lies inside the danger zone of a knife standing at [param knife].
static func in_knife_zone(knife: Vector2, pos: Vector2) -> bool:
	var gap: Vector2i = Rooms.cell_of(knife) - Rooms.cell_of(pos)
	return absi(gap.x) + absi(gap.y) <= KNIFE_REACH


## Returns the grid cells inside the danger zone of a knife standing at [param knife].
static func knife_zone_cells(knife: Vector2) -> Array[Vector2i]:
	var center: Vector2i = Rooms.cell_of(knife)
	var cells: Array[Vector2i] = []
	for row: int in range(center.y - KNIFE_REACH, center.y + KNIFE_REACH + 1):
		for col: int in range(center.x - KNIFE_REACH, center.x + KNIFE_REACH + 1):
			var cell: Vector2i = Vector2i(col, row)
			if col >= 0 and col < Rooms.COLS and row >= 0 and row < Rooms.ROWS and absi(col - center.x) + absi(row - center.y) <= KNIFE_REACH:
				cells.append(cell)
	return cells


## Returns the free position nearest to [param wanted] for a new gunman. Ties go to the upper row.
static func spawn_position(state: RoomState, wanted: Vector2) -> Vector2:
	var want: Vector2i = Rooms.cell_of(wanted)
	var hero_cell: Vector2i = Rooms.cell_of(state.hero)
	var best: Vector2i = want
	var best_key: float = INF
	for row: int in Rooms.ROWS:
		for col: int in Rooms.COLS:
			var cell: Vector2i = Vector2i(col, row)
			if cell == hero_cell or is_blocked(state, cell, -1):
				continue
			var key: float = absi(col - want.x) + absi(row - want.y) + 0.01 * row + 0.0001 * col
			if key < best_key:
				best_key = key
				best = cell
	return Rooms.cell_center(best)


## Returns true when [param cell] holds cover or a living gunman other than [param ignore].
static func is_blocked(state: RoomState, cell: Vector2i, ignore: int) -> bool:
	var center: Vector2 = Rooms.cell_center(cell)
	for cover: Rect2 in state.covers:
		if cover.has_point(center):
			return true
	for i: int in state.guns.size():
		if i != ignore and state.alive[i] and Rooms.cell_of(state.guns[i]) == cell:
			return true
	return false


static func _step_cell(state: RoomState, here: Vector2i, goal: Vector2i, taken: Dictionary) -> Vector2i:
	var gap: Vector2i = goal - here
	var along_x: Vector2i = Vector2i(signi(gap.x), 0)
	var along_y: Vector2i = Vector2i(0, signi(gap.y))
	var order: Array[Vector2i] = []
	if absi(gap.x) > absi(gap.y):
		order.assign([along_x, along_y])
	else:
		order.assign([along_y, along_x])
	for step: Vector2i in order:
		if step == Vector2i.ZERO:
			continue
		var dest: Vector2i = here + step
		if taken.has(dest):
			continue
		var center: Vector2 = Rooms.cell_center(dest)
		var covered: bool = false
		for cover: Rect2 in state.covers:
			covered = covered or cover.has_point(center)
		if not covered:
			return dest
	return here
