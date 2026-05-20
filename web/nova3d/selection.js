// Mesh selection, mesh-list rendering, raycaster picker, mesh-panel buttons,
// transform proxy attach/detach, transform-panel apply-on-Enter, and the
// numeric transform operations bound to that panel.
//
// Cross-module hooks (set by inline boot in PR 10):
//   - setSelectionHooks({ isFullUi })
//     `isFullUi` lives in ui/flyouts.js (PR 12); for now the inline boot wires
//     it. Used as a click guard so raycaster clicks don't fire while the
//     viewer is in compact (non-editor) mode.

import { THREE } from '@nova/three-ext.js';
import { state } from '@nova/state.js';
import { iconSvg } from '@nova/util.js';
import { highlightMat } from '@nova/materials.js';
import { pushUndoSnapshot } from '@nova/history.js';

let _isFullUi = () => true;
export function setSelectionHooks({ isFullUi } = {}) {
  if (typeof isFullUi === 'function') _isFullUi = isFullUi;
}

// ── Mesh list ────────────────────────────────────────────────────────────────
export function updateMeshList(options = {}) {
  const list   = document.getElementById('meshList');
  const search = document.getElementById('meshSearch').value.toLowerCase();
  if (!state.loadedMeshes.length) {
    list.innerHTML = '<div style="text-align:center;color:#444;font-size:10px;padding:20px">Load a model to see parts</div>';
    syncSelectionActions();
    return;
  }
  let html = '';
  state.loadedMeshes.forEach((m, idx) => {
    if (search && !m.name.toLowerCase().includes(search)) return;
    const sel    = state.selectedMeshIndices.has(idx);
    const hidden = !m.mesh.visible;
    const verts  = m.geometry.attributes.position ? m.geometry.attributes.position.count : 0;
    const faces  = m.geometry.index ? m.geometry.index.count / 3 : verts / 3;
    html += `<div class="mesh-item${sel ? ' selected' : ''}${hidden ? ' hidden-mesh' : ''}" data-idx="${idx}">
      <div class="mesh-item-name">${hidden ? '[H] ' : ''}${m.name}</div>
      <div class="mesh-item-info">${verts.toLocaleString()} verts / ${Math.round(faces).toLocaleString()} faces</div>
    </div>`;
  });
  list.innerHTML = html || '<div style="text-align:center;color:#444;font-size:10px;padding:20px">No match</div>';
  list.querySelectorAll('.mesh-item').forEach(item => {
    item.onclick = e => {
      const idx = parseInt(item.dataset.idx);
      if (e.ctrlKey || e.metaKey) { state.selectedMeshIndices.has(idx) ? state.selectedMeshIndices.delete(idx) : state.selectedMeshIndices.add(idx); }
      else if (e.shiftKey && state.selectedMeshIndices.size > 0) {
        const last = Math.max(...state.selectedMeshIndices);
        for (let i = Math.min(last, idx); i <= Math.max(last, idx); i++) state.selectedMeshIndices.add(i);
      }
      else { state.selectedMeshIndices.clear(); state.selectedMeshIndices.add(idx); }
      state.lastSelectionAction = null;
      state.lastSelectedMeshIndex = idx;
      updateMeshList({ scrollToSelection: true });
      updateHighlights();
      if (state.currentMode !== 'orbit') attachTransformToSelection();
    };
  });
  syncSelectionActions();
  if (options.scrollToSelection) scrollSelectedMeshIntoView();
}

