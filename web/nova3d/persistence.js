// IndexedDB-backed persistence for the editor session, pointer-first.
//
// The backend (GraphFlow DB + Azure artifacts) is the source of truth for
// every generated/AI-edited model state. Persistence therefore stores only
// POINTERS (model/code/joints artifacts + signed URLs) and restores by
// re-loading the GLB from the backend — which round-trips the full asset
// (materials, vertex colours / baked AO, emissive) with perfect fidelity.
//
// Local mesh edits (sculpt/merge/subdivide/material overrides) are ephemeral
// previews by design: they live in the in-memory undo stack for the session
// and are NOT persisted across reloads.
//
// Database: `nova3d-editor` (version 1) with a single object store `states`,
// keyed by `editorStorageKey()` (derived from state.stateKey || state.viewerId).
//
// Cross-module hooks (set from main.js to avoid import cycles):
//   setPersistenceSceneRefreshers({ onResize, reframeCamera })
//   setPersistenceModelLoader(fn)   — fn(url, options) -> loadGLB

/**
 * IndexedDB record shape stored under `editorStorageKey()` in the `states`
 * object store of the `nova3d-editor` database.
 *
 * Version history:
 *   2 — legacy fat records: pointers + serialized currentState/undo/redo
 *       geometry (lossy: dropped COLOR_0 vertex colours and material flags).
 *   3 — pointer-only records (current). v2 records remain readable: restore
 *       uses their pointers and ignores the serialized geometry.
 * @typedef {Object} EditorPersistedState
 * @property {number} version                     Schema version (currently 3).
 * @property {number} timestamp                   Wall-clock ms at write.
 * @property {Object|null} codeArtifact
 * @property {string|null} modelUrl
 * @property {string} sourceModelUrl
 * @property {Object|null} modelArtifact
 * @property {Object|null} jointsArtifact
 * @property {import('./articulation.js').Joint[]} joints
 */

import { state, editorStorageKey } from '@nova/state.js';

export const SCHEMA_VERSION = 3;
const MIN_READABLE_VERSION = 2;

let _onResize = () => {};
let _reframeCamera = () => {};
let _loadModel = null;

export function setPersistenceSceneRefreshers({ onResize, reframeCamera } = {}) {
  if (typeof onResize === 'function')      _onResize      = onResize;
  if (typeof reframeCamera === 'function') _reframeCamera = reframeCamera;
}

export function setPersistenceModelLoader(fn) {
  _loadModel = typeof fn === 'function' ? fn : null;
}

// ── IndexedDB primitives (lazy-open, shared connection) ──────────────────────
let _idb = null;

function _idbOpen() {
  if (_idb) return Promise.resolve(_idb);
  return new Promise((resolve, reject) => {
    const req = indexedDB.open('nova3d-editor', 1);
    req.onupgradeneeded = e => e.target.result.createObjectStore('states');
    req.onsuccess = e => { _idb = e.target.result; resolve(_idb); };
    req.onerror   = e => reject(e.target.error);
  });
}

function _idbSet(key, value) {
  return _idbOpen().then(db => new Promise((resolve, reject) => {
    const tx = db.transaction('states', 'readwrite');
    tx.objectStore('states').put(value, key);
    tx.oncomplete = resolve;
    tx.onerror = e => reject(e.target.error);
  }));
}

function _idbGet(key) {
  return _idbOpen().then(db => new Promise((resolve, reject) => {
    const tx = db.transaction('states', 'readonly');
    const req = tx.objectStore('states').get(key);
    req.onsuccess = e => resolve(e.target.result ?? null);
    req.onerror   = e => reject(e.target.error);
  }));
}

// ── Debounced save ───────────────────────────────────────────────────────────
let _saveTimer = null;

export function saveEditorState() {
  // Debounce rapid calls (every undo push, resize, etc.) into one write.
  clearTimeout(_saveTimer);
  _saveTimer = setTimeout(_persistEditorState, 800);
}

export function flushEditorState() {
  clearTimeout(_saveTimer);
  _saveTimer = null;
  return _persistEditorState();
}

async function _persistEditorState() {
  if (!state.loadedMeshes.length) return;
  const payload = {
    version: SCHEMA_VERSION,
    timestamp: Date.now(),
    codeArtifact: state.currentCodeArtifact,
    modelUrl: state.currentModelUrl,
    sourceModelUrl: state.currentSourceModelUrl,
    modelArtifact: state.currentModelArtifact,
    jointsArtifact: state.currentJointsArtifact,
    joints: state.currentJoints,
  };
  try {
    await _idbSet(editorStorageKey(), payload);
  } catch (e) {
    console.warn('[nova3d] saveEditorState failed:', e);
  }
}

// ── Restore ──────────────────────────────────────────────────────────────────
function _restorableUrl(data) {
  // blob: URLs die with the document that created them; http(s)/data: survive.
  const candidates = [data.modelUrl, data.modelArtifact?.url];
  for (const raw of candidates) {
    const url = String(raw || '').trim();
    if (/^(https?:|data:)/i.test(url)) return url;
  }
  return null;
}

export async function restoreEditorState() {
  try {
    const data = await _idbGet(editorStorageKey());
    if (!data || data.version < MIN_READABLE_VERSION) return false;

    const url = _restorableUrl(data);
    if (!url || !_loadModel) return false;

    state.currentCodeArtifact   = data.codeArtifact ?? null;
    state.currentModelUrl       = data.modelUrl     ?? null;
    state.currentSourceModelUrl = data.sourceModelUrl ?? data.modelUrl ?? '';
    state.currentModelArtifact  = data.modelArtifact ?? null;
    state.currentJointsArtifact = data.jointsArtifact ?? null;
    state.currentJoints         = Array.isArray(data.joints) ? data.joints : [];

    // Re-load the GLB from the backend artifact — full fidelity (materials,
    // vertex colours / AO, emissive), no local reconstruction. Defer until the
    // container has real dimensions so the camera frames correctly.
    const startLoad = () => {
      _onResize();
      _loadModel(url, { sourceModelUrl: state.currentSourceModelUrl, recordHistory: false });
    };
    if (state.container?.clientWidth > 0 && state.container?.clientHeight > 0) {
      startLoad();
    } else if (state.container) {
      const ro = new ResizeObserver((_, obs) => {
        if (state.container.clientWidth > 0 && state.container.clientHeight > 0) {
          obs.disconnect();
          startLoad();
        }
      });
      ro.observe(state.container);
    } else {
      requestAnimationFrame(startLoad);
    }
    return true;
  } catch (e) {
    console.warn('[nova3d] restoreEditorState failed:', e);
    return false;
  }
}
