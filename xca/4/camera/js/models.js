// Loads MediaPipe from the local folder only. No CDN.
import { FilesetResolver, PoseLandmarker, GestureRecognizer, FaceDetector } from '../vendor/vision_bundle.mjs';

const WASM_DIR = './vendor/wasm';
const FACE_MODEL = './models/blaze_face_short_range.tflite';
const POSE_MODEL = './models/pose_landmarker_lite.task';
const GESTURE_MODEL = './models/gesture_recognizer.task';

let filesetPromise = null;
function fileset() {
  filesetPromise ??= FilesetResolver.forVisionTasks(WASM_DIR);
  return filesetPromise;
}

// Tries the preferred delegate and retries on CPU. Reports the error from the first attempt.
async function createWithFallback(create, preferred) {
  const order = preferred === 'GPU' ? ['GPU', 'CPU'] : ['CPU'];
  let firstError = null;
  for (const delegate of order) {
    try {
      const task = await create(delegate);
      return { task, delegate, error: firstError };
    } catch (e) {
      firstError ??= `${delegate} failed: ${e?.name}: ${e?.message}`;
      if (delegate === 'CPU') throw e;
    }
  }
}

export async function createPose(preferred, numPoses) {
  const files = await fileset();
  return createWithFallback((delegate) => PoseLandmarker.createFromOptions(files, {
    baseOptions: { modelAssetPath: POSE_MODEL, delegate },
    runningMode: 'VIDEO',
    numPoses,
  }), preferred);
}

// The pose model loses a player who is too close for shoulders to show. The face detector needs only the face.
export async function createFace(preferred, maxFaces) {
  const files = await fileset();
  return createWithFallback((delegate) => FaceDetector.createFromOptions(files, {
    baseOptions: { modelAssetPath: FACE_MODEL, delegate },
    runningMode: 'VIDEO',
    minDetectionConfidence: 0.3,
  }), preferred);
}

export async function createHands(preferred) {
  const files = await fileset();
  return createWithFallback((delegate) => GestureRecognizer.createFromOptions(files, {
    baseOptions: { modelAssetPath: GESTURE_MODEL, delegate },
    runningMode: 'VIDEO',
    numHands: 2,
  }), preferred);
}
