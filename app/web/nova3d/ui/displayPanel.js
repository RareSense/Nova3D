// Display-mode toggles (wireframe, x-ray, clay, normal-material view, bounding
// box) and exposure slider. X-ray/clay/normals are mutually exclusive material
// override modes, mirroring the sample preview UI while keeping selection and
// editing on the existing mesh list contract.

import { THREE } from '@nova/three-ext.js';
import { state } from '@nova/state.js';
import { pushUndoSnapshot } from '@nova/history.js';
import { applyRenderProfileToMaterial, highlightMat } from '@nova/materials.js';
import { track } from '@nova/analytics.js';

const xrayMaterial = new THREE.MeshStandardMaterial({
  color:0x00ffff, transparent:true, opacity:0.18, depthWrite:false, side:THREE.DoubleSide
});
const normalViewMaterial = new THREE.MeshNormalMaterial({ side:THREE.DoubleSide });
const clayMaterial = new THREE.MeshStandardMaterial({
  color:0xc8b49a, metalness:0, roughness:0.92, flatShading:false, side:THREE.DoubleSide
});
applyRenderProfileToMaterial(clayMaterial);

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

// Wireframe is drawn as a line overlay on top of the shaded mesh (not via
// material.wireframe, which replaces the surface with wires in the object's
// own color and leaves transparent materials looking opaque). The shaded
// surface stays visible and topology lines render above it in a neutral color.
const wireframeLineMat = new THREE.LineBasicMaterial({
  color: 0x111111, transparent: true, opacity: 0.85
});

function setWireframeOverlay(entry, enabled) {
  if (enabled) {
    if (entry.wireframeOverlay) return;
    const lines = new THREE.LineSegments(
      new THREE.WireframeGeometry(entry.mesh.geometry), wireframeLineMat
    );
    lines.raycast = () => {};          // never intercept picking
    lines.renderOrder = 1;
    lines.userData.isWireframeOverlay = true;
    entry.mesh.add(lines);
    entry.wireframeOverlay = lines;
  } else if (entry.wireframeOverlay) {
    entry.mesh.remove(entry.wireframeOverlay);
    entry.wireframeOverlay.geometry.dispose();
    entry.wireframeOverlay = null;
  }
}

function syncDisplayFlags(material) {
  eachMaterial(material, mat => {
    mat.wireframe = false;   // legacy snapshots may carry wireframe:true
    mat.flatShading = state.displayState.flatShading;
    // Push the shaded surface back slightly so overlay lines never z-fight it.
    mat.polygonOffset = state.displayState.wireframe;
    mat.polygonOffsetFactor = 1;
    mat.polygonOffsetUnits = 1;
    mat.needsUpdate = true;
  });
}

function materialForDisplay(entry) {
  if (state.displayState.viewMode === 'xray') return xrayMaterial;
  if (state.displayState.viewMode === 'normals') return normalViewMaterial;
  if (state.displayState.viewMode === 'clay') return clayMaterial;
  return entry.sourceMaterial || entry.originalMaterial;
}

export function applyMaterialDisplayMode() {
  state.loadedMeshes.forEach((entry, idx) => {
    const material = materialForDisplay(entry);
    entry.originalMaterial = material;
    syncDisplayFlags(material);
    setWireframeOverlay(entry, state.displayState.wireframe);
    if (!state.selectedMeshIndices.has(idx) && entry.mesh.material !== highlightMat) {
      entry.mesh.material = material;
    }
  });
}

function updateViewModeButtons() {
  document.getElementById('togXray')?.classList.toggle('active-tool', state.displayState.viewMode === 'xray');
  document.getElementById('togNormals')?.classList.toggle('active-tool', state.displayState.viewMode === 'normals');
  document.getElementById('togClay')?.classList.toggle('active-tool', state.displayState.viewMode === 'clay');
}

function setViewMode(mode) {
  pushUndoSnapshot(mode || 'display-original');
  state.displayState.viewMode = state.displayState.viewMode === mode ? '' : mode;
  applyMaterialDisplayMode();
  updateViewModeButtons();
}

export function toggleWireframe() {
  track('display_mode_changed', { mode: 'wireframe' });
  pushUndoSnapshot('wireframe');
  state.displayState.wireframe = !state.displayState.wireframe;
  applyMaterialDisplayMode();
  document.getElementById('togWireframe').classList.toggle('active-tool', state.displayState.wireframe);
}

export function toggleFlatShading() {
  track('display_mode_changed', { mode: 'flat_shading' });
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
  track('display_mode_changed', { mode: 'xray' });
  setViewMode('xray');
}

export function toggleClay() {
  track('display_mode_changed', { mode: 'clay' });
  setViewMode('clay');
}

export function toggleBoundingBox() {
  track('display_mode_changed', { mode: 'bounding_box' });
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
  track('display_mode_changed', { mode: 'normals' });
  setViewMode('normals');
}

export function setExposure(val) {
  state.renderer.toneMappingExposure = parseFloat(val);
  document.getElementById('exposureVal').textContent = parseFloat(val).toFixed(1);
}
