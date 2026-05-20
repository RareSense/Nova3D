// Left-rail flyout open/close, compact-vs-full UI mode, and the fullscreen
// postMessage bridge to the parent Flutter app.
//
// `fsStorageKey()` (sessionStorage) preserves the editor mode across iframe
// reloads (Safari reparents iframes on DOM moves and reloads them).

import { state, fsStorageKey } from '@nova/state.js';
import { setMode, onResize, frameCameraToModel } from '@nova/scene.js';
import { updateMeshList, updateHighlights } from '@nova/selection.js';
import { saveEditorState } from '@nova/persistence.js';

export function setupFlyouts() {
  document.querySelectorAll('.et-btn:not(.et-btn-soon)').forEach(btn => {
    btn.addEventListener('click', e => {
      e.stopPropagation();
      const id = btn.dataset.flyout, flyout = document.getElementById(id);
      const wasOpen = flyout.classList.contains('open');
      closeFlyouts();
      if (!wasOpen) {
        flyout.classList.add('open');
        btn.classList.add('active');
        document.body.classList.add('flyout-open');
      }
    });
  });
  const soonBtn = document.getElementById('matSoonBtn');
  if (soonBtn) {
    soonBtn.addEventListener('click', e => {
      e.stopPropagation();
      const tip = soonBtn.querySelector('.et-tip');
      if (!tip) return;
      tip.style.display = 'block';
      clearTimeout(soonBtn._soonTimer);
      soonBtn._soonTimer = setTimeout(() => { tip.style.display = ''; }, 2000);
    });
  }
}

export function closeFlyouts() {
  document.querySelectorAll('.flyout').forEach(f => f.classList.remove('open'));
  document.querySelectorAll('.et-btn').forEach(b => b.classList.remove('active'));
  document.body.classList.remove('flyout-open');
}

export function isFullUi() {
  return document.body.classList.contains('full-ui');
}

export function setViewportMode(full) {
  document.body.classList.toggle('full-ui', full);
  document.body.classList.toggle('compact', !full);
  const btn = document.getElementById('fullscreenToggle');
  if (btn) {
    btn.title = full ? 'Return to studio preview' : 'Open full editor';
    btn.setAttribute('aria-label', btn.title);
  }
  if (!full) {
    setMode('orbit');
    state.selectedMeshIndices.clear();
    updateHighlights();
    updateMeshList();
    closeFlyouts();
  }
  // Persist the mode so that if the browser reloads the iframe after a DOM
  // move (a known Safari behaviour), it can restore the correct UI state.
  try {
    if (full) sessionStorage.setItem(fsStorageKey(), '1');
    else      sessionStorage.removeItem(fsStorageKey());
  } catch (_) {}
  saveEditorState();
  onResize();
  if (state.loadedMeshes.length) {
    if (full) {
      frameCameraToModel(state.modelGroup);
    } else {
      // Delay re-framing so the overlay can finish resizing to compact
      // dimensions before we compute the camera distance.
      requestAnimationFrame(() => { onResize(); frameCameraToModel(state.modelGroup); });
    }
  }
}

export function setupViewportMode() {
  const btn = document.getElementById('fullscreenToggle');
  if (btn) {
    btn.onclick = async () => {
      if (isFullUi()) {
        saveEditorState();
        setViewportMode(false);
        if (window.parent && window.parent !== window) {
          window.parent.postMessage({ type: 'nova3d-viewer-fullscreen', action: 'exit', viewerId: state.viewerId }, '*');
        }
        return;
      }
      saveEditorState();
      setViewportMode(true);
      if (window.parent && window.parent !== window) {
        window.parent.postMessage({ type: 'nova3d-viewer-fullscreen', action: 'enter', viewerId: state.viewerId }, '*');
      }
    };
  }
  window.addEventListener('message', event => {
    const data = event.data || {};
    if (data.type === 'nova3d-viewer-fullscreen-state') {
      setViewportMode(Boolean(data.full));
    }
  });
}
