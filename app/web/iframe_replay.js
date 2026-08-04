// Relays WebGL canvas frames from a same-origin viewer iframe into the parent
// PostHog replay.
//
// PostHog/rrweb observes same-origin iframe DOM from the top document, but its
// FPS canvas sampler only scans canvases in the document where the recorder is
// running. Starting a second PostHog client here is not correct: it creates a
// competing replay window, so playback can briefly switch to the model and
// then switch back to the parent's blank iframe.
//
// Instead, this module loads the exact rrweb recorder version already trusted
// and loaded by the parent. A local recorder samples this iframe's canvases,
// and only its CanvasMutation events are handed to the parent's existing
// recorder after translating each canvas to the parent's rrweb node id. The
// result remains one session, one window, and one activity timeline.
//
// Privacy and self-hosting invariants:
//   * no PostHog project key or endpoint is committed here;
//   * no second analytics client, identity, session, or product event exists;
//   * only canvas pixels are relayed; local DOM/network/console events are not;
//   * forks without an active parent PostHog recorder do nothing;
//   * capture follows the parent's recording state and stops on pagehide.

const POLL_INTERVAL_MS = 250;
const PARENT_READY_TIMEOUT_MS = 30000;
const PARENT_STATE_INTERVAL_MS = 1000;
const RELAY_RETRY_INTERVAL_MS = 2000;
const MAX_REPLAY_FPS = 2;
const MIN_QUALITY = 0.1;
const MAX_QUALITY = 1;
const CANVAS_MUTATION_SOURCE = 9;
const INCREMENTAL_SNAPSHOT_TYPE = 3;

function sameOriginParent() {
  if (!window.parent || window.parent === window) return null;
  try {
    return window.parent.location.origin === window.location.origin
      ? window.parent
      : null;
  } catch (_) {
    return null;
  }
}

function finiteNumber(value, fallback, min, max) {
  const number = Number(value);
  if (!Number.isFinite(number)) return fallback;
  return Math.min(max, Math.max(min, number));
}

function isHttpUrl(value) {
  if (typeof value !== 'string' || !value.trim()) return false;
  try {
    const parsed = new URL(value);
    return parsed.protocol === 'https:' || parsed.protocol === 'http:';
  } catch (_) {
    return false;
  }
}

