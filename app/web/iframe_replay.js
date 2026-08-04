// Adds WebGL snapshots from a same-origin viewer iframe to the one PostHog
// recorder owned by the Flutter shell.
//
// rrweb observes iframe DOM but its canvas sampler only scans the top document.
// Running another rrweb recorder in every iframe is both expensive and wrong:
// nested previews can resolve against an intermediate frame instead of the
// shell, and continuously encoding WebGL canvases competes with rendering.
//
// This bridge is deliberately event-driven. The viewer asks for a frame after
// a model is rendered, and pointer interaction requests throttled updates. A
// small 2D copy is made synchronously while the WebGL back buffer is valid,
// encoded once, and emitted as a normal rrweb CanvasMutation. There is no
// second analytics client, recorder, render loop, or background sampler.

const INCREMENTAL_SNAPSHOT_TYPE = 3;
const MOUSE_MOVE_SOURCE = 1;
const TOUCH_MOVE_SOURCE = 6;
const CANVAS_MUTATION_SOURCE = 9;

const MAX_CAPTURE_EDGE = 960;
const MAX_CAPTURE_PIXELS = 960 * 960;
const CAPTURE_QUALITY = 0.82;
const MIN_CAPTURE_INTERVAL_MS = 750;
const MIN_ACTIVITY_INTERVAL_MS = 250;
const CONTEXT_RETRY_INTERVAL_MS = 250;
const CONTEXT_RETRY_TIMEOUT_MS = 30000;

let pendingSnapshot = null;
let retryTimer = 0;
let disposed = false;
let lastCaptureAt = 0;
let lastActivityAt = 0;
let pointerActive = false;

function parentReplayContext() {
  let candidate = window;
  for (let depth = 0; depth < 8; depth++) {
    let next;
    try {
      next = candidate.parent;
      if (!next || next === candidate) return null;
      // Reading location is the same-origin boundary check.
      void next.location.origin;
    } catch (_) {
      return null;
    }
    candidate = next;

    const posthog = candidate.posthog;
    let recording = false;
    try { recording = posthog?.sessionRecordingStarted?.() === true; }
    catch (_) {}
    if (!recording) continue;

    const onRRwebEmit = posthog?.sessionRecording?.onRRwebEmit;
    const mirror = candidate.__PosthogExtensions__?.rrweb?.record?.mirror;
    if (typeof onRRwebEmit === 'function' && typeof mirror?.getId === 'function') {
      return { onRRwebEmit: onRRwebEmit.bind(posthog.sessionRecording), mirror };
    }
  }
  return null;
}

function replayNodeId(context, node) {
  try {
    const id = context.mirror.getId(node);
    return Number.isInteger(id) && id >= 0 ? id : null;
  } catch (_) {
    return null;
  }
}

function snapshotSize(canvas) {
  const width = Math.max(1, canvas.width || canvas.clientWidth || 1);
  const height = Math.max(1, canvas.height || canvas.clientHeight || 1);
  const edgeScale = Math.min(1, MAX_CAPTURE_EDGE / Math.max(width, height));
  const pixelScale = Math.min(1, Math.sqrt(MAX_CAPTURE_PIXELS / (width * height)));
  const scale = Math.min(edgeScale, pixelScale);
  return {
    width,
    height,
    copyWidth: Math.max(1, Math.round(width * scale)),
    copyHeight: Math.max(1, Math.round(height * scale)),
    displayWidth: Math.max(1, Math.round(canvas.clientWidth || width)),
    displayHeight: Math.max(1, Math.round(canvas.clientHeight || height)),
  };
}

function copyCanvas(canvas) {
  const size = snapshotSize(canvas);
  const copy = document.createElement('canvas');
  copy.width = size.copyWidth;
  copy.height = size.copyHeight;
  const context = copy.getContext('2d', { alpha: true });
  if (!context) return null;
  try {
    context.drawImage(canvas, 0, 0, size.copyWidth, size.copyHeight);
  } catch (_) {
    return null;
  }
  return { canvas, copy, size, createdAt: performance.now() };
}

function encodeCanvas(canvas) {
  const dataUrl = canvas.toDataURL('image/webp', CAPTURE_QUALITY);
  const match = /^data:([^;,]+);base64,(.*)$/.exec(dataUrl);
  if (!match) return null;
  return { type: match[1], base64: match[2] };
}

function serializedImageBitmap(type, base64) {
  return {
    rr_type: 'ImageBitmap',
    args: [{
      rr_type: 'Blob',
      type,
      data: [{ rr_type: 'ArrayBuffer', base64 }],
    }],
  };
}

function schedulePendingRetry() {
  if (retryTimer || disposed || !pendingSnapshot) return;
  const age = performance.now() - pendingSnapshot.createdAt;
  if (age >= CONTEXT_RETRY_TIMEOUT_MS) {
    pendingSnapshot = null;
    return;
  }
  retryTimer = window.setTimeout(() => {
    retryTimer = 0;
    void flushPendingSnapshot();
  }, CONTEXT_RETRY_INTERVAL_MS);
}

