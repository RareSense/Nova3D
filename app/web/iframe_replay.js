// WebGL replay bridge for same-origin embedded viewers.
//
// PostHog's top-level rrweb recorder serializes DOM inside same-origin iframes,
// but its canvas sampler only scans canvases in the recorder's own document.
// Nova3D renders both the showcase and editor inside iframes, so their DOM is
// present in a replay while their WebGL pixels are otherwise absent.
//
// When (and only when) the trusted parent is already recording, this module
// starts a recording-only PostHog instance in the iframe. It bootstraps the
// parent's session id and distinct id, while using memory persistence so the
// iframe receives its own window id. PostHog natively plays multi-window
// sessions as one timeline, switching to the active iframe while it is used.
//
// Privacy and self-hosting invariants:
//   * no project key or company endpoint is committed here;
//   * configuration is copied at runtime from a same-origin parent;
//   * forks without an initialized parent PostHog client do nothing;
//   * the child captures no product events, pageviews, heatmaps, or profiles;
//   * recording follows the parent's start/stop state.

const POLL_INTERVAL_MS = 250;
const PARENT_READY_TIMEOUT_MS = 30000;
const PARENT_STATE_INTERVAL_MS = 1000;
const MAX_REPLAY_FPS = 2;
const MIN_QUALITY = 0.1;
const MAX_QUALITY = 1;

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

function safeHttpUrl(value) {
  if (typeof value !== 'string' || !value.trim()) return null;
  try {
    const parsed = new URL(value);
    return parsed.protocol === 'https:' || parsed.protocol === 'http:'
      ? parsed.toString().replace(/\/$/, '')
      : null;
  } catch (_) {
    return null;
  }
}

function parentRecordingConfig(parentPostHog) {
  const config = parentPostHog?.config;
  const token = config?.token;
  const sessionId = parentPostHog?.get_session_id?.();
  const distinctId = parentPostHog?.get_distinct_id?.();
  const apiHost = safeHttpUrl(config?.api_host);
  const uiHost = safeHttpUrl(config?.ui_host);

  if (typeof token !== 'string' || !token.trim()) return null;
  if (typeof sessionId !== 'string' || !sessionId.trim()) return null;
  if (typeof distinctId !== 'string' || !distinctId.trim()) return null;
  if (!apiHost) return null;

  const parentCapture = config?.session_recording?.captureCanvas || {};
  const parentCanvasCapture = config?.session_recording?.canvasCapture || {};
  const parentFps = finiteNumber(parentCapture.canvasFps, MAX_REPLAY_FPS, 1, 12);

  return {
    token: token.trim(),
    sessionId,
    distinctId,
    apiHost,
    uiHost: uiHost || undefined,
    defaults: typeof config?.defaults === 'string' ? config.defaults : undefined,
    canvasFps: Math.min(parentFps, MAX_REPLAY_FPS),
    canvasQuality: String(finiteNumber(
      parentCapture.canvasQuality,
      0.8,
      MIN_QUALITY,
      MAX_QUALITY,
    )),
    resolutionScale: finiteNumber(
      parentCanvasCapture.resolutionScale,
      1,
      0.1,
      1,
    ),
  };
}

function installPostHogStub(apiHost) {
  if (window.posthog?.__SV) return window.posthog;

  const posthog = [];
  window.posthog = posthog;
  posthog._i = [];
  posthog.__SV = 1;
  posthog.init = function init(token, config, name) {
    const script = document.createElement('script');
    script.type = 'text/javascript';
    script.crossOrigin = 'anonymous';
    script.async = true;
    script.src = `${apiHost.replace('.i.posthog.com', '-assets.i.posthog.com')}/static/array.js`;
    const firstScript = document.getElementsByTagName('script')[0];
    firstScript?.parentNode?.insertBefore(script, firstScript);

    let instance;
    if (name !== undefined) {
      instance = posthog[name] = [];
    } else {
      name = 'posthog';
      instance = posthog;
    }
    instance.people = instance.people || [];
    instance.toString = function toString(detail) {
      let value = name === 'posthog' ? 'posthog' : `posthog.${name}`;
      return detail ? `${value}.people (stub)` : `${value} (stub)`;
    };
    instance.people.toString = () => instance.toString(true);

    const methods = [
      'init', 'capture', 'get_distinct_id', 'get_session_id',
      'sessionRecordingStarted', 'startSessionRecording',
      'stopSessionRecording', 'set_config', 'opt_out_capturing',
    ];
    for (const method of methods) {
      instance[method] = (...args) => instance.push([method, ...args]);
    }
    posthog._i.push([token, config, name]);
  };
  return posthog;
}

