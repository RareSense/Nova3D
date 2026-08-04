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
// Database: `nova3d-editor` (version 2) with `states` and `glbCache` stores,
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
const IDB_NAME = 'nova3d-editor';
const IDB_VERSION = 2;
const IDB_OPEN_TIMEOUT_MS = 1000;
const IDB_OPERATION_TIMEOUT_MS = 1000;
const IDB_DELETE_TIMEOUT_MS = 1500;

let _idb = null;
let _idbOpenPromise = null;
let _cancelIdbOpen = null;
let _persistenceDisabled = false;
const GLB_CACHE_MAX_ENTRIES = 6;
const GLB_FETCH_TIMEOUT_MS = 30000;
const CONTAINER_READY_TIMEOUT_MS = 4000;

// Loading against a zero-sized iframe is not ideal, but waiting forever is
// worse: hidden/remounted editors do not always emit a useful ResizeObserver
// notification. Run exactly once when the container becomes usable, or at the
// deadline so the loader can still establish the model and recover on resize.
function _runWhenContainerReady(action) {
  let finished = false;
  let observer = null;
  let deadline = null;

  const finish = () => {
    if (finished) return;
    finished = true;
    if (observer) observer.disconnect();
    if (deadline !== null) clearTimeout(deadline);
    void action();
  };

  if (!state.container) {
    requestAnimationFrame(finish);
    return;
  }
  if (state.container.clientWidth > 0 && state.container.clientHeight > 0) {
    finish();
    return;
  }

  deadline = setTimeout(finish, CONTAINER_READY_TIMEOUT_MS);
  if (typeof ResizeObserver === 'function') {
    observer = new ResizeObserver(() => {
      if (state.container?.clientWidth > 0 && state.container?.clientHeight > 0) finish();
    });
    observer.observe(state.container);
    // Cover a size change between the first check and observer registration.
    if (state.container.clientWidth > 0 && state.container.clientHeight > 0) finish();
  }
}

function _glbCacheKey(rawUrl) {
  try {
    const url = new URL(rawUrl);
    const names = [...url.searchParams.keys()];
    const isSigned = names.some(name => {
      const lower = name.toLowerCase();
      return lower === 'sig' || lower === 'signature'
        || lower === 'x-amz-signature' || lower === 'x-goog-signature';
    });
    if (isSigned) {
      names.forEach(name => {
        const lower = name.toLowerCase();
        if (['sv','ss','srt','sp','se','st','spr','sig','sr','skoid','sktid','skt','ske','sks','skv'].includes(lower)
            || lower.startsWith('x-amz-') || lower.startsWith('x-goog-')) {
          url.searchParams.delete(name);
        }
      });
    }
    url.hash = '';
    return url.toString();
  } catch (_) {
    return rawUrl;
  }
}

async function _fetchGlbBytes(url) {
  const controller = typeof AbortController === 'function' ? new AbortController() : null;
  const timer = controller
    ? setTimeout(() => controller.abort(), GLB_FETCH_TIMEOUT_MS)
    : null;
  try {
    const response = await fetch(url, {
      mode: 'cors',
      credentials: 'omit',
      ...(controller ? { signal: controller.signal } : {}),
    });
    if (!response.ok) return null;
    // Fetch resolves at headers; keep the deadline active through the body.
    return await response.arrayBuffer();
  } finally {
    if (timer !== null) clearTimeout(timer);
  }
}

function _storageError(message, cause = null) {
  const error = new Error(message);
  if (cause) error.cause = cause;
  return error;
}

function _closeIdb() {
  const db = _idb;
  _idb = null;
  if (!db) return;
  try { db.close(); } catch (_) {}
}

