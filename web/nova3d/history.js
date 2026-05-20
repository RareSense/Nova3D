// Snapshot capture/restore, undo/redo stacks, and history-list rendering.
//
// Snapshot serialization is the highest-risk surface in the refactor: the
// IndexedDB payload shape must stay byte-identical so saved state from older
// builds keeps loading. Do not change field names, defaults, or schema version
// without a deliberate migration plan.
//
// Cross-module hooks: this module needs to refresh the mesh list, mesh stats,
// highlights, and detach the transform proxy after restoreSnapshot swaps the
// scene. Those functions still live in the inline script (until PRs 10 and 11
// extract selection.js and scene.js), so the inline boot calls
// `setHistoryUiRefreshers({ detachProxy, refreshUi })` once at startup.
// `saveEditorState` lives in persistence.js but is wired via a setter to keep
// the module graph acyclic.

/**
 * In-memory snapshot used by the undo/redo stacks. Holds THREE objects with
 * live geometry/material clones — never written to IndexedDB directly.
 * @typedef {Object} Snapshot
 * @property {string} action
 * @property {Object|null} codeArtifact
 * @property {string|null} modelUrl
 * @property {string} sourceModelUrl
 * @property {Object|null} modelArtifact
 * @property {Object|null} jointsArtifact
 * @property {import('./articulation.js').Joint[]} joints
 * @property {string} selectedArticulatedJointName
 * @property {Record<string, number>} jointSliderValues
 * @property {Record<string, number>} jointDirectionMultipliers
 * @property {Array<{name:string,parentJointName:string,position:THREE.Vector3,rotation:THREE.Euler,scale:THREE.Vector3,restPos:THREE.Vector3,restRot:THREE.Euler}>} jointNodes
 * @property {Array<{name:string,geometry:THREE.BufferGeometry,material:THREE.Material,jointName:string|null,position:THREE.Vector3,rotation:THREE.Euler,scale:THREE.Vector3,visible:boolean,matParams:Object}>} meshes
 */

/**
 * Plain-object form of a Snapshot, suitable for IndexedDB. Field shape is
 * frozen at SCHEMA_VERSION = 2 — see @nova/persistence.js. Do not change
 * field names or defaults; older saves still load through `snapshotFromData`.
 * @typedef {Object} SerializedSnapshot
 */

import { THREE } from '@nova/three-ext.js';
import { state, MAX_UNDO } from '@nova/state.js';
import {
  structuredCloneSafe,
  escapeHtml,
  formatActionLabel,
  vecToData,
  vecFromData,
  eulerToData,
  eulerFromData,
} from '@nova/util.js';
import {
  serializeMaterial,
  materialFromParams,
  applyRenderProfileToMaterial,
  highlightMat,
} from '@nova/materials.js';
import {
  captureJointNodes,
  objectParentJointName,
  bindArticulatedJoints,
  applyJointTransforms,
  syncDemoFlags,
  stopJointAutoPreviewForEdit,
} from '@nova/articulation.js';

// ── Cross-module callback hooks (set by inline boot) ─────────────────────────
let _detachProxy = () => {};
let _refreshUi = () => {};
let _saveEditorState = () => {};

export function setHistoryUiRefreshers({ detachProxy, refreshUi } = {}) {
  if (typeof detachProxy === 'function') _detachProxy = detachProxy;
  if (typeof refreshUi === 'function')   _refreshUi   = refreshUi;
}
export function setHistorySaveEditorState(fn) {
  _saveEditorState = typeof fn === 'function' ? fn : (() => {});
}

// ── Geometry serialization ───────────────────────────────────────────────────
function serializeGeometry(geometry) {
  const pos = geometry.attributes.position;
  if (!pos) return null;
  return {
    position: Array.from(pos.array),
    normal:   geometry.attributes.normal ? Array.from(geometry.attributes.normal.array) : null,
    index:    geometry.index ? Array.from(geometry.index.array) : null,
  };
}