function stripNetworkUrl(request) {
  if (!request || typeof request.name !== 'string') return request;
  try {
    const url = new URL(request.name, window.location.origin);
    url.search = '';
    url.hash = '';
    request.name = url.toString();
  } catch (_) {
    request.name = request.name.split(/[?#]/, 1)[0];
  }
  return request;
}

function forceRecording(instance) {
  try {
    // The parent already passed its project's sampling/privacy gates. Override
    // the child's independent sampling decision so its canvas cannot vanish
    // from a session the parent is actively recording.
    instance?.startSessionRecording?.({
      sampling: true,
      linked_flag: true,
      url_trigger: true,
      event_trigger: true,
    });
  } catch (_) {
    // Replay must never become load-bearing for the viewer.
  }
}

function startChildRecorder(parentPostHog, inherited) {
  if (window.__nova3dIframeReplayStarted) return;
  window.__nova3dIframeReplayStarted = true;

  const childPostHog = installPostHogStub(inherited.apiHost);
  childPostHog.init(inherited.token, {
    api_host: inherited.apiHost,
    ...(inherited.uiHost ? { ui_host: inherited.uiHost } : {}),
    ...(inherited.defaults ? { defaults: inherited.defaults } : {}),
    bootstrap: {
      distinctID: inherited.distinctId,
      sessionID: inherited.sessionId,
    },

    // A distinct in-memory persistence namespace gives this iframe its own
    // window id without mutating the parent client's cookies/local storage.
    persistence: 'memory',
    person_profiles: 'never',
    capture_pageview: false,
    capture_pageleave: false,
    autocapture: false,
    rageclick: false,
    capture_heatmaps: false,
    capture_performance: false,
    disable_surveys: true,
    disable_session_recording: false,
    property_denylist: [
      '$current_url', '$initial_current_url', '$referrer', '$initial_referrer',
    ],
    session_recording: {
      maskAllInputs: true,
      maskInputOptions: { password: true, email: false, text: false },
      maskTextSelector: '[data-ph-mask]',
      blockSelector: '[data-ph-block]',
      maskCapturedNetworkRequestFn: stripNetworkUrl,
      // This must stay false for a same-origin child. rrweb delegates iframe
      // recording to the parent when true, which is the exact path that omits
      // nested canvas sampling.
      recordCrossOriginIframes: false,
      captureCanvas: {
        recordCanvas: true,
        canvasFps: inherited.canvasFps,
        canvasQuality: inherited.canvasQuality,
      },
      canvasCapture: { resolutionScale: inherited.resolutionScale },
    },
    loaded: forceRecording,
  });

  let childInstance = childPostHog;
  let lastParentRecording = true;
  const syncParentState = () => {
    let parentIsRecording = false;
    try {
      parentIsRecording = parentPostHog.sessionRecordingStarted?.() === true;
    } catch (_) {}

    if (parentIsRecording === lastParentRecording) return;
    lastParentRecording = parentIsRecording;

    // The real SDK replaces the stub asynchronously; always read the current
    // global before forwarding a start/stop transition.
    childInstance = window.posthog || childInstance;
    try {
      if (parentIsRecording) forceRecording(childInstance);
      else childInstance?.stopSessionRecording?.();
    } catch (_) {}
  };

  const stateTimer = window.setInterval(syncParentState, PARENT_STATE_INTERVAL_MS);
  window.addEventListener('pagehide', () => {
    window.clearInterval(stateTimer);
    try { (window.posthog || childInstance)?.stopSessionRecording?.(); } catch (_) {}
  }, { once: true });
}

function boot() {
  const parentWindow = sameOriginParent();
  if (!parentWindow) return;

  const startedAt = performance.now();
  const poll = () => {
    const parentPostHog = parentWindow.posthog;
    let recording = false;
    try { recording = parentPostHog?.sessionRecordingStarted?.() === true; }
    catch (_) {}

    const inherited = recording ? parentRecordingConfig(parentPostHog) : null;
    if (inherited) {
      startChildRecorder(parentPostHog, inherited);
      return;
    }
    if (performance.now() - startedAt < PARENT_READY_TIMEOUT_MS) {
      window.setTimeout(poll, POLL_INTERVAL_MS);
    }
  };
  poll();
}

boot();