export function syncSelectionActions() {
  const toolbar = document.getElementById('selectionActions');
  const countEl = document.getElementById('selectionCount');
  const count = state.selectedMeshIndices.size;
  if (toolbar) toolbar.classList.toggle('has-selection', count > 0);
  if (countEl) countEl.textContent = count === 1 ? '1 selected' : `${count} selected`;

  const selected = [...state.selectedMeshIndices].map(i => state.loadedMeshes[i]).filter(Boolean);
  const hiddenSelected = selected.filter(entry => !entry.mesh.visible).length;
  const hiddenTotal = state.loadedMeshes.filter(entry => !entry.mesh.visible).length;
  const allSelected = state.loadedMeshes.length > 0 && count === state.loadedMeshes.length;
  const focused = count > 0 && hiddenTotal > 0 && state.loadedMeshes.every((entry, idx) =>
    state.selectedMeshIndices.has(idx) ? entry.mesh.visible : !entry.mesh.visible
  );

  const visibilityBtn = document.getElementById('actVisibility');
  const visibilityLabel = document.getElementById('actVisibilityLabel');
  const visibilityIcon = document.getElementById('actVisibilityIcon');
  const showAllBtn = document.getElementById('actShowAll');
  const isolateBtn = document.getElementById('actIsolate');
  const selectAllBtn = document.getElementById('selectAll');
  const selectNoneBtn = document.getElementById('selectNone');
  const invertBtn = document.getElementById('selectInvert');

  if (visibilityLabel) visibilityLabel.textContent = hiddenSelected > 0 ? 'Unhide' : 'Hide';
  if (visibilityBtn) {
    visibilityBtn.title = hiddenSelected > 0 ? 'Unhide the selected hidden parts' : 'Hide the selected visible parts';
    visibilityBtn.classList.toggle('active', hiddenSelected > 0 || state.lastSelectionAction === 'visibility');
  }
  if (visibilityIcon) visibilityIcon.innerHTML = hiddenSelected > 0 ? iconSvg('eye') : iconSvg('eye-off');
  if (showAllBtn) {
    showAllBtn.disabled = hiddenTotal === 0;
    showAllBtn.classList.toggle('active', state.lastSelectionAction === 'show-all');
  }
  if (isolateBtn) isolateBtn.classList.toggle('active', focused || state.lastSelectionAction === 'isolate');
  if (selectAllBtn) selectAllBtn.classList.toggle('active', allSelected || state.lastSelectionAction === 'select-all');
  if (selectNoneBtn) selectNoneBtn.classList.toggle('active', state.lastSelectionAction === 'select-none');
  if (invertBtn) invertBtn.classList.toggle('active', state.lastSelectionAction === 'invert');
}

export function scrollSelectedMeshIntoView() {
  const list = document.getElementById('meshList');
  if (!list || !state.selectedMeshIndices.size) return;
  const targetIdx = state.lastSelectedMeshIndex != null && state.selectedMeshIndices.has(state.lastSelectedMeshIndex)
    ? state.lastSelectedMeshIndex
    : Math.min(...state.selectedMeshIndices);
  const item = list.querySelector(`.mesh-item[data-idx="${targetIdx}"]`) || list.querySelector('.mesh-item.selected');
  if (!item) return;
  item.scrollIntoView({ block: 'center', inline: 'nearest', behavior: 'smooth' });
}

// ── Highlight overlay + transform-panel value mirror ─────────────────────────
export function updateHighlights() {
  state.loadedMeshes.forEach((m, idx) => { m.mesh.material = state.selectedMeshIndices.has(idx) ? highlightMat : m.originalMaterial; });
  if (state.selectedMeshIndices.size === 1) {
    const mesh = state.loadedMeshes[[...state.selectedMeshIndices][0]].mesh;
    const set = (id, v) => { const el = document.getElementById(id); if (el) el.value = v; };
    set('tfPosX', mesh.position.x.toFixed(4)); set('tfPosY', mesh.position.y.toFixed(4)); set('tfPosZ', mesh.position.z.toFixed(4));
    set('tfRotX', (mesh.rotation.x * 180/Math.PI).toFixed(1)); set('tfRotY', (mesh.rotation.y * 180/Math.PI).toFixed(1)); set('tfRotZ', (mesh.rotation.z * 180/Math.PI).toFixed(1));
    set('tfScaleX', mesh.scale.x.toFixed(4)); set('tfScaleY', mesh.scale.y.toFixed(4)); set('tfScaleZ', mesh.scale.z.toFixed(4));
    set('tfScale', ((mesh.scale.x + mesh.scale.y + mesh.scale.z) / 3).toFixed(4));
  }
}

// ── Multi-mesh transform proxy ───────────────────────────────────────────────
export function attachTransformToSelection() {
  if (!state.selectedMeshIndices.size || state.currentMode === 'orbit') { state.transformControls.detach(); return; }
  detachProxy();
  if (state.selectedMeshIndices.size === 1) {
    state.transformControls.attach(state.loadedMeshes[[...state.selectedMeshIndices][0]].mesh);
    return;
  }
  const arr = [...state.selectedMeshIndices];
  const center = new THREE.Vector3();
  arr.forEach(i => { const wp = new THREE.Vector3(); state.loadedMeshes[i].mesh.getWorldPosition(wp); center.add(wp); });
  center.divideScalar(arr.length);
  state.transformProxy.position.copy(center); state.transformProxy.rotation.set(0,0,0); state.transformProxy.scale.set(1,1,1);
  arr.forEach(i => { const m = state.loadedMeshes[i].mesh; m.userData._origParent = m.parent; state.transformProxy.attach(m); });
  state.transformControls.attach(state.transformProxy);
}

