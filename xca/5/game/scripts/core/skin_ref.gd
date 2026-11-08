class_name SkinRef
extends Resource
## One reference to the [VisualSet] in use. Swapping a skin changes only [member visual_set]
## inside [code]res://assets/skins/active.tres[/code].

const ACTIVE_PATH: String = "res://assets/skins/active.tres"

## The 3D Kenney set, used while the depth view is chosen.
const DEPTH_SET_PATH: String = "res://assets/skins/kenney3d.tres"

static var _cached: VisualSet
static var _cached_view: int = -1

## The active visual set.
@export var visual_set: VisualSet


## Returns the active [VisualSet]. Every logic node builds its visual from this.
static func get_visual_set() -> VisualSet:
	if _cached == null:
		follow_view_setting()
	return _cached


## Points the cache at the set of the view chosen in settings.
## Returns true when the cached set changed, so the caller rebuilds art that lives for a whole match.
static func follow_view_setting() -> bool:
	var wanted: int = SettingsRef.view()
	if _cached != null and _cached_view == wanted:
		return false
	var next: VisualSet = null
	if wanted == SettingsRef.VIEW_DEPTH:
		next = load(DEPTH_SET_PATH) as VisualSet
	if next == null:
		wanted = SettingsRef.VIEW_FLAT
		var ref: SkinRef = load(ACTIVE_PATH) as SkinRef
		if ref == null or ref.visual_set == null:
			push_error("SkinRef: %s has no visual set." % ACTIVE_PATH)
			return false
		next = ref.visual_set
	var changed: bool = _cached != next
	_cached = next
	_cached_view = wanted
	return changed


## Drops the cached set so the next [method get_visual_set] reads the file again.
static func reload() -> void:
	_cached = null
	_cached_view = -1
