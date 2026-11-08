"""Adds the camera overlay, tracker script and CSP to the exported Godot index.html."""
import pathlib
import sys

OVERLAY = """
<video id="cam" playsinline muted style="position:fixed;right:8px;top:8px;width:140px;opacity:0;pointer-events:none;transform:scaleX(-1);border:2px solid #fff;border-radius:6px;z-index:5"></video>
<canvas id="holo" width="280" height="210" style="position:fixed;right:8px;top:8px;width:140px;height:105px;pointer-events:none;transform:scaleX(-1);z-index:6"></canvas>
<div id="panel" style="display:none;position:fixed;left:8px;bottom:190px;z-index:5;display:flex;gap:8px;flex-wrap:wrap">
<button id="startCam" style="font:600 22px sans-serif;min-width:150px;min-height:56px">Start camera</button>
<button id="dlLog" style="font:600 22px sans-serif;min-width:150px;min-height:56px">Download log</button>
</div>
<pre id="hud" style="position:fixed;right:8px;top:130px;margin:0;z-index:5;color:#fff;background:rgba(0,0,0,.8);font:14px/1.35 monospace;padding:6px;max-width:48vw;white-space:pre-wrap"></pre>
<pre id="err" style="display:none;position:fixed;left:8px;top:300px;margin:0;z-index:6;color:#fff;background:#b00020;font:16px monospace;padding:6px;max-width:90vw;white-space:pre-wrap"></pre>
<script>if (/[?&]debug\b/.test(location.search)) document.documentElement.classList.add('debug');</script>
<script type="module" src="tracker.js"></script>
<script>
try {
  if ('serviceWorker' in navigator && window.isSecureContext) {
    navigator.serviceWorker.register('sw.js').catch((e) => console.log('sw: register failed - ' + e));
  }
} catch (e) { console.log('sw: unavailable - ' + e); }
</script>
"""
# The hiding rule lives in head so the first paint never shows the debug elements.
HEAD_STYLE = '<style>#hud:empty,#err:empty{display:none!important}html:not(.debug) #panel,html:not(.debug) #hud,html:not(.debug) #err{display:none!important}</style>'
CSP = '<meta http-equiv="Content-Security-Policy" content="connect-src \'self\' blob: data:">'

path = pathlib.Path(sys.argv[1])
html = path.read_text()
if "tracker.js" not in html:
    html = html.replace("<head>", "<head>\n\t\t" + CSP + HEAD_STYLE, 1)
    html = html.replace("</body>", OVERLAY + "</body>", 1)
    path.write_text(html)
