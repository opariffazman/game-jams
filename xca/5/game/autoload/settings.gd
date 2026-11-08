extends Node
## Player settings, saved to [code]user://settings.cfg[/code].
##
## The web build keeps that file in the browser's IndexedDB, so a choice survives a page reload.
## A change applies at once through [signal scheme_changed] and [signal haptics_changed].

## Emitted when the throw scheme changes. [param scheme] is a [enum Scheme] value.
signal scheme_changed(scheme: int)
## Emitted when haptics turn on or off.
signal haptics_changed(enabled: bool)
## Emitted when the view changes. [param view] is a [enum View] value. The match applies it at the next round start.
signal view_changed(view: int)
## Emitted when the 3D camera pitch or zoom changes.
signal camera_changed(pitch_degrees: float, zoom: float)
## Emitted when sound turns on or off.
signal sound_changed(enabled: bool)

## The two throw schemes.
enum Scheme {
	LOCK_FIRE, ## Scheme D: a fire button locks onto a target.
	AIM_STICK, ## Scheme A: a stick aims and release fires.
}

## The two art views of the same match.
enum View {
	FLAT, ## The 2D primitives skin, the default.
	DEPTH, ## The 3D Kenney skin.
}

const SECTION: String = "controls"
const DEFAULT_PATH: String = "user://settings.cfg"

## Throw scheme in use.
var scheme: int = Scheme.LOCK_FIRE
## Art view in use.
var view: int = View.DEPTH
## True when vibration feedback is on. It only does anything on Android Chrome.
var haptics_enabled: bool = true
## True when sound plays. The mute toggle in the settings panel turns it off.
var sound_enabled: bool = true
## 3D camera pitch below the horizon, degrees.
var camera_pitch: float = ViewProjection.DEFAULT_PITCH_DEGREES
## 3D camera zoom. 1.0 is the default framing.
var camera_zoom: float = ViewProjection.DEFAULT_FIT
## True when the title screen never shows. A player or a test sets it.
var skip_title: bool = false
## True once the player has seen the how-to-play cards.
var how_to_seen: bool = false
## Where settings are read from and written to. Tests point it at a scratch file.
var path: String = DEFAULT_PATH


func _ready() -> void:
	load_settings()
	_apply_camera()


## Reads the file. A missing or broken file keeps the defaults.
func load_settings() -> void:
	var file: ConfigFile = ConfigFile.new()
	if file.load(path) != OK:
		return
	var stored: int = int(file.get_value(SECTION, "scheme", Scheme.LOCK_FIRE))
	scheme = stored if stored in [Scheme.LOCK_FIRE, Scheme.AIM_STICK] else Scheme.LOCK_FIRE
	haptics_enabled = bool(file.get_value(SECTION, "haptics", true))
	sound_enabled = bool(file.get_value(SECTION, "sound", true))
	var stored_view: int = int(file.get_value(SECTION, "view", View.DEPTH))
	view = stored_view if stored_view in [View.FLAT, View.DEPTH] else View.DEPTH
	skip_title = bool(file.get_value(SECTION, "skip_title", false))
	how_to_seen = bool(file.get_value(SECTION, "how_to_seen", false))
	camera_pitch = clampf(float(file.get_value(SECTION, "camera_pitch", ViewProjection.DEFAULT_PITCH_DEGREES)), ViewProjection.MIN_PITCH_DEGREES, ViewProjection.MAX_PITCH_DEGREES)
	camera_zoom = clampf(float(file.get_value(SECTION, "camera_zoom", ViewProjection.DEFAULT_FIT)), ViewProjection.MIN_FIT, ViewProjection.MAX_FIT)


## Writes the file. Returns the error code.
func save_settings() -> int:
	var file: ConfigFile = ConfigFile.new()
	file.set_value(SECTION, "scheme", scheme)
	file.set_value(SECTION, "haptics", haptics_enabled)
	file.set_value(SECTION, "view", view)
	file.set_value(SECTION, "sound", sound_enabled)
	file.set_value(SECTION, "skip_title", skip_title)
	file.set_value(SECTION, "how_to_seen", how_to_seen)
	file.set_value(SECTION, "camera_pitch", camera_pitch)
	file.set_value(SECTION, "camera_zoom", camera_zoom)
	return file.save(path)


## Switches the throw scheme, saves it and tells listeners.
func set_scheme(new_scheme: int) -> void:
	if new_scheme == scheme:
		return
	scheme = new_scheme
	save_settings()
	scheme_changed.emit(scheme)


## Remembers that the how-to-play cards were shown, so they do not open by themselves again.
func mark_how_to_seen() -> void:
	if how_to_seen:
		return
	how_to_seen = true
	save_settings()


## Switches the art view, saves it and tells listeners.
func set_view(new_view: int) -> void:
	if new_view == view:
		return
	view = new_view
	save_settings()
	view_changed.emit(view)


## Sets the 3D camera. A drag passes [param persist] false and saves once on release, because the web build writes IndexedDB.
func set_camera(pitch_degrees: float, zoom: float, persist: bool = true) -> void:
	camera_pitch = clampf(pitch_degrees, ViewProjection.MIN_PITCH_DEGREES, ViewProjection.MAX_PITCH_DEGREES)
	camera_zoom = clampf(zoom, ViewProjection.MIN_FIT, ViewProjection.MAX_FIT)
	_apply_camera()
	if persist:
		save_settings()
	camera_changed.emit(camera_pitch, camera_zoom)


## Restores the default camera and saves it.
func reset_camera() -> void:
	set_camera(ViewProjection.DEFAULT_PITCH_DEGREES, ViewProjection.DEFAULT_FIT)


func _apply_camera() -> void:
	ViewProjection.pitch_degrees = camera_pitch
	ViewProjection.fit = camera_zoom


## Turns haptics on or off, saves it and tells listeners.
func set_haptics(enabled: bool) -> void:
	if enabled == haptics_enabled:
		return
	haptics_enabled = enabled
	save_settings()
	haptics_changed.emit(enabled)


## Turns sound on or off, saves it and tells listeners.
func set_sound(enabled: bool) -> void:
	if enabled == sound_enabled:
		return
	sound_enabled = enabled
	save_settings()
	sound_changed.emit(enabled)


## Vibrates for [param milliseconds] when haptics are on and the device supports it.
func vibrate(milliseconds: int) -> void:
	if haptics_enabled and milliseconds > 0 and DisplayServer.is_touchscreen_available():
		Input.vibrate_handheld(milliseconds)
