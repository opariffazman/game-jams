class_name FullscreenToggle
extends RefCounted
## Enters and leaves browser fullscreen from a button.
##
## GamePix runs the game in a frame that can lack the fullscreen permission, mostly on phones. There the button
## opens the game in its own tab instead. The request runs inside the touch handler, because browsers only grant
## fullscreen and popups to a direct user gesture.

const ROOT: String = "document.documentElement"


## True on a web build that can show the page fullscreen, or that sits in a frame and can open its own page.
## iPhone Safari outside a frame cannot do either, so no button shows there.
static func available() -> bool:
	if not OS.has_feature("web"):
		return false
	return can_request() or framed()


## True when the browser lets this page request fullscreen. A frame without the fullscreen permission cannot.
static func can_request() -> bool:
	return bool(JavaScriptBridge.eval("!!((document.fullscreenEnabled || document.webkitFullscreenEnabled) && (%s.requestFullscreen || %s.webkitRequestFullscreen))" % [ROOT, ROOT]))


## True when the page runs inside another page, as on a game portal.
static func framed() -> bool:
	return bool(JavaScriptBridge.eval("window.self !== window.top"))


## True while the page is fullscreen.
static func active() -> bool:
	if not OS.has_feature("web"):
		return false
	return bool(JavaScriptBridge.eval("!!(document.fullscreenElement || document.webkitFullscreenElement)"))


## Enters fullscreen, or leaves it when already there. A phone is also locked to landscape.
static func toggle() -> void:
	if not OS.has_feature("web"):
		return
	if active():
		JavaScriptBridge.eval("(document.exitFullscreen || document.webkitExitFullscreen).call(document)")
		return
	if not can_request():
		# The portal frame blocks fullscreen. Its own tab has no frame, and the start tap there goes fullscreen.
		JavaScriptBridge.eval("window.open(location.href, '_blank')")
		return
	JavaScriptBridge.eval("""
		(function () {
			const root = %s;
			const request = root.requestFullscreen || root.webkitRequestFullscreen;
			const entered = request.call(root, { navigationUI: 'hide' });
			const lock = () => { try { screen.orientation.lock('landscape').catch(() => {}); } catch (err) {} };
			if (entered && entered.then) { entered.then(lock, () => {}); } else { lock(); }
		}());
	""" % ROOT)