export function detachProxy() {
  [...state.transformProxy.children].forEach(m => { (m.userData._origParent || state.modelGroup).attach(m); delete m.userData._origParent; });
}

// ── Raycaster picker ─────────────────────────────────────────────────────────
export function setupRaycasting() {
  let down = { x: 0, y: 0 };
  state.container.addEventListener('mousedown', e => { down = { x: e.clientX, y: e.clientY }; });
  state.container.addEventListener('click', e => {
    if (!_isFullUi()) return;
    if (Math.abs(e.clientX - down.x) > 5 || Math.abs(e.clientY - down.y) > 5) return;
    if (state.sculptMode) return;
    const rect = state.container.getBoundingClientRect();
    state.mouse.x = ((e.clientX - rect.left) / rect.width) * 2 - 1;
    state.mouse.y = -((e.clientY - rect.top) / rect.height) * 2 + 1;
    state.raycaster.setFromCamera(state.mouse, state.camera);
    const hits = state.raycaster.intersectObjects(state.loadedMeshes.map(m => m.mesh).filter(m => m.visible), false);
    if (!hits.length) {
      if (state.selectedMeshIndices.size) {
        state.selectedMeshIndices.clear(); state.lastSelectedMeshIndex = null;
        state.transformControls.detach(); updateMeshList(); updateHighlights();
      }
      return;
    }
    const idx = state.loadedMeshes.findIndex(m => m.mesh === hits[0].object); if (idx === -1) return;
    if (e.ctrlKey || e.metaKey) { state.selectedMeshIndices.has(idx) ? state.selectedMeshIndices.delete(idx) : state.selectedMeshIndices.add(idx); }
    else if (e.shiftKey && state.selectedMeshIndices.size > 0) {
      const last = Math.max(...state.selectedMeshIndices);
      for (let i = Math.min(last, idx); i <= Math.max(last, idx); i++) state.selectedMeshIndices.add(i);
    }
    else { state.selectedMeshIndices.clear(); state.selectedMeshIndices.add(idx); }
    state.lastSelectionAction = null;
    state.lastSelectedMeshIndex = idx;
    updateMeshList({ scrollToSelection: true });
    updateHighlights();
    if (state.currentMode !== 'orbit') attachTransformToSelection();
  });
  state.container.addEventListener('contextmenu', e => {
    if (!_isFullUi()) return;
    e.preventDefault();
    if (state.selectedMeshIndices.size) {
      state.selectedMeshIndices.clear(); state.lastSelectedMeshIndex = null;
      state.transformControls.detach(); updateMeshList(); updateHighlights();
    }
  });
}

// ── Mesh-panel buttons ───────────────────────────────────────────────────────
export function setupMeshButtons() {
  document.getElementById('selectAll').onclick    = () => { state.lastSelectionAction = 'select-all'; state.loadedMeshes.forEach((_, i) => state.selectedMeshIndices.add(i)); state.lastSelectedMeshIndex = 0; updateMeshList({ scrollToSelection: true }); updateHighlights(); };
  document.getElementById('selectNone').onclick   = () => { state.lastSelectionAction = 'select-none'; state.selectedMeshIndices.clear(); state.lastSelectedMeshIndex = null; state.transformControls.detach(); updateMeshList(); updateHighlights(); };
  document.getElementById('selectInvert').onclick = () => { state.lastSelectionAction = 'invert'; const n = new Set(); state.loadedMeshes.forEach((_, i) => { if (!state.selectedMeshIndices.has(i)) n.add(i); }); state.selectedMeshIndices = n; state.lastSelectedMeshIndex = state.selectedMeshIndices.size ? Math.min(...state.selectedMeshIndices) : null; updateMeshList({ scrollToSelection: true }); updateHighlights(); };
  document.getElementById('meshSearch').oninput   = () => updateMeshList();
  document.getElementById('actVisibility').onclick = () => {
    if (!state.selectedMeshIndices.size) return;
    pushUndoSnapshot('visibility');
    state.lastSelectionAction = 'visibility';
    const shouldShow = [...state.selectedMeshIndices].some(i => state.loadedMeshes[i] && !state.loadedMeshes[i].mesh.visible);
    state.selectedMeshIndices.forEach(i => { state.loadedMeshes[i].mesh.visible = shouldShow; });
    updateMeshList();
  };
  document.getElementById('actShowAll').onclick = () => { pushUndoSnapshot('show-all'); state.lastSelectionAction = 'show-all'; state.loadedMeshes.forEach(m => { m.mesh.visible = true; }); updateMeshList(); };
  document.getElementById('actIsolate').onclick = () => { if (!state.selectedMeshIndices.size) return; pushUndoSnapshot('isolate'); state.lastSelectionAction = 'isolate'; state.loadedMeshes.forEach((m, i) => { m.mesh.visible = state.selectedMeshIndices.has(i); }); updateMeshList(); };
}

