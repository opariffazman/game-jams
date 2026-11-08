class_name HudIconSet
extends Resource
## Every texture the HUD draws, in one swappable resource.
##
## The HUD reads icons only from this resource. To reskin the HUD, make a new
## [HudIconSet] file and assign it to the [code]icons[/code] property of the HUD scene.

## Filled or empty pip that counts round wins.
@export var score_pip: Texture2D
## Role marker while the human team attacks.
@export var role_attack: Texture2D
## Role marker while the human team defends.
@export var role_defend: Texture2D
## One icon per attacker throw. Dims after the throw is used.
@export var throw_sandal: Texture2D
## Icon in the middle of the stack progress ring.
@export var stack_ring: Texture2D
## One icon per attacker. Lights up when that attacker is mati.
@export var skull: Texture2D
## Coin shown during the coin flip at the start of a match.
@export var coin_flip: Texture2D
## Trophy shown when the match ends.
@export var match_trophy: Texture2D
