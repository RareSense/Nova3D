// IndexedDB-backed persistence for the full editor state (current scene +
// undo/redo stacks). Schema is frozen at version 2: existing payload shape
// must stay byte-identical so older saves keep loading.
//
// Database: `nova3d-editor` (version 1) with a single object store `states`,
// keyed by `editorStorageKey()` (derived from state.stateKey || state.viewerId).
//
// Cross-module hook: `restoreEditorState` needs to reframe the camera after
// the model swap. PR 11 will give us a direct import of `frameCameraToModel`
// + `onResize` from scene.js; for now the inline boot calls
// `setPersistenceSceneRefreshers({ onResize, reframeCamera })`.

/**
 * IndexedDB record shape stored under `editorStorageKey()` in the `states`
 * object store of the `nova3d-editor` database. Version is FROZEN at 2 — any
 * future change must bump SCHEMA_VERSION and provide a migration path in
 * `restoreEditorState`.
 * @typedef {Object} EditorPersistedState
 * @property {number} version                     Schema version (currently 2).
 * @property {number} timestamp                   Wall-clock ms at write.
 * @property {Object|null} codeArtifact
 * @property {string|null} modelUrl
 * @property {string} sourceModelUrl
 * @property {Object|null} modelArtifact
 * @property {Object|null} jointsArtifact
 * @property {import('./articulation.js').Joint[]} joints
 * @property {import('./history.js').SerializedSnapshot} currentState
 * @property {import('./history.js').SerializedSnapshot[]} undoHistory
 * @property {import('./history.js').SerializedSnapshot[]} redoHistory
 */

import { state, editorStorageKey } from '@nova/state.js';
import {
  captureSnapshot,
  snapshotToData,
  snapshotFromData,
  restoreSnapshot,
  disposeSnapshot,
} from '@nova/history.js';

export const SCHEMA_VERSION = 2;

let _onResize = () => {};
let _reframeCamera = () => {};

export function setPersistenceSceneRefreshers({ onResize, reframeCamera } = {}) {
  if (typeof onResize === 'function')      _onResize      = onResize;
  if (typeof reframeCamera === 'function') _reframeCamera = reframeCamera;
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
  // Capture the current scene as a snapshot and convert everything to plain
  // serialisable data BEFORE any await so we don't race with scene mutations.
  const current = captureSnapshot('_saved');
  if (!current) return;
  const payload = {
    version: SCHEMA_VERSION,
    timestamp: Date.now(),
    codeArtifact: state.currentCodeArtifact,
    modelUrl: state.currentModelUrl,
    sourceModelUrl: state.currentSourceModelUrl,
    modelArtifact: state.currentModelArtifact,
    jointsArtifact: state.currentJointsArtifact,
    joints: state.currentJoints,
    currentState: snapshotToData(current),
    undoHistory: state.undoHistory.map(snapshotToData),
    redoHistory: state.redoHistory.map(snapshotToData),
  };
  disposeSnapshot(current); // free Three.js memory; plain data is already copied
  try {
    await _idbSet(editorStorageKey(), payload);
  } catch (e) {
    console.warn('[nova3d] saveEditorState failed:', e);
  }
}

export async function restoreEditorState() {
  try {
    const data = await _idbGet(editorStorageKey());
    if (!data || data.version < SCHEMA_VERSION) return false;

    state.currentCodeArtifact   = data.codeArtifact ?? null;
    state.currentModelUrl       = data.modelUrl     ?? null;
    state.currentSourceModelUrl = data.sourceModelUrl ?? state.currentModelUrl ?? '';
    state.currentModelArtifact  = data.modelArtifact ?? null;
    state.currentJointsArtifact = data.jointsArtifact ?? null;
    state.currentJoints         = Array.isArray(data.joints) ? data.joints : [];

    // Rebuild undo/redo stacks first so syncHistoryUi (called by restoreSnapshot)
    // sees the correct history.
    state.undoHistory.splice(0, state.undoHistory.length,
      ...(data.undoHistory ?? []).map(snapshotFromData).filter(Boolean));
    state.redoHistory.splice(0, state.redoHistory.length,
      ...(data.redoHistory ?? []).map(snapshotFromData).filter(Boolean));

    const snap = snapshotFromData(data.currentState);
    if (!snap || !restoreSnapshot(snap, { skipPersist: true })) return false;

    // Re-frame the camera once the container has its real dimensions.
    requestAnimationFrame(() => { _onResize(); if (state.loadedMeshes.length) _reframeCamera(state.modelGroup); });
    return true;
  } catch (e) {
    console.warn('[nova3d] restoreEditorState failed:', e);
    return false;
  }
}
