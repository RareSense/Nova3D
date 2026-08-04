// Viewer-side analytics emitter.
//
// The editor runs in a same-origin iframe and deliberately does NOT initialise
// its own posthog-js. A second init would mint a second distinct_id and split
// one user's work across two sessions. Instead the viewer posts events up to
// the Flutter parent, which owns the single identified PostHog client and
// forwards them (see `_onWindowMessage` in glb_viewer_web.dart).
//
// Session REPLAY of this iframe needs no wiring: rrweb records same-origin
// iframe DOM as part of the parent recording. This module is only about
// structured events.
//
// Everything here is best-effort. A failure to report must never interfere
// with a modelling action, so every call is wrapped and silently ignored.

import { state } from '@nova/state.js';

/** Fire-and-forget a single event to the parent app. */
export function track(event, properties = {}) {
  try {
    window.parent?.postMessage({
      type: 'nova3d-analytics',
      viewerId: state.viewerId,
      event,
      properties: properties || {},
    }, window.location.origin);
  } catch (_) {
    // Analytics is never load-bearing.
  }
}

// ── Throttling ───────────────────────────────────────────────────────────────
// Continuous interactions (joint sliders, sculpt strokes, transform drags) fire
// per animation frame. Sending one event each would swamp ingestion and cost
// real money for zero extra insight. These collapse into one trailing event per
// burst, carrying the occurrence count so intensity is still visible.

const _pending = new Map();
const THROTTLE_MS = 2000;

export function trackThrottled(key, event, properties = {}, waitMs = THROTTLE_MS) {
  const existing = _pending.get(key);
  if (existing) {
    existing.count += 1;
    // Last write wins: the final position of a drag is the interesting one.
    existing.properties = properties;
    return;
  }
  const entry = {
    event,
    count: 1,
    properties,
    timer: window.setTimeout(() => {
      const done = _pending.get(key);
      _pending.delete(key);
      if (!done) return;
      track(done.event, { ...done.properties, occurrences: done.count });
    }, waitMs),
  };
  _pending.set(key, entry);
}

/** Flush pending throttled events immediately. Bound to pagehide so a burst
 *  that ends with the user closing the tab is not lost. */
export function flushAnalytics() {
  for (const entry of _pending.values()) {
    try {
      window.clearTimeout(entry.timer);
      track(entry.event, { ...entry.properties, occurrences: entry.count });
    } catch (_) {}
  }
  _pending.clear();
}

try {
  window.addEventListener('pagehide', flushAnalytics);
} catch (_) {}