function flushPendingSnapshot() {
  if (disposed || !pendingSnapshot) return;
  const snapshot = pendingSnapshot;
  const context = parentReplayContext();
  const id = context && replayNodeId(context, snapshot.canvas);
  if (!context || id === null) {
    schedulePendingRetry();
    return;
  }

  pendingSnapshot = null;
  try {
    const encoded = encodeCanvas(snapshot.copy);
    if (!encoded || disposed) return;

    const { width, height, copyWidth, copyHeight, displayWidth, displayHeight } = snapshot.size;
    context.onRRwebEmit({
      type: INCREMENTAL_SNAPSHOT_TYPE,
      timestamp: Date.now(),
      data: {
        source: CANVAS_MUTATION_SOURCE,
        type: 0,
        id,
        displayWidth,
        displayHeight,
        commands: [
          { property: 'clearRect', args: [0, 0, width, height] },
          {
            property: 'drawImage',
            args: [
              serializedImageBitmap(encoded.type, encoded.base64),
              0,
              0,
              copyWidth,
              copyHeight,
              0,
              0,
              width,
              height,
            ],
          },
        ],
      },
    });
  } catch (_) {
    // Replay diagnostics must never affect the viewer.
    if (!disposed && performance.now() - snapshot.createdAt < CONTEXT_RETRY_TIMEOUT_MS) {
      pendingSnapshot = snapshot;
      schedulePendingRetry();
    }
  }
}

function capture(canvas, { force = false } = {}) {
  if (disposed || !(canvas instanceof HTMLCanvasElement)) return false;
  const now = performance.now();
  if (!force && now - lastCaptureAt < MIN_CAPTURE_INTERVAL_MS) return false;

  const snapshot = copyCanvas(canvas);
  if (!snapshot) return false;
  lastCaptureAt = now;
  // Keep only the newest image if the parent recorder is not ready yet.
  pendingSnapshot = snapshot;
  flushPendingSnapshot();
  return true;
}

function primaryCanvas() {
  const canvases = [...document.querySelectorAll('canvas')];
  return canvases
    .filter((canvas) => canvas.width > 1 && canvas.height > 1)
    .sort((a, b) => (b.clientWidth * b.clientHeight) - (a.clientWidth * a.clientHeight))[0] || null;
}

function captureAfterPaint(force = false) {
  requestAnimationFrame(() => {
    const canvas = primaryCanvas();
    if (canvas) capture(canvas, { force });
  });
}

function isModelInteractionTarget(target) {
  if (target instanceof HTMLCanvasElement) return true;
  return target instanceof Element
    && Boolean(target.closest('.stage, #canvas-container'));
}

function relayActivity(event) {
  if (!pointerActive && event.type === 'pointermove') return;
  const now = performance.now();
  if (now - lastActivityAt < MIN_ACTIVITY_INTERVAL_MS) return;

  const canvas = event.target instanceof HTMLCanvasElement
    ? event.target
    : primaryCanvas();
  const context = canvas && parentReplayContext();
  const id = context && replayNodeId(context, canvas);
  if (!context || id === null) return;

  lastActivityAt = now;
  try {
    context.onRRwebEmit({
      type: INCREMENTAL_SNAPSHOT_TYPE,
      timestamp: Date.now(),
      data: {
        source: event.pointerType === 'touch' ? TOUCH_MOVE_SOURCE : MOUSE_MOVE_SOURCE,
        positions: [{
          id,
          x: event.clientX,
          y: event.clientY,
          timeOffset: 0,
        }],
      },
    });
  } catch (_) {}
}

// Explicit render hook used by the gallery and editor. It is available before
// PostHog starts; a single pending image waits briefly for the parent recorder.
window.nova3dReplayCapture = (canvas, options) => capture(canvas, options);

document.addEventListener('pointerdown', (event) => {
  if (!isModelInteractionTarget(event.target)) return;
  pointerActive = true;
  relayActivity(event);
  captureAfterPaint(false);
}, { passive: true });

document.addEventListener('pointermove', (event) => {
  if (!pointerActive) return;
  relayActivity(event);
  captureAfterPaint(false);
}, { passive: true });

function endPointer(event) {
  if (!pointerActive) return;
  relayActivity(event);
  pointerActive = false;
  captureAfterPaint(true);
}

document.addEventListener('pointerup', endPointer, { passive: true });
document.addEventListener('pointercancel', endPointer, { passive: true });

window.addEventListener('pagehide', () => {
  disposed = true;
  pendingSnapshot = null;
  if (retryTimer) window.clearTimeout(retryTimer);
  retryTimer = 0;
  delete window.nova3dReplayCapture;
}, { once: true });
