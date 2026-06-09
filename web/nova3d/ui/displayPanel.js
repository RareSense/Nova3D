// Display-mode toggles (wireframe, x-ray, bounding box, normals) and exposure
// slider. These mutate the loaded-mesh materials directly and rebuild scene
// helpers (state.boxHelpers, state.normalHelpers) so they live next to the
// scene module. The flat-shading toggle is currently unbound to any UI but
// kept exported for symmetry.

import { THREE } from '@nova/three-ext.js';
import { state } from '@nova/state.js';
import { pushUndoSnapshot } from '@nova/history.js';
import { highlightMat } from '@nova/materials.js';

function selectedOrAll() {
  return state.selectedMeshIndices.size
    ? [...state.selectedMeshIndices]
    : state.loadedMeshes.map((_, i) => i);
}

function eachMaterial(material, fn) {
  (Array.isArray(material) ? material : [material]).forEach(mat => {
    if (mat) fn(mat);
  });
}

function syncDisplayFlags(material) {
  eachMaterial(material, mat => {
    mat.wireframe = state.displayState.wireframe;
    mat.flatShading = state.displayState.flatShading;
    mat.transparent = state.displayState.xray;
    mat.opacity = state.displayState.xray ? .3 : 1;
    mat.depthWrite = !state.displayState.xray;
    mat.needsUpdate = true;
  });
}

export function applyMaterialDisplayMode() {
  state.loadedMeshes.forEach((entry, idx) => {
    const material = state.displayState.categoryColors
      ? (entry.categoryMaterial || entry.originalMaterial)
      : (entry.sourceMaterial || entry.originalMaterial);
    entry.originalMaterial = material;
    syncDisplayFlags(material);
    if (!state.selectedMeshIndices.has(idx) && entry.mesh.material !== highlightMat) {
      entry.mesh.material = material;
    }
  });
}

export function toggleCategoryColors() {
  state.displayState.categoryColors = !state.displayState.categoryColors;
  applyMaterialDisplayMode();
  document.getElementById('togCategoryColors')?.classList.toggle('active-tool', state.displayState.categoryColors);
}

export function toggleWireframe() {
  pushUndoSnapshot('wireframe');
  state.displayState.wireframe = !state.displayState.wireframe;
  selectedOrAll().forEach(i => {
    eachMaterial(state.loadedMeshes[i].originalMaterial, mat => {
      mat.wireframe = state.displayState.wireframe;
      mat.needsUpdate = true;
    });
  });
  document.getElementById('togWireframe').classList.toggle('active-tool', state.displayState.wireframe);
}

export function toggleFlatShading() {
  pushUndoSnapshot('flat-shading');
  state.displayState.flatShading = !state.displayState.flatShading;
  selectedOrAll().forEach(i => {
    eachMaterial(state.loadedMeshes[i].originalMaterial, mat => {
      mat.flatShading = state.displayState.flatShading;
      mat.needsUpdate = true;
    });
  });
  document.getElementById('togFlatShade')?.classList.toggle('active-tool', state.displayState.flatShading);
}

export function toggleXray() {
  pushUndoSnapshot('xray');
  state.displayState.xray = !state.displayState.xray;
  selectedOrAll().forEach(i => {
    eachMaterial(state.loadedMeshes[i].originalMaterial, mat => {
      mat.transparent = state.displayState.xray;
      mat.opacity     = state.displayState.xray ? .3 : 1;
      mat.depthWrite  = !state.displayState.xray;
      mat.needsUpdate = true;
    });
  });
  document.getElementById('togXray').classList.toggle('active-tool', state.displayState.xray);
}

export function toggleBoundingBox() {
  state.displayState.boundingBox = !state.displayState.boundingBox;
  state.boxHelpers.forEach(h => state.scene.remove(h)); state.boxHelpers = [];
  if (state.displayState.boundingBox) {
    selectedOrAll().forEach(i => {
      const h = new THREE.BoxHelper(state.loadedMeshes[i].mesh, 0x00ffff);
      state.scene.add(h); state.boxHelpers.push(h);
    });
  }
  document.getElementById('togBBox').classList.toggle('active-tool', state.displayState.boundingBox);
}

export function toggleNormals() {
  state.displayState.normals = !state.displayState.normals;
  state.normalHelpers.forEach(h => { h.parent ? h.parent.remove(h) : state.scene.remove(h); h.geometry?.dispose(); });
  state.normalHelpers = [];
  if (state.displayState.normals) {
    selectedOrAll().forEach(i => {
      const mesh = state.loadedMeshes[i].mesh, pos = mesh.geometry.attributes.position, nrm = mesh.geometry.attributes.normal;
      if (!nrm) return;
      const pts = [], step = Math.max(1, Math.floor(pos.count / 500));
      for (let v=0; v<pos.count; v+=step) {
        const p = new THREE.Vector3(pos.getX(v), pos.getY(v), pos.getZ(v));
        const n = new THREE.Vector3(nrm.getX(v), nrm.getY(v), nrm.getZ(v)).multiplyScalar(.05);
        pts.push(p, p.clone().add(n));
      }
      const lg = new THREE.BufferGeometry().setFromPoints(pts);
      const lm = new THREE.LineBasicMaterial({ color: 0x00ff88 });
      const lines = new THREE.LineSegments(lg, lm);
      mesh.add(lines); state.normalHelpers.push(lines);
    });
  }
  document.getElementById('togNormals').classList.toggle('active-tool', state.displayState.normals);
}

export function setExposure(val) {
  state.renderer.toneMappingExposure = parseFloat(val);
  document.getElementById('exposureVal').textContent = parseFloat(val).toFixed(1);
}
