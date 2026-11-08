class_name Quality
extends RefCounted
## Two graphics tiers. The tier decides how many heavy kit models the street bakes, because chunks are built once and reused.

enum Tier { LOW, HIGH }

## Substrings of the WebGL renderer name that mean the machine has no discrete GPU. Software renderers and phones sit here too.
const LOW_RENDERERS: PackedStringArray = ["swiftshader", "llvmpipe", "software", "mali", "adreno", "powervr", "apple gpu", "intel", "radeon graphics", "vega"]

static var _tier: int = -1


## The tier is read once. A `quality=low` or `quality=high` query parameter overrides the GPU check, so a tester can compare both.
static func tier() -> Tier:
	if _tier < 0:
		_tier = _detect()
	return _tier as Tier


static func is_high() -> bool:
	return tier() == Tier.HIGH


static func _detect() -> int:
	if not OS.has_feature("web"):
		return Tier.HIGH
	var forced: String = str(JavaScriptBridge.eval("new URLSearchParams(location.search).get('quality') || ''", true)).to_lower()
	if forced == "low":
		return Tier.LOW
	if forced == "high":
		return Tier.HIGH
	var renderer: String = str(JavaScriptBridge.eval("(function(){try{var c=document.createElement('canvas');var g=c.getContext('webgl2')||c.getContext('webgl');var e=g.getExtension('WEBGL_debug_renderer_info');return e?g.getParameter(e.UNMASKED_RENDERER_WEBGL):''}catch(x){return ''}})()", true)).to_lower()
	for marker: String in LOW_RENDERERS:
		if renderer.contains(marker):
			return Tier.LOW
	return Tier.HIGH