function geometryFromData(data) {
  if (!data?.position) return null;
  const geometry = new THREE.BufferGeometry();
  geometry.setAttribute('position', new THREE.Float32BufferAttribute(data.position, 3));
  if (data.normal) geometry.setAttribute('normal', new THREE.Float32BufferAttribute(data.normal, 3));
  else geometry.computeVertexNormals();
  if (data.index) geometry.setIndex(data.index);
  geometry.computeBoundingBox();
  geometry.computeBoundingSphere();
  return geometry;
}

// ── In-memory snapshot capture/dispose ───────────────────────────────────────
export function captureSnapshot(action) {
  if (!state.loadedMeshes.length) return null;
  const preserveArticulation = state.articulatedJoints.length > 0;
  return {
    action,
    codeArtifact: state.currentCodeArtifact,
    modelUrl: state.currentModelUrl,
    sourceModelUrl: state.currentSourceModelUrl,
    modelArtifact: state.currentModelArtifact,
    jointsArtifact: state.currentJointsArtifact,
    joints: structuredCloneSafe(state.currentJoints),
    selectedArticulatedJointName: state.selectedArticulatedJointName,
    jointSliderValues: structuredCloneSafe(state.jointSliderValues) || {},
    jointDirectionMultipliers: structuredCloneSafe(state.jointDirectionMultipliers) || {},
    jointNodes: preserveArticulation ? captureJointNodes() : [],
    meshes: state.loadedMeshes.map(entry => {
      const material = entry.originalMaterial?.clone?.() || entry.mesh.material?.clone?.() || new THREE.MeshStandardMaterial({ color:0xaaaaaa });
      const geometry = entry.mesh.geometry.clone();
      if (!preserveArticulation) {
        entry.mesh.updateMatrixWorld(true);
        state.modelGroup.updateMatrixWorld(true);
        const toModelGroup = new THREE.Matrix4().copy(state.modelGroup.matrixWorld).invert().multiply(entry.mesh.matrixWorld);
        geometry.applyMatrix4(toModelGroup);
      }
      return {
        name: entry.name,
        geometry,
        material,
        jointName: preserveArticulation ? objectParentJointName(entry.mesh) : null,
        position: preserveArticulation ? entry.mesh.position.clone() : new THREE.Vector3(),
        rotation: preserveArticulation ? entry.mesh.rotation.clone() : new THREE.Euler(),
        scale:    preserveArticulation ? entry.mesh.scale.clone()    : new THREE.Vector3(1,1,1),
        visible:  entry.mesh.visible,
        matParams: serializeMaterial(material),
      };
    }),
  };
}

export function disposeSnapshot(snapshot) {
  snapshot?.meshes?.forEach(m => { m.geometry?.dispose?.(); m.material?.dispose?.(); });
}

// ── IDB-shaped (plain object) serialization ──────────────────────────────────
export function snapshotToData(snapshot) {
  if (!snapshot) return null;
  return {
    action: snapshot.action,
    codeArtifact: snapshot.codeArtifact,
    modelUrl: snapshot.modelUrl,
    sourceModelUrl: snapshot.sourceModelUrl,
    modelArtifact: snapshot.modelArtifact,
    jointsArtifact: snapshot.jointsArtifact,
    joints: snapshot.joints || [],
    selectedArticulatedJointName: snapshot.selectedArticulatedJointName || '',
    jointSliderValues: snapshot.jointSliderValues || {},
    jointDirectionMultipliers: snapshot.jointDirectionMultipliers || {},
    jointNodes: (snapshot.jointNodes || []).map(node => ({
      name: node.name,
      parentJointName: node.parentJointName,
      position: vecToData(node.position),
      rotation: eulerToData(node.rotation),
      scale: vecToData(node.scale),
      restPos: vecToData(node.restPos),
      restRot: eulerToData(node.restRot),
    })),
    meshes: snapshot.meshes.map(mesh => ({
      name: mesh.name,
      jointName: mesh.jointName,
      position: vecToData(mesh.position),
      rotation: eulerToData(mesh.rotation),
      scale: vecToData(mesh.scale),
      visible: mesh.visible,
      geometry: serializeGeometry(mesh.geometry),
      material: serializeMaterial(mesh.material || materialFromParams(mesh.matParams)),
    })).filter(mesh => mesh.geometry),
  };
}

