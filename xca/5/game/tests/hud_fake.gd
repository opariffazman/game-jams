extends Node2D
## Stand-in for RoundManager, Stack and Character so the HUD runs alone.
##
## The preview scene gives each instance a group that the HUD searches:
## [code]hud_round_manager[/code], [code]hud_stack[/code] or [code]hud_character[/code].

## Same signals as the real nodes.
signal phase_changed(phase: int)
signal round_ended(winner_team: int)
signal toppled
signal rebuilt

## Same phase names as RoundManager.
enum State { COIN_FLIP, TOPPLE, SCATTER, ROUND_END, MATCH_END }

## Team that attacks this round.
var attacking_team: int = 0
## Throws the attackers have left.
var throws_left: int = 0
## Stack sandals placed back.
var placed_count: int = 0
## Team of this fake character.
var team: int = 0
## False once this fake character is mati.
var alive: bool = true