function _idbOpen() {
  if (_persistenceDisabled) {
    return Promise.reject(_storageError('Editor persistence is disabled.'));
  }
  if (_idb) return Promise.resolve(_idb);
  if (_idbOpenPromise) return _idbOpenPromise;

  let cancelOpen = () => {};
  const attempt = new Promise((resolve, reject) => {
    let request = null;
    let settled = false;
    const timer = setTimeout(() => {
      fail(_storageError('IndexedDB open timed out.'));
      try { request?.transaction?.abort(); } catch (_) {}
    }, IDB_OPEN_TIMEOUT_MS);

    const finish = (callback, value) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      callback(value);
    };
    const fail = error => finish(reject, error);
    cancelOpen = () => fail(_storageError('IndexedDB open cancelled.'));

    try {
      request = indexedDB.open(IDB_NAME, IDB_VERSION);
      request.onblocked = () => fail(_storageError('IndexedDB open was blocked.'));
      request.onerror = event => fail(
        _storageError('IndexedDB open failed.', event.target?.error),
      );
      request.onupgradeneeded = event => {
        const db = event.target.result;
        if (!db.objectStoreNames.contains('states')) db.createObjectStore('states');
        if (!db.objectStoreNames.contains('glbCache')) db.createObjectStore('glbCache');
      };
      request.onsuccess = event => {
        const db = event.target.result;
        if (settled || _persistenceDisabled) {
          try { db.close(); } catch (_) {}
          return;
        }
        db.onversionchange = () => {
          try { db.close(); } catch (_) {}
          if (_idb === db) {
            _idb = null;
            _idbOpenPromise = null;
            _cancelIdbOpen = null;
          }
        };
        _idb = db;
        finish(resolve, db);
      };
    } catch (error) {
      fail(_storageError('IndexedDB is unavailable.', error));
    }
  });

  _idbOpenPromise = attempt;
  _cancelIdbOpen = cancelOpen;
  const cleanup = () => {
    if (_idbOpenPromise === attempt) _idbOpenPromise = null;
    if (_cancelIdbOpen === cancelOpen) _cancelIdbOpen = null;
  };
  attempt.then(cleanup, cleanup);
  return attempt;
}

function _idbTransaction(storeName, mode, operation) {
  if (_persistenceDisabled) {
    return Promise.reject(_storageError('Editor persistence is disabled.'));
  }
  return _idbOpen().then(db => new Promise((resolve, reject) => {
    let transaction = null;
    let settled = false;
    let result;
    const timer = setTimeout(() => {
      fail(_storageError(`IndexedDB ${storeName} transaction timed out.`));
    }, IDB_OPERATION_TIMEOUT_MS);

    const finish = (callback, value) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      callback(value);
    };
    const fail = error => {
      finish(reject, error);
      try { transaction?.abort(); } catch (_) {}
    };
    const setResult = value => { result = value; };

    try {
      transaction = db.transaction(storeName, mode);
      transaction.oncomplete = () => finish(resolve, result);
      transaction.onerror = event => fail(
        _storageError(`IndexedDB ${storeName} transaction failed.`, event.target?.error),
      );
      transaction.onabort = event => fail(
        _storageError(`IndexedDB ${storeName} transaction aborted.`, event.target?.error),
      );
      operation(transaction.objectStore(storeName), setResult, fail);
    } catch (error) {
      fail(_storageError(`IndexedDB ${storeName} transaction could not start.`, error));
    }
  }));
}

function _idbSet(key, value) {
  if (_persistenceDisabled) return Promise.resolve();
  return _idbTransaction('states', 'readwrite', (store, _setResult, fail) => {
    const request = store.put(value, key);
    request.onerror = event => fail(
      _storageError('IndexedDB state write failed.', event.target?.error),
    );
  });
}

function _idbGet(key) {
  return _idbTransaction('states', 'readonly', (store, setResult, fail) => {
    const request = store.get(key);
    request.onsuccess = event => setResult(event.target.result ?? null);
    request.onerror = event => fail(
      _storageError('IndexedDB state read failed.', event.target?.error),
    );
  });
}

// ── GLB byte cache ───────────────────────────────────────────────────────────
function _glbCacheGet(url) {
  if (_persistenceDisabled) return Promise.resolve(null);
  const key = _glbCacheKey(url);
  return _idbTransaction('glbCache', 'readonly', (store, setResult, fail) => {
    const request = store.get(key);
    request.onsuccess = event => setResult(event.target.result?.bytes ?? null);
    request.onerror = event => fail(
      _storageError('IndexedDB GLB cache read failed.', event.target?.error),
    );
  }).catch(() => null);
}

async function _glbCachePut(url, bytes) {
  if (_persistenceDisabled) return;
  try {
    const key = _glbCacheKey(url);
    await _idbTransaction('glbCache', 'readwrite', (store, _setResult, fail) => {
      store.put({ ts: Date.now(), bytes }, key);
      // Prune oldest entries beyond the cap.
      const keysReq = store.getAllKeys();
      keysReq.onerror = event => fail(
        _storageError('IndexedDB GLB cache prune failed.', event.target?.error),
      );
      keysReq.onsuccess = () => {
        const keys = keysReq.result || [];
        if (keys.length <= GLB_CACHE_MAX_ENTRIES) return;
        const rowsReq = store.getAll();
        rowsReq.onerror = event => fail(
          _storageError('IndexedDB GLB cache prune failed.', event.target?.error),
        );
        rowsReq.onsuccess = () => {
          const rows = rowsReq.result || [];
          keys.map((k, i) => ({ key: k, ts: rows[i]?.ts ?? 0 }))
              .sort((a, b) => a.ts - b.ts)
              .slice(0, keys.length - GLB_CACHE_MAX_ENTRIES)
              .forEach(({ key }) => store.delete(key));
        };
      };
    });
  } catch (e) {
    console.warn('[nova3d] glb cache write failed:', e);
  }
}