export function snapshotFromData(data) {
  if (!data?.meshes?.length) return null;
  return {
    action: data.action,
    codeArtifact: data.codeArtifact,
    modelUrl: data.modelUrl,
    sourceModelUrl: data.sourceModelUrl,
    modelArtifact: data.modelArtifact,
    jointsArtifact: data.jointsArtifact,
    joints: Array.isArray(data.joints) ? data.joints : [],
    selectedArticulatedJointName: data.selectedArticulatedJointName || '',
    jointSliderValues: data.jointSliderValues || {},
    jointDirectionMultipliers: data.jointDirectionMultipliers || {},
    jointNodes: (data.jointNodes || []).map(node => ({
      name: node.name,
      parentJointName: node.parentJointName,
      position: vecFromData(node.position),
      rotation: eulerFromData(node.rotation),
      scale: vecFromData(node.scale, 1),
      restPos: vecFromData(node.restPos),
      restRot: eulerFromData(node.restRot),
    })),
    meshes: data.meshes.map(mesh => ({
      name: mesh.name,
      jointName: mesh.jointName,
      visible: mesh.visible,
      geometry: geometryFromData(mesh.geometry),
      material: materialFromParams(mesh.material),
      matParams: mesh.material,
      position: vecFromData(mesh.position),
      rotation: eulerFromData(mesh.rotation),
      scale: vecFromData(mesh.scale, 1),
    })).filter(mesh => mesh.geometry),
  };
}

// ── Stack ops ────────────────────────────────────────────────────────────────
export function pushUndoSnapshot(action) {
  stopJointAutoPreviewForEdit(action);
  const snapshot = captureSnapshot(action);
  if (!snapshot || !snapshot.meshes.length) return;
  state.undoHistory.push(snapshot);
  state.redoHistory.splice(0).forEach(disposeSnapshot);
  if (state.undoHistory.length > MAX_UNDO) disposeSnapshot(state.undoHistory.shift());
  syncHistoryUi();
  _saveEditorState();
}

export function restoreSnapshot(snap, options = {}) {
  if (!snap || !snap.meshes?.length) return false;
  const nextGroup = new THREE.Group();
  const nextMeshes = [];

  try {
    const jointNodeMap = new Map();
    (snap.jointNodes || []).forEach(node => {
      if (!node?.name) return;
      const obj = new THREE.Object3D();
      obj.name = node.name;
      obj.position.copy(node.position || new THREE.Vector3());
      obj.rotation.copy(node.rotation || new THREE.Euler());
      obj.scale.copy(node.scale || new THREE.Vector3(1,1,1));
      obj.userData.restPos = (node.restPos || node.position || new THREE.Vector3()).clone();
      obj.userData.restRot = (node.restRot || node.rotation || new THREE.Euler()).clone();
      jointNodeMap.set(node.name, { obj, parentJointName: node.parentJointName || '' });
    });
    jointNodeMap.forEach(({ obj, parentJointName }) => {
      const parent = parentJointName ? jointNodeMap.get(parentJointName)?.obj : null;
      (parent || nextGroup).add(obj);
    });

    snap.meshes.forEach(s => {
      if (!s?.geometry) throw new Error('Snapshot mesh is missing geometry.');
      const mat = s.material?.clone?.() || materialFromParams(s.matParams);
      applyRenderProfileToMaterial(mat);
      const geometry = s.geometry.clone();
      const mesh = new THREE.Mesh(geometry, mat);
      mesh.name = s.name || `Mesh_${nextMeshes.length}`;
      mesh.position.copy(s.position || new THREE.Vector3());
      mesh.rotation.copy(s.rotation || new THREE.Euler());
      mesh.scale.copy(s.scale || new THREE.Vector3(1,1,1));
      mesh.visible = s.visible !== false;
      const jointParent = s.jointName ? jointNodeMap.get(s.jointName)?.obj : null;
      (jointParent || nextGroup).add(mesh);
      nextMeshes.push({ mesh, originalMaterial: mat, name: mesh.name, geometry: geometry.clone() });
    });
  } catch (err) {
    console.error('Undo restore failed before model swap:', err);
    nextMeshes.forEach(e => { e.geometry.dispose(); e.mesh.geometry.dispose(); if (e.mesh.material) e.mesh.material.dispose(); });
    return false;
  }

  _detachProxy();
  state.transformControls?.detach();
  state.boxHelpers.forEach(h => state.scene.remove(h));     state.boxHelpers = [];
  state.normalHelpers.forEach(h => { h.parent ? h.parent.remove(h) : state.scene.remove(h); h.geometry?.dispose(); });
  state.normalHelpers = [];
  state.loadedMeshes.forEach(e => { e.mesh.removeFromParent(); e.mesh.geometry.dispose(); if (e.mesh.material && e.mesh.material !== highlightMat) e.mesh.material.dispose(); });
  while (state.modelGroup.children.length) state.modelGroup.remove(state.modelGroup.children[0]);
  nextGroup.children.slice().forEach(mesh => state.modelGroup.add(mesh));
  state.loadedMeshes = nextMeshes;
  state.selectedMeshIndices.clear();
  state.currentCodeArtifact = snap.codeArtifact ?? null;
  state.currentModelUrl = snap.modelUrl ?? null;
  state.currentSourceModelUrl = snap.sourceModelUrl ?? state.currentModelUrl ?? '';
  state.currentModelArtifact = snap.modelArtifact ?? null;
  state.currentJointsArtifact = snap.jointsArtifact ?? null;
  state.currentJoints = Array.isArray(snap.joints) ? snap.joints : [];
  state.selectedArticulatedJointName = snap.selectedArticulatedJointName || '';
  state.jointSliderValues = structuredCloneSafe(snap.jointSliderValues) || {};
  state.jointDirectionMultipliers = structuredCloneSafe(snap.jointDirectionMultipliers) || {};
  state.jointAutoPreviewSet.clear();
  for (const k of Object.keys(state.jointDemoPhases)) delete state.jointDemoPhases[k];
  syncDemoFlags();
  bindArticulatedJoints(state.currentJoints, { preserveValues: true });
  applyJointTransforms();
  _refreshUi();
  syncHistoryUi();
  if (!options.skipPersist) _saveEditorState();
  return true;
}

