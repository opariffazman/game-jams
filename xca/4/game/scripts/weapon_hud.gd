class_name WeaponHud
extends Control
## Shows the weapon in hand as an icon, the next weapon in the cycle and the combo count.
##
## The next weapon is small, so a player sees what a flick up or down brings before making it. The accent colour is a second cue beside the icon shape.

const CURRENT_SIZE: Vector2 = Vector2(84.0, 68.0)
const NEXT_SIZE: Vector2 = Vector2(60.0, 48.0)
const ICON_PAD: float = 8.0
const GAP: float = 8.0
const LEFT: float = 12.0
const TOP: float = 8.0
const AMMO_BAR_HEIGHT: float = 10.0
const AMMO_FONT: int = 22
const COMBO_FONT: int = 40
const SHADOW: Vector2 = Vector2(1.0, 2.0)
const TEXT_SHADOW: Color = Color(0.0, 0.0, 0.0, 0.85)
## Combos below this count stay hidden, so a single kill never flashes a number.
const COMBO_MIN: int = 2

## Shooter that knows the weapon in hand.
@export var shooter: Shooter

## Combo count to show. The scene sets it from the juice node.
var combo: int = 0:
	set(value):
		combo = value
		queue_redraw()

var _font: Font = UiKit.font()


func _ready() -> void:
	if shooter != null:
		shooter.weapon_changed.connect(func(_weapon: Dictionary) -> void: queue_redraw())
		shooter.ammo_changed.connect(queue_redraw)
		shooter.carried_changed.connect(queue_redraw)


func _draw() -> void:
	if shooter == null:
		return
	var current: Dictionary = shooter.get_weapon()
	var current_rect := Rect2(Vector2(LEFT, TOP), CURRENT_SIZE)
	_draw_card(current_rect, String(current["id"]), Color(current["accent"]), 4)
	var below: float = current_rect.end.y + GAP
	if int(current["ammo"]) > 0:
		below = _draw_ammo(current, current_rect) + GAP
	# Every other carried weapon sits beside the current one in cycle order, so a flick shows what it brings.
	var others: int = shooter.carried.size() - 1
	for step: int in range(1, others + 1):
		var other: Dictionary = shooter.peek_weapon(step)
		var next_rect := Rect2(Vector2(current_rect.end.x + GAP + (step - 1) * (NEXT_SIZE.x + GAP), TOP + CURRENT_SIZE.y - NEXT_SIZE.y), NEXT_SIZE)
		var empty: bool = shooter.ammo_left(other) == 0
		_draw_card(next_rect, String(other["id"]), Color(other["accent"]), 2, 0.35 if empty else 1.0)
	if combo >= COMBO_MIN:
		var text: String = "x%d" % combo
		var baseline := Vector2(LEFT, below + _font.get_ascent(COMBO_FONT))
		draw_string(_font, baseline + SHADOW, text, HORIZONTAL_ALIGNMENT_LEFT, -1, COMBO_FONT, TEXT_SHADOW)
		draw_string(_font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, COMBO_FONT, UiKit.GOLD)


func _draw_card(rect: Rect2, weapon_id: String, accent: Color, border: int, alpha: float = 1.0) -> void:
	draw_style_box(UiKit.brush(UiKit.PANEL, accent, 0.0, 5 + border, false), rect)
	draw_texture_rect(UiKit.icon(weapon_id), rect.grow(-ICON_PAD), false, Color(1, 1, 1, alpha))


## Draws a bar and a number under the weapon card, and returns the bottom edge. The bar turns red when nearly empty, so colour is never the only cue beside the number.
func _draw_ammo(weapon: Dictionary, card: Rect2) -> float:
	var left: int = shooter.ammo_left(weapon)
	var share: float = float(left) / float(weapon["ammo"])
	var bar := Rect2(card.position.x, card.end.y + GAP * 0.5, CURRENT_SIZE.x, AMMO_BAR_HEIGHT)
	draw_rect(bar, Color(0, 0, 0, 0.7))
	var fill_colour: Color = Color(1.0, 0.3, 0.3) if share < 0.25 else Color(weapon["accent"])
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * share, bar.size.y)), fill_colour)
	var baseline := Vector2(bar.end.x + GAP, bar.end.y + 4.0)
	draw_string(_font, baseline + SHADOW, str(left), HORIZONTAL_ALIGNMENT_LEFT, -1, AMMO_FONT, TEXT_SHADOW)
	draw_string(_font, baseline, str(left), HORIZONTAL_ALIGNMENT_LEFT, -1, AMMO_FONT, Color.WHITE)
	return bar.end.y
