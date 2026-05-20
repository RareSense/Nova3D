// GLB load/clear, loading overlay, mesh stats, mesh ops (delete/dup/mirror/
// merge/separate/subdivide/smooth/decimate/flip-normals/center-origin/
// recalc-normals/mirror-modifier), material presets, and GLB export.
//
// Cross-module hooks (set by inline boot in PR 9):
//   - setModelHooks({ refreshMeshUi, refreshHighlights, detachProxy,
//                     frameCameraToModel, showDownloadError })
//   - selection-side helpers move into selection.js in PR 10; scene-side
//     helpers move into scene.js in PR 11. The hooks let model.js stay
//     usable while those moves are pending.

/**
 * @typedef {Object} MeshEntry
 * @property {THREE.Mesh} mesh                     The live mesh in the scene.
 * @property {THREE.Material} originalMaterial     The mesh's material before the highlight overlay swaps it.
 * @property {string} name                         Display name (used by mesh list, AI edit selectors).
 * @property {THREE.BufferGeometry} geometry       A clone of the rest-state geometry (used by smooth/subdivide/decimate to derive next state).
 */

import { THREE, GLTFLoader, GLTFExporter, mergeGeometries } from '@nova/three-ext.js';
import { state } from '@nova/state.js';
import { pushUndoSnapshot } from '@nova/history.js';
import { saveEditorState } from '@nova/persistence.js';
import { bindArticulatedJoints } from '@nova/articulation.js';
import {
  assignCategoryColors,
  applyRenderProfileToObject,
  highlightMat,
  makeDiamond,
  METAL_FACTORIES,
  GEM_PRESETS,
} from '@nova/materials.js';
import { syncHistoryUi } from '@nova/history.js';

// ── Cross-module callback hooks ──────────────────────────────────────────────
let _refreshMeshUi      = () => {};
let _refreshHighlights  = () => {};
let _detachProxy        = () => {};
let _frameCameraToModel = () => {};
let _showDownloadError  = (msg) => console.error(msg);

export function setModelHooks({
  refreshMeshUi, refreshHighlights, detachProxy, frameCameraToModel, showDownloadError,
} = {}) {
  if (typeof refreshMeshUi === 'function')      _refreshMeshUi      = refreshMeshUi;
  if (typeof refreshHighlights === 'function')  _refreshHighlights  = refreshHighlights;
  if (typeof detachProxy === 'function')        _detachProxy        = detachProxy;
  if (typeof frameCameraToModel === 'function') _frameCameraToModel = frameCameraToModel;
  if (typeof showDownloadError === 'function')  _showDownloadError  = showDownloadError;
}

// ── Loading overlay ──────────────────────────────────────────────────────────
export function showLoading() {
  document.getElementById('loadingOverlay').classList.add('active');
  setLoadingProgress(0);
}

export function hideLoading() {
  const el = document.getElementById('loadingError');
  if (el) el.style.display = 'none';
  document.getElementById('loadingOverlay').classList.remove('active');
}

export function showError(msg) {
  setLoadingProgress(100);
  document.getElementById('loadingLabel').textContent = 'Error loading model';
  const el = document.getElementById('loadingError');
  if (el) { el.textContent = msg; el.style.display = 'block'; }
  // Keep overlay visible so user can read the error
}

export function setLoadingProgress(pct) {
  document.getElementById('loadingBarFill').style.width = pct + '%';
  document.getElementById('loadingLabel').textContent = pct < 100 ? `Loading model... ${pct}%` : 'Ready';
}

// ── Stats panel ──────────────────────────────────────────────────────────────
export function updateMeshStats() {
  const totalVerts = state.loadedMeshes.reduce((s,m) => s + (m.geometry.attributes.position ? m.geometry.attributes.position.count : 0), 0);
  document.getElementById('meshStats').textContent = `${state.loadedMeshes.length} meshes | ${totalVerts.toLocaleString()} verts`;
  document.getElementById('statMeshes').textContent = state.loadedMeshes.length;
  document.getElementById('statVerts').textContent  = totalVerts.toLocaleString();
}

