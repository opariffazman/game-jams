extends RefCounted
## Rule-specific checks for the match simulator. Enabled with SIM_RULES=1.
##
## Names follow the spec: Stack.is_built and a build-complete signal. A check that needs a name the
## tree does not have yet is skipped, so the file stays valid while the rules change.

const BUILD_SIGNALS: Array[StringName] = [&"pyramid_built", &"build_completed", &"built", &"rebuilt"]
const LIMIT_PROPERTIES: Array[StringName] = [&"build_time_limit", &"scatter_time_limit", &"round_time_limit"]


## Returns one message per broken rule. Each message starts with a short class name and a colon.
func on_round_ended(manager: RoundManager, arena: Arena, tuning: Tuning, winner_team: int, kind: String) -> Array[String]:
	var messages: Array[String] = []
	if kind == "build":
		var built: Variant = arena.stack.get(&"is_built")
		if built != null and not bool(built):
			messages.append("build_without_pyramid: attackers won by build while Stack.is_built is false")
		if arena.stack.placed_count < tuning.stack_size:
			messages.append("build_with_missing_sandals: attackers won by build with %d of %d sandals placed" % [arena.stack.placed_count, tuning.stack_size])
		if not _has_build_signal(arena.stack):
			messages.append("build_signal_missing: Stack has none of %s" % str(BUILD_SIGNALS))
	if kind == "forced":
		return messages
	for property: StringName in LIMIT_PROPERTIES:
		var limit: Variant = tuning.get(property)
		if limit != null and float(limit) > 0.0 and kind != "build" and kind != "wipe" and kind != "topple":
			messages.append("round_without_cause: round ended without a known cause")
	if winner_team != manager.attacking_team and kind == "build":
		messages.append("build_credited_to_defenders: build ended the round for the defending team")
	return messages


func _has_build_signal(stack: Stack) -> bool:
	for name: StringName in BUILD_SIGNALS:
		if stack.has_signal(name):
			return true
	return false
