// Vertex-sculpting on the active mesh: brush size / strength sliders plus four
// brushes (grab, inflate, smooth, flatten). Sculpting bypasses the orbit
// controls while a stroke is in progress and uses the same raycaster as
// selection to pick the target mesh.

import { THREE } from '@nova/three-ext.js';
import { state } from '@nova/state.js';
import { pushUndoSnapshot } from '@nova/history.js';
import { setMode } from '@nova/scene.js';

export function toggleSculptMode() {
  state.sculptMode = !state.sculptMode;
  const btn = document.getElementById('sculptModeBtn');
  if (state.sculptMode) {
    if (btn) { btn.textContent = 'Disable Sculpt Mode'; btn.style.borderColor = '#0f0'; btn.style.color = '#0f0'; }
    setMode('orbit');
    state.container.style.cursor = 'crosshair';
  } else {
    if (btn) { btn.textContent = 'Enable Sculpt Mode'; btn.style.borderColor = '#f80'; btn.style.color = '#f80'; }
    state.container.style.cursor = '';
    state.isSculpting = false;
  }
}

export function setSculptTool(tool) {
  state.sculptTool = tool;
  document.querySelectorAll('#flySculpt .fo-btn').forEach(b => b.classList.remove('active-tool'));
  const el = document.getElementById('sculpt' + tool[0].toUpperCase() + tool.slice(1));
  if (el) el.classList.add('active-tool');
}

function applySculptBrush(hit) {
  const mesh = state.loadedMeshes[state.sculptTgtIdx].mesh, geo = mesh.geometry;
  const pos = geo.attributes.position, nrm = geo.attributes.normal;
  const bSize = parseFloat(document.getElementById('brushSize').value);
  const bStr  = parseFloat(document.getElementById('brushStrength').value);
  const inv = new THREE.Matrix4().copy(mesh.matrixWorld).invert();
  const lh = hit.point.clone().applyMatrix4(inv);
  const lfn = hit.face ? hit.face.normal.clone() : new THREE.Vector3(0, 1, 0);
  for (let v=0; v<pos.count; v++) {
    const vx = pos.getX(v), vy = pos.getY(v), vz = pos.getZ(v);
    const dist = Math.sqrt((vx-lh.x)**2 + (vy-lh.y)**2 + (vz-lh.z)**2);
    if (dist > bSize) continue;
    const str = bStr * (1 - (dist/bSize))**2 * .02;
    if (state.sculptTool === 'grab') {
      const dd = hit.point.clone().sub(state.sculptHitPt).applyMatrix4(new THREE.Matrix4().extractRotation(inv));
      pos.setXYZ(v, vx + dd.x * str * 10, vy + dd.y * str * 10, vz + dd.z * str * 10);
    } else if (state.sculptTool === 'inflate' && nrm) {
      pos.setXYZ(v, vx + nrm.getX(v) * str, vy + nrm.getY(v) * str, vz + nrm.getZ(v) * str);
    } else if (state.sculptTool === 'smooth') {
      pos.setXYZ(v, vx + (lh.x-vx) * str * .5, vy + (lh.y-vy) * str * .5, vz + (lh.z-vz) * str * .5);
    } else if (state.sculptTool === 'flatten') {
      const dot = (vx-lh.x) * lfn.x + (vy-lh.y) * lfn.y + (vz-lh.z) * lfn.z;
      pos.setXYZ(v, vx - lfn.x * dot * str, vy - lfn.y * dot * str, vz - lfn.z * dot * str);
    }
  }
  pos.needsUpdate = true; state.sculptHitPt = hit.point.clone();
}

export function setupSculpting() {
  state.container.addEventListener('mousedown', e => {
    if (!state.sculptMode || e.button !== 0) return;
    const rect = state.container.getBoundingClientRect();
    state.mouse.x =  ((e.clientX - rect.left) / rect.width)  * 2 - 1;
    state.mouse.y = -((e.clientY - rect.top)  / rect.height) * 2 + 1;
    state.raycaster.setFromCamera(state.mouse, state.camera);
    const hits = state.raycaster.intersectObjects(state.loadedMeshes.map(m => m.mesh).filter(m => m.visible), false);
    if (!hits.length) return;
    state.sculptTgtIdx = state.loadedMeshes.findIndex(m => m.mesh === hits[0].object);
    if (state.sculptTgtIdx === -1) return;
    pushUndoSnapshot('sculpt');
    state.isSculpting = true;
    state.sculptHitPt = hits[0].point.clone();
    state.controls.enabled = false;
    applySculptBrush(hits[0]);
  });
  state.container.addEventListener('mousemove', e => {
    if (!state.isSculpting || state.sculptTgtIdx === -1) return;
    const rect = state.container.getBoundingClientRect();
    state.mouse.x =  ((e.clientX - rect.left) / rect.width)  * 2 - 1;
    state.mouse.y = -((e.clientY - rect.top)  / rect.height) * 2 + 1;
    state.raycaster.setFromCamera(state.mouse, state.camera);
    const hits = state.raycaster.intersectObject(state.loadedMeshes[state.sculptTgtIdx].mesh, false);
    if (hits.length) applySculptBrush(hits[0]);
  });
  state.container.addEventListener('mouseup', () => {
    if (!state.isSculpting) return;
    state.isSculpting = false;
    state.controls.enabled = true;
    if (state.sculptTgtIdx !== -1) state.loadedMeshes[state.sculptTgtIdx].mesh.geometry.computeVertexNormals();
  });
}