// ── Transform panel — apply on Enter ─────────────────────────────────────────
export function setupTransformPanel() {
  const tfFlyout = document.getElementById('flyTransform');
  if (!tfFlyout) return;
  tfFlyout.addEventListener('keydown', e => {
    if (e.key !== 'Enter') return;
    e.preventDefault();
    const id = e.target?.id;
    if (id === 'tfScale') { applyUniformScale(); }
    else { applyNumericTransform(); }
    e.target?.blur();
  });
}

// ── Numeric transform operations (bound to the transform flyout inputs) ──────
export function resetTransform() {
  if (!state.selectedMeshIndices.size) return; pushUndoSnapshot('reset-transform');
  state.selectedMeshIndices.forEach(i => { const m = state.loadedMeshes[i].mesh; m.position.set(0,0,0); m.rotation.set(0,0,0); m.scale.set(1,1,1); });
}

export function alignToAxis(axis) {
  if (!state.selectedMeshIndices.size) return; pushUndoSnapshot('align');
  state.selectedMeshIndices.forEach(i => { state.loadedMeshes[i].mesh.position[axis] = 0; });
}

export function applyNumericTransform() {
  if (!state.selectedMeshIndices.size) return; pushUndoSnapshot('numeric-transform');
  const g = id => parseFloat(document.getElementById(id)?.value) || 0;
  const px = g('tfPosX'), py = g('tfPosY'), pz = g('tfPosZ');
  const rx = g('tfRotX') * Math.PI/180, ry = g('tfRotY') * Math.PI/180, rz = g('tfRotZ') * Math.PI/180;
  const sx = parseFloat(document.getElementById('tfScaleX')?.value) || 1;
  const sy = parseFloat(document.getElementById('tfScaleY')?.value) || 1;
  const sz = parseFloat(document.getElementById('tfScaleZ')?.value) || 1;
  state.selectedMeshIndices.forEach(i => { const m = state.loadedMeshes[i].mesh; m.position.set(px, py, pz); m.rotation.set(rx, ry, rz); m.scale.set(sx, sy, sz); });
}

export function applyUniformScale() {
  const s = parseFloat(document.getElementById('tfScale')?.value) || 1;
  ['tfScaleX','tfScaleY','tfScaleZ'].forEach(id => { const el = document.getElementById(id); if (el) el.value = s; });
  applyNumericTransform();
}

export function readCurrentTransform() {
  if (!state.selectedMeshIndices.size) return;
  const mesh = state.loadedMeshes[[...state.selectedMeshIndices][0]].mesh;
  const s = (id, v) => { const el = document.getElementById(id); if (el) el.value = v; };
  s('tfPosX', mesh.position.x.toFixed(4)); s('tfPosY', mesh.position.y.toFixed(4)); s('tfPosZ', mesh.position.z.toFixed(4));
  s('tfRotX', (mesh.rotation.x * 180/Math.PI).toFixed(1)); s('tfRotY', (mesh.rotation.y * 180/Math.PI).toFixed(1)); s('tfRotZ', (mesh.rotation.z * 180/Math.PI).toFixed(1));
  s('tfScaleX', mesh.scale.x.toFixed(4)); s('tfScaleY', mesh.scale.y.toFixed(4)); s('tfScaleZ', mesh.scale.z.toFixed(4));
  s('tfScale', ((mesh.scale.x + mesh.scale.y + mesh.scale.z) / 3).toFixed(4));
}