// ── GLB load/clear ───────────────────────────────────────────────────────────
export function loadGLB(url, options = {}) {
  showLoading();
  new GLTFLoader().load(
    url,
    gltf => {
      clearModel();
      state.currentModelUrl = url;
      if (options.sourceModelUrl) state.currentSourceModelUrl = options.sourceModelUrl;
      const model = gltf.scene;
      const box  = new THREE.Box3().setFromObject(model);
      const ctr  = box.getCenter(new THREE.Vector3());
      const size = box.getSize(new THREE.Vector3());
      model.position.sub(ctr);
      model.scale.setScalar(2.2 / Math.max(size.x, size.y, size.z));
      state.modelGroup.position.set(0,0,0); state.modelGroup.scale.setScalar(1); state.modelGroup.rotation.set(0,0,0);
      model.traverse(child => { if (child.isMesh && child.geometry) { child.castShadow = true; child.receiveShadow = true; } });
      assignCategoryColors(model);
      applyRenderProfileToObject(model);
      state.modelGroup.add(model);
      model.traverse(child => {
        if (!child.isMesh || !child.geometry) return;
        state.loadedMeshes.push({ mesh: child, originalMaterial: child.material, name: child.name || `Mesh_${state.loadedMeshes.length}`, geometry: child.geometry.clone() });
      });
      _refreshMeshUi();
      bindArticulatedJoints(state.currentJoints, {
        preserveValues: true,
        autoStart: options.startJointDemo === true,
      });
      _frameCameraToModel(state.modelGroup);
      hideLoading();
      const el = document.getElementById('statsBar'); if (el) el.style.display = 'flex';
      if (options.recordHistory !== false && !state.undoHistory.length && !state.redoHistory.length) {
        syncHistoryUi();
      }
      saveEditorState();
      state.renderer.render(state.scene, state.camera);
    },
    prog => { if (prog.total > 0) setLoadingProgress(Math.round(prog.loaded / prog.total * 100)); },
    err  => {
      const msg = err?.message || String(err);
      console.error('GLB load error:', err);
      showError(`Failed to load model: ${msg}\n\nURL: ${url.slice(0,80)}`);
    }
  );
}

export function clearModel() {
  state.transformControls?.detach();
  state.loadedMeshes.forEach(m => { if (m.mesh.material && m.mesh.material !== highlightMat) m.mesh.material.dispose(); });
  state.loadedMeshes = []; state.selectedMeshIndices.clear();
  state.lastSelectionAction = null;
  while (state.modelGroup.children.length) state.modelGroup.remove(state.modelGroup.children[0]);
  state.boxHelpers.forEach(h => state.scene.remove(h));     state.boxHelpers = [];
  state.normalHelpers.forEach(h => { h.parent ? h.parent.remove(h) : state.scene.remove(h); h.geometry?.dispose(); });
  state.normalHelpers = [];
}

