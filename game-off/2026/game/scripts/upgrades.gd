class_name Upgrades
extends RefCounted
## Permanent upgrades bought in the Locker with tips. Pure rules over the save dictionary and the owned-id list.

## Upgrade ids. The order is the Locker order and the number key of each card.
enum Id { HEARTS_1, HEARTS_2, SPARE_SLACK, OPENING_CHOICE, CYAN_COAT, AMBER_COAT }
## What a card shows and what a tap does.
enum CardState { BUYABLE, POOR, OWNED, EQUIPPED, LOCKED }
## Outcome of a tap on a card.
enum Result { BOUGHT, EQUIPPED, UNEQUIPPED, OWNED, POOR, LOCKED }

## Upgrades in the game.
const COUNT: int = 6
## Card names, indexed by [enum Id].
const NAMES: Array[String] = ["MAX HEARTS I", "MAX HEARTS II", "SPARE SLACK", "OPENING CHOICE", "CYAN COAT", "AMBER COAT"]
## One-line effects, indexed by [enum Id].
const EFFECTS: Array[String] = ["Start with 4 hearts", "Start with 5 hearts", "+1 shift on floors 1-2", "Pick a boon at start", "Hero color: cyan", "Hero color: amber"]
## Tips cost, indexed by [enum Id].
const COSTS: Array[int] = [40, 90, 60, 80, 30, 30]
## Upgrade that must be owned first, or -1. Indexed by [enum Id].
const REQUIRES: Array[int] = [-1, Id.HEARTS_1, -1, -1, -1, -1]
## Last floor that Spare Slack covers.
const SLACK_LAST_FLOOR: int = 2


## Returns true for the hero color upgrades, which equip instead of applying at once.
static func is_style(id: int) -> bool:
	return id == Id.CYAN_COAT or id == Id.AMBER_COAT


## Returns the state of card [param id] for [param save].
static func card_state(save: Dictionary, id: int) -> CardState:
	if id in save["owned"]:
		return CardState.EQUIPPED if is_style(id) and int(save["coat"]) == id else CardState.OWNED
	if REQUIRES[id] >= 0 and REQUIRES[id] not in save["owned"]:
		return CardState.LOCKED
	return CardState.BUYABLE if int(save["tips"]) >= COSTS[id] else CardState.POOR


## Taps card [param id]: buys it, or equips or unequips an owned coat. Changes [param save] in memory only.
static func activate(save: Dictionary, id: int) -> Result:
	match card_state(save, id):
		CardState.LOCKED:
			return Result.LOCKED
		CardState.POOR:
			return Result.POOR
		CardState.BUYABLE:
			save["tips"] = int(save["tips"]) - COSTS[id]
			save["owned"].append(id)
			if is_style(id):
				save["coat"] = id
			return Result.BOUGHT
	if is_style(id) and int(save["coat"]) != id:
		save["coat"] = id
		return Result.EQUIPPED
	if is_style(id):
		save["coat"] = -1
		return Result.UNEQUIPPED
	return Result.OWNED


## Returns the hearts a run starts with when [param owned] holds the bought upgrades.
static func start_hearts(owned: Array) -> int:
	return RunState.START_HEARTS + (1 if Id.HEARTS_1 in owned else 0) + (1 if Id.HEARTS_2 in owned else 0)


## Returns the extra swaps Spare Slack gives a room on [param floor_number].
static func slack_bonus(owned: Array, floor_number: int) -> int:
	return 1 if Id.SPARE_SLACK in owned and floor_number <= SLACK_LAST_FLOOR else 0


## Returns the hero color: the equipped coat, else the plain shirt.
static func hero_color(save: Dictionary) -> Color:
	match int(save["coat"]):
		Id.CYAN_COAT:
			return Palette.CYAN
		Id.AMBER_COAT:
			return Palette.AMBER
	return Palette.INK