async function _primeGlbCache(url) {
  if (_persistenceDisabled) return;
  if (!/^https?:/i.test(String(url || ''))) return;
  if (await _glbCacheGet(url)) return;
  try {
    const bytes = await _fetchGlbBytes(url);
    if (bytes) void _glbCachePut(url, bytes);
  } catch (_) { /* cache priming is best-effort */ }
}

// ── Debounced save ───────────────────────────────────────────────────────────
let _saveTimer = null;

export function saveEditorState() {
  if (_persistenceDisabled) return;
  // Debounce rapid calls (every undo push, resize, etc.) into one write.
  clearTimeout(_saveTimer);
  _saveTimer = setTimeout(() => {
    _saveTimer = null;
    void _persistEditorState();
  }, 800);
}

export function flushEditorState() {
  clearTimeout(_saveTimer);
  _saveTimer = null;
  if (_persistenceDisabled) return Promise.resolve();
  return _persistEditorState();
}

async function _persistEditorState() {
  if (_persistenceDisabled || !state.loadedMeshes.length) return;
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

/** Permanently disables persistence for this iframe and makes a bounded,
 * best-effort request to remove all editor state and cached private GLB bytes.
 * Used on logout; display and teardown must never wait on database deletion.
 * @returns {Promise<boolean>} Whether deletion completed before the deadline.
 */
export function clearEditorPersistence() {
  _persistenceDisabled = true;
  clearTimeout(_saveTimer);
  _saveTimer = null;

  const pendingOpen = _idbOpenPromise;
  try { _cancelIdbOpen?.(); } catch (_) {}
  if (_idbOpenPromise === pendingOpen) _idbOpenPromise = null;
  _cancelIdbOpen = null;
  _closeIdb();

  return new Promise(resolve => {
    let request = null;
    let settled = false;
    const timer = setTimeout(() => finish(false), IDB_DELETE_TIMEOUT_MS);
    const finish = deleted => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      resolve(deleted);
    };

    try {
      request = indexedDB.deleteDatabase(IDB_NAME);
      request.onsuccess = () => finish(true);
      request.onerror = () => finish(false);
      // Another viewer may still be closing its connection. Do not let that
      // hold logout or iframe teardown open; the delete request remains queued.
      request.onblocked = () => finish(false);
    } catch (_) {
      finish(false);
    }
  });
}

// ── Restore ──────────────────────────────────────────────────────────────────
function _restorableUrl(data) {
  // blob: URLs die with the document that created them; http(s)/data: survive.
  const candidates = [data.modelUrl, data.sourceModelUrl, data.modelArtifact?.url];
  for (const raw of candidates) {
    const url = String(raw || '').trim();
    if (/^(https?:|data:)/i.test(url)) return url;
  }
  return null;
}

export async function restoreEditorState({ modelUrl = '', sourceModelUrl = '' } = {}) {
  if (_persistenceDisabled) return false;
  try {
    const data = await _idbGet(editorStorageKey());
    if (!data || data.version < MIN_READABLE_VERSION) return false;

    // The host has already resolved/refreshed the model URL before creating the
    // iframe. Prefer it over a persisted signed URL, which may have expired
    // since this editor state was written.
    const hostUrl = String(modelUrl || '').trim();
    const hostSourceUrl = String(sourceModelUrl || '').trim();
    const url = hostUrl || _restorableUrl(data);
    if (!url || !_loadModel) return false;

    state.currentCodeArtifact   = data.codeArtifact ?? null;
    state.currentModelUrl       = hostSourceUrl || data.modelUrl || url;
    state.currentSourceModelUrl = hostSourceUrl || data.sourceModelUrl || data.modelUrl || url;
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
      const loadOptions = {
        sourceModelUrl: state.currentSourceModelUrl,
        recordHistory: false,
        // When the host URL is a blob, the canonical source arrives over the
        // same-origin config bridge and may update state while GLTF parses.
        preserveCurrentSourceModelUrl: Boolean(hostUrl && !hostSourceUrl),
      };
      if (hostUrl && hostSourceUrl && hostUrl !== hostSourceUrl) {
        loadOptions.canonicalUrl = hostSourceUrl;
      }
      if (/^https?:/i.test(url)) {
        let bytes = await _glbCacheGet(url);
        if (!bytes) {
          try {
            const fetched = await _fetchGlbBytes(url);
            if (fetched) {
              bytes = fetched;
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
    _runWhenContainerReady(startLoad);
    return true;
  } catch (e) {
    console.warn('[nova3d] restoreEditorState failed:', e);
    return false;
  }
}