// ── GLB export ───────────────────────────────────────────────────────────────
export function downloadCurrentGLB() {
  if (!state.modelGroup || !state.modelGroup.children.length) return;
  const exporter = new GLTFExporter();
  exporter.parse(
    state.modelGroup,
    result => {
      const blob = result instanceof ArrayBuffer
        ? new Blob([result], { type: 'model/gltf-binary' })
        : new Blob([JSON.stringify(result)], { type: 'model/gltf+json' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `nova3d-edit-${Date.now()}.glb`;
      document.body.appendChild(a);
      a.click();
      a.remove();
      setTimeout(() => URL.revokeObjectURL(url), 1000);
    },
    error => _showDownloadError(`Download failed: ${error?.message || error}`),
    { binary: true, onlyVisible: false }
  );
}

// ── Mesh operations ──────────────────────────────────────────────────────────
export function deleteSelected() {
  if (!state.selectedMeshIndices.size) return;
  pushUndoSnapshot('delete'); _detachProxy(); state.transformControls.detach();
  const idxs = [...state.selectedMeshIndices].sort((a,b) => b - a);
  idxs.forEach(i => { const e = state.loadedMeshes[i]; e.mesh.removeFromParent(); e.mesh.geometry.dispose(); if (e.mesh.material && e.mesh.material !== highlightMat) e.mesh.material.dispose(); });
  idxs.forEach(i => state.loadedMeshes.splice(i, 1));
  state.selectedMeshIndices.clear();
  _refreshMeshUi();
}

export function duplicateSelection() {
  if (!state.selectedMeshIndices.size) return;
  pushUndoSnapshot('duplicate');
  const newIdxs = new Set();
  [...state.selectedMeshIndices].forEach(i => {
    const e = state.loadedMeshes[i];
    const geom = e.mesh.geometry.clone(), mat = e.originalMaterial.clone();
    const mesh = new THREE.Mesh(geom, mat);
    mesh.position.copy(e.mesh.position); mesh.position.x += 0.15;
    mesh.rotation.copy(e.mesh.rotation); mesh.scale.copy(e.mesh.scale);
    mesh.name = e.name + '_copy'; state.modelGroup.add(mesh);
    const ni = state.loadedMeshes.length;
    state.loadedMeshes.push({ mesh, originalMaterial: mat, name: mesh.name, geometry: geom.clone() });
    newIdxs.add(ni);
  });
  state.selectedMeshIndices = newIdxs;
  _refreshMeshUi(); _refreshHighlights();
}

export function mirrorSelection(axis) {
  if (!state.selectedMeshIndices.size) return; pushUndoSnapshot('mirror');
  state.selectedMeshIndices.forEach(i => { state.loadedMeshes[i].mesh.scale[axis] *= -1; });
}

export function mergeSelected() {
  if (state.selectedMeshIndices.size < 2) return; pushUndoSnapshot('merge');
  const idxs = [...state.selectedMeshIndices].sort((a,b) => a - b), geoms = [];
  idxs.forEach(i => { const m = state.loadedMeshes[i].mesh; const g = m.geometry.clone(); m.updateMatrixWorld(true); g.applyMatrix4(m.matrixWorld); geoms.push(g); });
  try {
    const merged = mergeGeometries(geoms, false); if (!merged) return;
    merged.computeVertexNormals();
    const mat = state.loadedMeshes[idxs[0]].originalMaterial.clone();
    const mesh = new THREE.Mesh(merged, mat); mesh.name = 'Merged'; state.modelGroup.add(mesh);
    idxs.sort((a,b) => b - a).forEach(i => { state.loadedMeshes[i].mesh.removeFromParent(); state.loadedMeshes[i].mesh.geometry.dispose(); state.loadedMeshes.splice(i, 1); });
    state.loadedMeshes.push({ mesh, originalMaterial: mat, name: 'Merged', geometry: merged.clone() });
    state.selectedMeshIndices.clear(); state.selectedMeshIndices.add(state.loadedMeshes.length - 1);
    _refreshMeshUi(); _refreshHighlights();
  } catch (e) { console.error('Merge error:', e); }
}

export function flipNormals() {
  if (!state.selectedMeshIndices.size) return; pushUndoSnapshot('flip-normals');
  state.selectedMeshIndices.forEach(i => {
    const geo = state.loadedMeshes[i].mesh.geometry, idx = geo.index;
    if (idx) { const a = idx.array; for (let j=0; j<a.length; j+=3) { [a[j], a[j+2]] = [a[j+2], a[j]]; } idx.needsUpdate = true; }
    const nrm = geo.attributes.normal;
    if (nrm) { for (let j=0; j<nrm.count; j++) nrm.setXYZ(j, -nrm.getX(j), -nrm.getY(j), -nrm.getZ(j)); nrm.needsUpdate = true; }
  });
}

export function centerOrigin() {
  if (!state.selectedMeshIndices.size) return; pushUndoSnapshot('center-origin');
  state.selectedMeshIndices.forEach(i => {
    const mesh = state.loadedMeshes[i].mesh; mesh.geometry.computeBoundingBox();
    const c = mesh.geometry.boundingBox.getCenter(new THREE.Vector3());
    mesh.geometry.translate(-c.x, -c.y, -c.z);
    c.applyMatrix4(new THREE.Matrix4().makeRotationFromEuler(mesh.rotation)).multiply(mesh.scale);
    mesh.position.add(c);
  });
}

export function recalcNormals() {
  if (!state.selectedMeshIndices.size) return;
  pushUndoSnapshot('recalc-normals');
  state.selectedMeshIndices.forEach(i => { state.loadedMeshes[i].mesh.geometry.computeVertexNormals(); });
}

export function separateByLooseParts() {
  if (state.selectedMeshIndices.size !== 1) return;
  pushUndoSnapshot('separate');
  const idx = [...state.selectedMeshIndices][0], entry = state.loadedMeshes[idx];
  const geo = entry.mesh.geometry, pos = geo.attributes.position, index = geo.index;
  if (!index) return;
  const n = pos.count, parent = new Int32Array(n).fill(0).map((_,i) => i);
  const find = x => { while (parent[x] !== x) { parent[x] = parent[parent[x]]; x = parent[x]; } return x; };
  const union = (a, b) => { const ra = find(a), rb = find(b); if (ra !== rb) parent[ra] = rb; };
  const ia = index.array;
  for (let i=0; i<ia.length; i+=3) { union(ia[i], ia[i+1]); union(ia[i+1], ia[i+2]); }
  const groups = {};
  for (let i=0; i<ia.length; i+=3) { const r = find(ia[i]); (groups[r] = groups[r] || []).push(i); }
  const keys = Object.keys(groups); if (keys.length < 2) return;
  entry.mesh.removeFromParent(); state.loadedMeshes.splice(idx, 1); state.selectedMeshIndices.clear();
  keys.forEach((root, gi) => {
    const faces = groups[root], vmap = {}; let nvc = 0, newIdx = [];
    faces.forEach(fi => { for (let j=0; j<3; j++) { const ov = ia[fi+j]; if (!(ov in vmap)) vmap[ov] = nvc++; newIdx.push(vmap[ov]); } });
    const newPos = new Float32Array(nvc * 3), oldPos = pos.array;
    for (const [ov, nv] of Object.entries(vmap)) { newPos[nv*3] = oldPos[ov*3]; newPos[nv*3+1] = oldPos[ov*3+1]; newPos[nv*3+2] = oldPos[ov*3+2]; }
    const ng = new THREE.BufferGeometry();
    ng.setAttribute('position', new THREE.BufferAttribute(newPos, 3)); ng.setIndex(newIdx); ng.computeVertexNormals();
    const mat = entry.originalMaterial.clone(), mesh = new THREE.Mesh(ng, mat);
    mesh.name = `${entry.name}_part${gi}`; mesh.position.copy(entry.mesh.position); mesh.rotation.copy(entry.mesh.rotation); mesh.scale.copy(entry.mesh.scale);
    state.modelGroup.add(mesh); state.loadedMeshes.push({ mesh, originalMaterial: mat, name: mesh.name, geometry: ng.clone() });
  });
  _refreshMeshUi();
}

// ── Modifiers ────────────────────────────────────────────────────────────────
function subdivideGeometryOnce(geometry) {
  const source = geometry.index ? geometry.toNonIndexed() : geometry.clone();
  const pos = source.attributes.position;
  const out = [];
  const vertex = i => new THREE.Vector3(pos.getX(i), pos.getY(i), pos.getZ(i));
  const pushTri = (a, b, c) => { out.push(a.x, a.y, a.z, b.x, b.y, b.z, c.x, c.y, c.z); };
  for (let i=0; i<pos.count; i+=3) {
    const a = vertex(i), b = vertex(i+1), c = vertex(i+2);
    const ab = a.clone().add(b).multiplyScalar(.5);
    const bc = b.clone().add(c).multiplyScalar(.5);
    const ca = c.clone().add(a).multiplyScalar(.5);
    pushTri(a, ab, ca); pushTri(ab, b, bc); pushTri(ca, bc, c); pushTri(ab, bc, ca);
  }
  const next = new THREE.BufferGeometry();
  next.setAttribute('position', new THREE.Float32BufferAttribute(out, 3));
  next.computeVertexNormals();
  source.dispose();
  return next;
}

export function subdivideSelected(iters = 1) {
  if (!state.selectedMeshIndices.size) return; pushUndoSnapshot('subdivide');
  state.selectedMeshIndices.forEach(i => {
    try {
      let next = state.loadedMeshes[i].mesh.geometry.clone();
      for (let step=0; step<iters; step++) {
        if ((next.index ? next.index.count : next.attributes.position.count) > 80000) break;
        const sub = subdivideGeometryOnce(next);
        next.dispose();
        next = sub;
      }
      state.loadedMeshes[i].mesh.geometry.dispose();
      state.loadedMeshes[i].mesh.geometry = next;
      state.loadedMeshes[i].geometry = next.clone();
    } catch (e) { console.error(e); }
  });
  updateMeshStats();
}

export function smoothSelected(iters = 3) {
  if (!state.selectedMeshIndices.size) return; pushUndoSnapshot('smooth');
  state.selectedMeshIndices.forEach(i => {
    const geo = state.loadedMeshes[i].mesh.geometry, pos = geo.attributes.position, idx = geo.index; if (!idx) return;
    const adj = Array.from({ length: pos.count }, () => new Set()), ia = idx.array;
    for (let f=0; f<ia.length; f+=3) { adj[ia[f]].add(ia[f+1]); adj[ia[f]].add(ia[f+2]); adj[ia[f+1]].add(ia[f]); adj[ia[f+1]].add(ia[f+2]); adj[ia[f+2]].add(ia[f]); adj[ia[f+2]].add(ia[f+1]); }
    for (let it=0; it<iters; it++) {
      const np = new Float32Array(pos.array.length);
      for (let v=0; v<pos.count; v++) {
        const nb = adj[v]; if (!nb.size) { np[v*3] = pos.getX(v); np[v*3+1] = pos.getY(v); np[v*3+2] = pos.getZ(v); continue; }
        let sx = 0, sy = 0, sz = 0; nb.forEach(n => { sx += pos.getX(n); sy += pos.getY(n); sz += pos.getZ(n); }); const c = nb.size;
        np[v*3] = pos.getX(v)*.5 + (sx/c)*.5; np[v*3+1] = pos.getY(v)*.5 + (sy/c)*.5; np[v*3+2] = pos.getZ(v)*.5 + (sz/c)*.5;
      }
      pos.array.set(np); pos.needsUpdate = true;
    }
    geo.computeVertexNormals();
  });
  updateMeshStats();
}

export function decimateSelected(ratio = 0.5) {
  if (!state.selectedMeshIndices.size) return; pushUndoSnapshot('decimate');
  state.selectedMeshIndices.forEach(i => {
    const geo = state.loadedMeshes[i].mesh.geometry, idx = geo.index; if (!idx) return;
    const keep = Math.max(12, Math.floor(idx.count * ratio)) - (Math.max(12, Math.floor(idx.count * ratio)) % 3);
    const newIdx = new Uint32Array(keep);
    for (let j=0; j<keep; j++) newIdx[j] = idx.array[j];
    geo.setIndex(new THREE.BufferAttribute(newIdx, 1)); geo.computeVertexNormals();
    state.loadedMeshes[i].geometry = geo.clone();
  });
  updateMeshStats();
}

export function applyMirrorModifier(axis) {
  if (!state.selectedMeshIndices.size) return; pushUndoSnapshot('mirror-mod');
  state.selectedMeshIndices.forEach(i => {
    const mesh = state.loadedMeshes[i].mesh, orig = mesh.geometry.clone(), mir = mesh.geometry.clone();
    const scl = new THREE.Vector3(1,1,1); scl[axis] = -1; mir.scale(scl.x, scl.y, scl.z);
    if (mir.index) { const a = mir.index.array; for (let j=0; j<a.length; j+=3) { [a[j], a[j+2]] = [a[j+2], a[j]]; } }
    try {
      const merged = mergeGeometries([orig, mir], false); if (!merged) return;
      merged.computeVertexNormals(); mesh.geometry.dispose(); mesh.geometry = merged; state.loadedMeshes[i].geometry = merged.clone();
    } catch (e) { console.error(e); }
  });
  updateMeshStats();
}

// ── Materials ────────────────────────────────────────────────────────────────
export function applyMaterialPreset(name) {
  if (!state.selectedMeshIndices.size) return; pushUndoSnapshot('material');
  state.selectedMeshIndices.forEach(i => {
    const entry = state.loadedMeshes[i]; let mat;
    if (name === 'Diamond') { mat = makeDiamond(entry.mesh); }
    else if (METAL_FACTORIES[name]) { mat = METAL_FACTORIES[name](); entry.mesh.material = mat; }
    else if (GEM_PRESETS[name]) {
      const p = GEM_PRESETS[name];
      mat = new THREE.MeshPhysicalMaterial({ color: p.color, metalness: 0, roughness: 0, transmission: p.transmission, ior: p.ior, thickness: p.thickness, envMap: state.envMap, envMapIntensity: 2, clearcoat: 1, clearcoatRoughness: 0, transparent: true, opacity: 1, side: THREE.DoubleSide, specularIntensity: 1.5, specularColor: new THREE.Color(0xffffff), attenuationDistance: 1, attenuationColor: new THREE.Color(p.color) });
      entry.mesh.material = mat;
    }
    if (mat) entry.originalMaterial = mat;
  });
  _refreshHighlights();
}

export function applyCustomMaterial() {
  if (!state.selectedMeshIndices.size) return; pushUndoSnapshot('custom-material');
  const color     = document.getElementById('customMatColor').value;
  const metalness = parseFloat(document.getElementById('customMetalness').value);
  const roughness = parseFloat(document.getElementById('customRoughness').value);
  const clearcoat = parseFloat(document.getElementById('customClearcoat').value);
  state.selectedMeshIndices.forEach(i => {
    const mat = new THREE.MeshPhysicalMaterial({ color: new THREE.Color(color), metalness, roughness, clearcoat, clearcoatRoughness: .1, envMap: state.envMap, envMapIntensity: 1.5 });
    state.loadedMeshes[i].mesh.material = mat; state.loadedMeshes[i].originalMaterial = mat;
  });
  _refreshHighlights();
}