export function popUndo() {
  if (!state.undoHistory.length) return;
  const current = captureSnapshot('redo-point');
  const snap = state.undoHistory.pop();
  if (restoreSnapshot(snap)) {
    if (current) state.redoHistory.push(current);
  } else {
    state.undoHistory.push(snap);
  }
  syncHistoryUi();
  _saveEditorState();
}

export function popRedo() {
  if (!state.redoHistory.length) return;
  const current = captureSnapshot('undo-point');
  const snap = state.redoHistory.pop();
  if (restoreSnapshot(snap)) {
    if (current) state.undoHistory.push(current);
  } else {
    state.redoHistory.push(snap);
  }
  syncHistoryUi();
  _saveEditorState();
}

// ── History list rendering ───────────────────────────────────────────────────
export function syncHistoryUi() {
  const undoBtn = document.getElementById('tbUndo');
  const redoBtn = document.getElementById('tbRedo');
  if (undoBtn) undoBtn.disabled = state.undoHistory.length === 0;
  if (redoBtn) redoBtn.disabled = state.redoHistory.length === 0;

  const list = document.getElementById('historyList');
  if (!list) return;
  const redoForward = state.redoHistory.slice().reverse();
  const entries = [
    'Initial model',
    ...state.undoHistory.map(s => formatActionLabel(s.action)),
    ...redoForward.map(s => formatActionLabel(s.action)),
  ];
  const activeIndex = state.undoHistory.length;
  list.innerHTML = entries.map((label, idx) => {
    const isActive = idx === activeIndex;
    const sub = isActive ? 'Current state' : (idx < activeIndex ? 'Undo stack' : 'Redo stack');
    return `<button class="history-item${isActive ? ' active' : ''}" type="button" data-history-idx="${idx}">
      ${escapeHtml(label)}
      <small>${sub}</small>
    </button>`;
  }).join('');
  list.querySelectorAll('[data-history-idx]').forEach(btn => {
    btn.onclick = () => {
      const target = parseInt(btn.dataset.historyIdx, 10);
      while (state.undoHistory.length > target) popUndo();
      while (state.undoHistory.length < target && state.redoHistory.length) popRedo();
    };
  });
}
