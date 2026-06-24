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
// DB version 2 adds `glbCache`: raw GLB bytes keyed by artifact URL. This is a
// CACHE of the backend artifact (pruned, re-fetchable) — the iframe is reloaded
// by Flutter on every fullscreen enter/exit, and without the cache each toggle
// would re-download the model from Azure.
let _idb = null;
const GLB_CACHE_MAX_ENTRIES = 6;

function _idbOpen() {
  if (_idb) return Promise.resolve(_idb);
  return new Promise((resolve, reject) => {
    const req = indexedDB.open('nova3d-editor', 2);
    req.onupgradeneeded = e => {
      const db = e.target.result;
      if (!db.objectStoreNames.contains('states'))   db.createObjectStore('states');
      if (!db.objectStoreNames.contains('glbCache')) db.createObjectStore('glbCache');
    };
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

// ── GLB byte cache ───────────────────────────────────────────────────────────
function _glbCacheGet(url) {
  return _idbOpen().then(db => new Promise(resolve => {
    try {
      const req = db.transaction('glbCache', 'readonly').objectStore('glbCache').get(url);
      req.onsuccess = e => resolve(e.target.result?.bytes ?? null);
      req.onerror   = () => resolve(null);
    } catch (_) { resolve(null); }
  })).catch(() => null);
}

async function _glbCachePut(url, bytes) {
  try {
    const db = await _idbOpen();
    await new Promise((resolve, reject) => {
      const tx = db.transaction('glbCache', 'readwrite');
      const store = tx.objectStore('glbCache');
      store.put({ ts: Date.now(), bytes }, url);
      // Prune oldest entries beyond the cap.
      const keysReq = store.getAllKeys();
      keysReq.onsuccess = () => {
        const keys = keysReq.result || [];
        if (keys.length <= GLB_CACHE_MAX_ENTRIES) return;
        const rowsReq = store.getAll();
        rowsReq.onsuccess = () => {
          const rows = rowsReq.result || [];
          keys.map((k, i) => ({ key: k, ts: rows[i]?.ts ?? 0 }))
              .sort((a, b) => a.ts - b.ts)
              .slice(0, keys.length - GLB_CACHE_MAX_ENTRIES)
              .forEach(({ key }) => store.delete(key));
        };
      };
      tx.oncomplete = resolve;
      tx.onerror = e => reject(e.target.error);
    });
  } catch (e) {
    console.warn('[nova3d] glb cache write failed:', e);
  }
}

async function _primeGlbCache(url) {
  if (!/^https?:/i.test(String(url || ''))) return;
  if (await _glbCacheGet(url)) return;
  try {
    const res = await fetch(url);
    if (!res.ok) return;
    _glbCachePut(url, await res.arrayBuffer());
  } catch (_) { /* cache priming is best-effort */ }
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
  // Best-effort: keep the current GLB's bytes cached so the next iframe
  // reload (Flutter fullscreen enter/exit re-mounts us) restores instantly
  // instead of re-downloading from Azure.
  void _primeGlbCache(state.currentModelUrl);
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
    // vertex colours / AO, emissive), no local reconstruction. Cache-first:
    // Flutter re-mounts this iframe on every fullscreen toggle, so the byte
    // cache makes those reboots instant instead of a network round-trip.
    const startLoad = async () => {
      _onResize();
      let src = url;
      const loadOptions = { sourceModelUrl: state.currentSourceModelUrl, recordHistory: false };
      if (/^https?:/i.test(url)) {
        let bytes = await _glbCacheGet(url);
        if (!bytes) {
          try {
            const res = await fetch(url);
            if (res.ok) {
              bytes = await res.arrayBuffer();
              void _glbCachePut(url, bytes);
            }
          } catch (_) { /* fall through to direct URL load */ }
        }
        if (bytes) {
          src = URL.createObjectURL(new Blob([bytes], { type: 'model/gltf-binary' }));
          loadOptions.canonicalUrl = url; // persist the real artifact URL, not blob:
        }
      }
      _loadModel(src, loadOptions);

      // Flutter animates the surrounding layout for a moment after re-mounting
      // the iframe; re-frame the camera on container resizes until it settles
      // so the model is never left cropped or mis-scaled.
      if (state.container) {
        const settleUntil = Date.now() + 3000;
        const ro = new ResizeObserver(() => {
          _onResize();
          if (state.loadedMeshes.length) _reframeCamera(state.modelGroup);
          if (Date.now() > settleUntil) ro.disconnect();
        });
        ro.observe(state.container);
        setTimeout(() => ro.disconnect(), 3500);
      }
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
