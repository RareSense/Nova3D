// UV maps bridge (editor → Flutter). Requests UV-atlas generation for the
// CURRENT version's source code from the parent Flutter app, which runs the
// generate_uv_maps workflow, packages the checker GLB + atlas SVGs into a zip,
// and triggers the browser download. This module only sends the request and
// reflects status on the toolbar button — it never produces an asset version.

import { state } from '@nova/state.js';
import { track } from '@nova/analytics.js';

let _activeUvRequestId = '';

function uvButton() {
  return document.getElementById('uvMapsBtn');
}

function setUvBusy(busy) {
  const btn = uvButton();
  if (!btn) return;
  btn.disabled = busy;
  btn.classList.toggle('busy', busy);
}

function showUvStatus(message, isError = false) {
  const btn = uvButton();
  if (btn) btn.title = message;
  // Surface the message in the AI-edit status line when it's on screen.
  const el = document.getElementById('aiEditStatus');
  if (el) {
    el.textContent = message;
    el.classList.add('active');
    el.classList.toggle('error', isError);
  }
}

export function requestUvMaps() {
  const code = state.currentCodeArtifact;
  if (!code || (!code.uri && !code.url)) {
    showUvStatus('This model has no editable code yet. Generate it again first.', true);
    return;
  }
  if (_activeUvRequestId) return;
  _activeUvRequestId = `uv-${Date.now()}-${Math.random().toString(16).slice(2)}`;
  setUvBusy(true);
  showUvStatus('Generating UV maps…');
  track('uv_maps_requested', {
    atlas_mode: 'budget',
    mesh_count: state.loadedMeshes.length,
    source: 'viewer',
  });
  try {
    window.parent?.postMessage({
      type: 'nova3d-uv-request',
      viewerId: state.viewerId,
      requestId: _activeUvRequestId,
      codeArtifact: state.currentCodeArtifact,
      sourceWorkflowId: state.currentSourceWorkflowId || '',
      atlasMode: 'budget',
    }, window.location.origin);
  } catch (_) {
    _activeUvRequestId = '';
    setUvBusy(false);
    showUvStatus('Could not start UV map generation.', true);
  }
}

export function setupUvBridge() {
  window.addEventListener('message', (event) => {
    if (event.origin !== window.location.origin || event.source !== window.parent) return;
    const data = event.data || {};
    if (data.type !== 'nova3d-uv-result') return;
    if (data.requestId !== _activeUvRequestId) return;
    if (data.status === 'running') {
      showUvStatus(data.message || 'Generating UV maps…');
      return;
    }
    _activeUvRequestId = '';
    setUvBusy(false);
    const completed = data.status === 'completed';
    showUvStatus(
      data.message || (completed ? 'UV maps downloaded.' : 'UV map generation failed.'),
      !completed,
    );
  });
}
