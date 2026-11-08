class_name ShareLink
extends RefCounted
## Share link and clipboard access. The web build copies the page URL with [code]?seed=CODE[/code] and the desktop build copies the code.

## Script that copies a text and reports a later refusal in [code]window.hsCopyFailed[/code]. It returns false when the clipboard is missing.
const COPY_SCRIPT: String = "(function(t){try{window.hsCopyFailed=false;if(!navigator.clipboard||!navigator.clipboard.writeText){return false;}navigator.clipboard.writeText(t).catch(function(){window.hsCopyFailed=true;});return true;}catch(e){return false;}})(%s)"


## Returns the text a friend can open or type: the page URL with the seed on web, the bare code elsewhere.
static func text_for(seed_value: int) -> String:
	var code: String = SeedCode.encode(seed_value)
	if not OS.has_feature("web"):
		return code
	var base: Variant = JavaScriptBridge.eval("window.location.origin + window.location.pathname")
	return "%s?seed=%s" % [str(base), code] if base != null else code


## Copies [param text] and returns true when a copy was started. Returns false when no clipboard is available, so the caller shows the text.
## Call it from the tap handler, because browsers allow the clipboard only after a tap.
static func copy(text: String) -> bool:
	if OS.has_feature("web"):
		return JavaScriptBridge.eval(COPY_SCRIPT % JSON.stringify(text)) == true
	if not DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		return false
	DisplayServer.clipboard_set(text)
	return true


## Returns true when the browser refused a copy that [method copy] started. Always false off the web.
static func web_copy_failed() -> bool:
	return OS.has_feature("web") and JavaScriptBridge.eval("window.hsCopyFailed === true") == true


## Returns the query string of the page URL on web, or an empty string elsewhere.
static func page_query() -> String:
	if not OS.has_feature("web"):
		return ""
	return str(JavaScriptBridge.eval("window.location.search"))
