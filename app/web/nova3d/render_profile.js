// Shared adaptive rendering policy for the editor and showcase. The initial
// profile uses browser hardware/network hints; auto mode can also downgrade a
// session when sustained frame pacing proves the device is struggling.

const LOW_POWER_FRAME_MS = 1000 / 30;
const SLOW_FRAME_MS = 27;
const SLOW_FRAME_SCORE_LIMIT = 45;
const OVERRIDE_KEY = 'nova3d_render_profile';

function readOverride() {
  try {
    const query = new URLSearchParams(window.location.search).get('renderProfile');
    if (query === 'low' || query === 'high') return query;
  } catch (_) {}
  try {
    const stored = localStorage.getItem(OVERRIDE_KEY);
    if (stored === 'low' || stored === 'high') return stored;
  } catch (_) {}
  return 'auto';
}

function initialLowPowerReason() {
  const connection = navigator.connection
    || navigator.mozConnection
    || navigator.webkitConnection;
  if (connection?.saveData) return 'save-data';
  if (['slow-2g', '2g', '3g'].includes(connection?.effectiveType)) {
    return 'slow-connection';
  }

  const memory = Number(navigator.deviceMemory || 0);
  if (memory > 0 && memory <= 4) return 'device-memory';

  const cores = Number(navigator.hardwareConcurrency || 0);
  if (cores > 0 && cores <= 4) return 'cpu-threads';

  try {
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
      return 'reduced-motion';
    }
  } catch (_) {}

  // Retina/high-DPI screens multiply framebuffer cost. Treat a large physical
  // display paired with a mid-range CPU as low-power before fullscreen allocates
  // its first oversized WebGL buffer.
  try {
    const dpr = Math.max(1, Number(window.devicePixelRatio || 1));
    const physicalPixels = Number(window.screen?.width || 0)
      * Number(window.screen?.height || 0) * dpr * dpr;
    if (physicalPixels >= 4_000_000 && cores > 0 && cores <= 8) {
      return 'display-pixel-cost';
    }
  } catch (_) {}

  return '';
}

class AdaptiveRenderProfile {
  constructor() {
    this.override = readOverride();
    this.lowPowerReason = this.override === 'low'
      ? 'manual'
      : (this.override === 'high' ? '' : initialLowPowerReason());
    this.lowPower = Boolean(this.lowPowerReason);
    this.listeners = new Set();
    this.lastRafAt = 0;
    this.lastRenderAt = 0;
    this.slowFrameScore = 0;
    this._publishMode();
  }

  onChange(listener) {
    if (typeof listener !== 'function') return () => {};
    this.listeners.add(listener);
    listener(this.lowPower, this.lowPowerReason);
    return () => this.listeners.delete(listener);
  }

  shouldRender(now) {
    if (typeof document !== 'undefined' && document.hidden) {
      this.lastRafAt = now;
      this.lastRenderAt = now;
      return false;
    }

    if (this.lastRafAt > 0 && this.override === 'auto' && !this.lowPower) {
      const delta = now - this.lastRafAt;
      // Ignore tab suspension and one-off GLB parse stalls. Sustained slow RAF
      // cadence is the useful signal that the active renderer is too expensive.
      if (delta > 0 && delta < 250) {
        this.slowFrameScore = delta >= SLOW_FRAME_MS
          ? this.slowFrameScore + 1
          : Math.max(0, this.slowFrameScore - 0.5);
        if (this.slowFrameScore >= SLOW_FRAME_SCORE_LIMIT) {
          this._enableLowPower('measured-frame-rate');
        }
      }
    }
    this.lastRafAt = now;

    if (this.lowPower
        && this.lastRenderAt > 0
        && now - this.lastRenderAt < LOW_POWER_FRAME_MS - 1) {
      return false;
    }
    this.lastRenderAt = now;
    return true;
  }

  pixelRatio() {
    return this.lowPower ? 1 : Math.min(Number(window.devicePixelRatio || 1), 2);
  }

  _enableLowPower(reason) {
    if (this.lowPower || this.override === 'high') return;
    this.lowPower = true;
    this.lowPowerReason = reason;
    this._publishMode();
    for (const listener of this.listeners) {
      try { listener(true, reason); } catch (_) {}
    }
  }

  _publishMode() {
    try {
      document.documentElement.dataset.renderProfile = this.lowPower ? 'low' : 'high';
      document.documentElement.dataset.renderProfileReason = this.lowPowerReason || 'default';
    } catch (_) {}
  }
}

export const adaptiveRenderProfile = new AdaptiveRenderProfile();
