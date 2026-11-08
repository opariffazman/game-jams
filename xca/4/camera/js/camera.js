// Many tablet cameras crop the sensor at low resolutions, so a larger capture size can show a wider view.
export const CAPTURE_SIZES = [
  { w: 640, h: 480 },
  { w: 1280, h: 720 },
  { w: 1280, h: 960 },
  { w: 1920, h: 1080 },
];

export async function startStream(video, facing, size = CAPTURE_SIZES[0]) {
  const stream = await navigator.mediaDevices.getUserMedia({
    audio: false,
    video: { facingMode: facing, width: { ideal: size.w }, height: { ideal: size.h } },
  });
  video.srcObject = stream;
  await video.play();
  return stream;
}

export function zoomRange(video) {
  const track = video.srcObject?.getVideoTracks()[0];
  const zoom = track?.getCapabilities?.().zoom;
  return zoom ? { min: zoom.min, max: zoom.max, step: zoom.step || 0.1, value: track.getSettings().zoom ?? zoom.min } : null;
}

export async function setZoom(video, value) {
  const track = video.srcObject?.getVideoTracks()[0];
  await track.applyConstraints({ advanced: [{ zoom: value }] });
}

export function stopStream(video) {
  video.srcObject?.getTracks().forEach((t) => t.stop());
  video.srcObject = null;
}

export function environmentInfo() {
  let camPolicy = 'n/a';
  try {
    const fp = document.featurePolicy;
    if (fp?.allowsFeature) camPolicy = String(fp.allowsFeature('camera'));
  } catch (e) { camPolicy = `error ${e.name}`; }
  return {
    isSecureContext: window.isSecureContext,
    insideIframe: window.self !== window.top,
    featurePolicyAllowsCamera: camPolicy,
    hasMediaDevices: !!navigator.mediaDevices?.getUserMedia,
    userAgent: navigator.userAgent,
    devicePixelRatio: window.devicePixelRatio,
    screen: `${screen.width}x${screen.height}`,
    hardwareConcurrency: navigator.hardwareConcurrency,
  };
}
