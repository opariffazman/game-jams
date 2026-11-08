class_name SettingsRef
extends RefCounted
## Reads the [code]Settings[/code] autoload by node path, so scripts compile in a test run and a scene run alike.
##
## A script run through [code]--script[/code] compiles before autoloads register, so naming the autoload fails there.
## Every call falls back to a safe default when the autoload is missing.

## Scheme D value, the default.
const SCHEME_LOCK_FIRE: int = 0
## Scheme A value.
const SCHEME_AIM_STICK: int = 1

## Flat 2D view value, the default.
const VIEW_FLAT: int = 0
## Depth 3D view value.
const VIEW_DEPTH: int = 1

const NODE_PATH: String = "/root/Settings"


## The autoload node, or null.
static func node() -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null(NODE_PATH)


## The throw scheme chosen in settings. Scheme D when the autoload is missing.
static func scheme() -> int:
	var settings: Node = node()
	return int(settings.get("scheme")) if settings != null else SCHEME_LOCK_FIRE


## The art view chosen in settings. The flat view when the autoload is missing.
static func view() -> int:
	var settings: Node = node()
	return int(settings.get("view")) if settings != null else VIEW_FLAT


## True when haptics are on. On when the autoload is missing.
static func haptics_enabled() -> bool:
	var settings: Node = node()
	return bool(settings.get("haptics_enabled")) if settings != null else true


## True when sound is on. On when the autoload is missing.
static func sound_enabled() -> bool:
	var settings: Node = node()
	return bool(settings.get("sound_enabled")) if settings != null else true


## Id of the hero picked last. Kilat when the autoload is missing.
static func hero_id() -> StringName:
	var settings: Node = node()
	return StringName(settings.get("hero_id")) if settings != null else &"kilat"


## True once the coin flip has played. True when the autoload is missing, so a bare scene never plays it.
static func coin_flip_seen() -> bool:
	var settings: Node = node()
	return bool(settings.get("coin_flip_seen")) if settings != null else true


## Remembers that the coin flip played. Does nothing when the autoload is missing.
static func mark_coin_flip_seen() -> void:
	var settings: Node = node()
	if settings != null:
		settings.call("mark_coin_flip_seen")


## Remembers the picked hero. Does nothing when the autoload is missing.
static func set_hero_id(value: StringName) -> void:
	var settings: Node = node()
	if settings != null:
		settings.call("set_hero_id", value)


## Switches the scheme. Does nothing when the autoload is missing.
static func set_scheme(value: int) -> void:
	var settings: Node = node()
	if settings != null:
		settings.call("set_scheme", value)


## Switches the art view. Does nothing when the autoload is missing.
static func set_view(value: int) -> void:
	var settings: Node = node()
	if settings != null:
		settings.call("set_view", value)


## Turns haptics on or off. Does nothing when the autoload is missing.
static func set_haptics(enabled: bool) -> void:
	var settings: Node = node()
	if settings != null:
		settings.call("set_haptics", enabled)


## Turns sound on or off. Does nothing when the autoload is missing.
static func set_sound(enabled: bool) -> void:
	var settings: Node = node()
	if settings != null:
		settings.call("set_sound", enabled)


## Vibrates through the autoload. Does nothing when it is missing.
static func vibrate(milliseconds: int) -> void:
	var settings: Node = node()
	if settings != null:
		settings.call("vibrate", milliseconds)


## Calls [param callback] when the scheme changes. Returns false when the autoload is missing.
static func on_scheme_changed(callback: Callable) -> bool:
	var settings: Node = node()
	if settings == null:
		return false
	settings.connect("scheme_changed", callback)
	return true


## Calls [param callback] when the view changes. Returns false when the autoload is missing.
static func on_view_changed(callback: Callable) -> bool:
	var settings: Node = node()
	if settings == null:
		return false
	settings.connect("view_changed", callback)
	return true


## Calls [param callback] when haptics change. Returns false when the autoload is missing.
static func on_haptics_changed(callback: Callable) -> bool:
	var settings: Node = node()
	if settings == null:
		return false
	settings.connect("haptics_changed", callback)
	return true


## Calls [param callback] when sound turns on or off. Returns false when the autoload is missing.
static func on_sound_changed(callback: Callable) -> bool:
	var settings: Node = node()
	if settings == null:
		return false
	settings.connect("sound_changed", callback)
	return true


## 3D camera pitch in degrees. The default when the autoload is missing.
static func camera_pitch() -> float:
	var settings: Node = node()
	return float(settings.get("camera_pitch")) if settings != null else 42.0


## 3D camera zoom. 1.0 when the autoload is missing.
static func camera_zoom() -> float:
	var settings: Node = node()
	return float(settings.get("camera_zoom")) if settings != null else 1.0


## Sets the 3D camera. Pass [param persist] false while a finger drags.
static func set_camera(pitch_degrees: float, zoom: float, persist: bool = true) -> void:
	var settings: Node = node()
	if settings != null:
		settings.call("set_camera", pitch_degrees, zoom, persist)


## Restores the default 3D camera.
static func reset_camera() -> void:
	var settings: Node = node()
	if settings != null:
		settings.call("reset_camera")


## Calls [param callback] when the camera changes. Returns false when the autoload is missing.
static func on_camera_changed(callback: Callable) -> bool:
	var settings: Node = node()
	if settings == null:
		return false
	settings.connect("camera_changed", callback)
	return true