function parentRecorderScriptUrl(parentWindow) {
  try {
    for (const script of parentWindow.document.scripts) {
      const src = script.src;
      if (isHttpUrl(src) && /\/posthog-recorder(?:\.min)?\.js(?:$|[?#])/.test(src)) {
        return src;
      }
    }
  } catch (_) {}
  return null;
}

function parentReplayContext(parentWindow) {
  const posthog = parentWindow.posthog;
  let recording = false;
  try { recording = posthog?.sessionRecordingStarted?.() === true; }
  catch (_) {}
  if (!recording) return null;

  const sessionRecording = posthog?.sessionRecording;
  const parentRecord = parentWindow.__PosthogExtensions__?.rrweb?.record;
  const parentMirror = parentRecord?.mirror;
  const recorderScriptUrl = parentRecorderScriptUrl(parentWindow);
  if (typeof sessionRecording?.onRRwebEmit !== 'function') return null;
  if (typeof parentMirror?.getId !== 'function') return null;
  if (!recorderScriptUrl) return null;

  const config = posthog.config?.session_recording || {};
  const captureCanvas = config.captureCanvas || {};
  const canvasCapture = config.canvasCapture || {};
  const parentFps = finiteNumber(
    captureCanvas.canvasFps,
    MAX_REPLAY_FPS,
    1,
    12,
  );

  return {
    posthog,
    sessionRecording,
    parentMirror,
    recorderScriptUrl,
    canvasFps: Math.min(parentFps, MAX_REPLAY_FPS),
    canvasQuality: finiteNumber(
      captureCanvas.canvasQuality,
      0.8,
      MIN_QUALITY,
      MAX_QUALITY,
    ),
    resolutionScale: finiteNumber(
      canvasCapture.resolutionScale,
      1,
      0.1,
      1,
    ),
  };
}

let recorderScriptPromise;

function loadLocalRecorder(src) {
  const existing = window.__PosthogExtensions__?.rrweb?.record;
  if (typeof existing === 'function') return Promise.resolve(existing);
  if (recorderScriptPromise) return recorderScriptPromise;

  recorderScriptPromise = new Promise((resolve, reject) => {
    const script = document.createElement('script');
    script.type = 'text/javascript';
    script.crossOrigin = 'anonymous';
    script.async = true;
    script.src = src;
    script.dataset.nova3dReplayRelay = 'true';
    script.addEventListener('load', () => {
      const record = window.__PosthogExtensions__?.rrweb?.record;
      if (typeof record === 'function') resolve(record);
      else reject(new Error('rrweb recorder did not initialize'));
    }, { once: true });
    script.addEventListener('error', () => {
      reject(new Error('rrweb recorder failed to load'));
    }, { once: true });
    document.head.appendChild(script);
  }).catch((error) => {
    recorderScriptPromise = undefined;
    throw error;
  });

  return recorderScriptPromise;
}

function isCanvasMutation(event) {
  return event?.type === INCREMENTAL_SNAPSHOT_TYPE
    && event?.data?.source === CANVAS_MUTATION_SOURCE;
}

function parentIsRecording(context) {
  try { return context.posthog.sessionRecordingStarted?.() === true; }
  catch (_) { return false; }
}

function startBridge(parentWindow, initialContext) {
  if (window.__nova3dIframeReplayStarted) return;
  window.__nova3dIframeReplayStarted = true;

  let context = initialContext;
  let localStop = null;
  let starting = false;
  let disposed = false;
  let lastStartAttempt = 0;

  const stopLocalRecorder = () => {
    const stop = localStop;
    localStop = null;
    if (typeof stop === 'function') {
      try { stop(); } catch (_) {}
    }
  };

  const startLocalRecorder = async () => {
    if (disposed || starting || localStop) return;
    const now = Date.now();
    if (now - lastStartAttempt < RELAY_RETRY_INTERVAL_MS) return;
    lastStartAttempt = now;
    starting = true;

    try {
      const record = await loadLocalRecorder(context.recorderScriptUrl);
      if (disposed || !parentIsRecording(context)) return;

      const childMirror = record.mirror;
      if (typeof childMirror?.getNode !== 'function') return;

      const stop = record({
        emit(event) {
          if (!isCanvasMutation(event) || !parentIsRecording(context)) return;
          try {
            const canvas = childMirror.getNode(event.data.id);
            if (!(canvas instanceof window.HTMLCanvasElement)) return;

            // The parent recorder already serialized this same-origin canvas.
            // Resolve its current id for every frame because rrweb replaces
            // mirror ids whenever it takes a new full snapshot.
            const parentId = context.parentMirror.getId(canvas);
            if (!Number.isInteger(parentId) || parentId < 0) return;

            context.sessionRecording.onRRwebEmit({
              ...event,
              data: { ...event.data, id: parentId },
            });
          } catch (_) {
            // Replay must never become load-bearing for the model viewer.
          }
        },
        recordCanvas: true,
        recordCrossOriginIframes: false,
        sampling: {
          canvas: context.canvasFps,
          // The parent recorder already owns interaction/activity capture.
          mousemove: false,
          mouseInteraction: false,
          scroll: false,
        },
        dataURLOptions: {
          type: 'image/webp',
          quality: context.canvasQuality,
          maxBase64ImageLength: 1048576,
        },
        canvasResolutionScale: context.resolutionScale,
        maskAllInputs: true,
        maskInputOptions: { password: true, email: false, text: false },
        maskTextSelector: '[data-ph-mask]',
        blockSelector: '[data-ph-block]',
      });

      if (typeof stop === 'function') localStop = stop;
    } catch (_) {
      // Retried while the trusted parent recorder remains active.
    } finally {
      starting = false;
    }
  };

  const syncParentState = () => {
    const freshContext = parentReplayContext(parentWindow);
    if (!freshContext) {
      stopLocalRecorder();
      return;
    }
    context = freshContext;
    void startLocalRecorder();
  };

  void startLocalRecorder();
  const stateTimer = window.setInterval(
    syncParentState,
    PARENT_STATE_INTERVAL_MS,
  );
  window.addEventListener('pagehide', () => {
    disposed = true;
    window.clearInterval(stateTimer);
    stopLocalRecorder();
  }, { once: true });
}

function boot() {
  const parentWindow = sameOriginParent();
  if (!parentWindow) return;

  const startedAt = performance.now();
  const poll = () => {
    const context = parentReplayContext(parentWindow);
    if (context) {
      startBridge(parentWindow, context);
      return;
    }
    if (performance.now() - startedAt < PARENT_READY_TIMEOUT_MS) {
      window.setTimeout(poll, POLL_INTERVAL_MS);
    }
  };
  poll();
}

boot();
