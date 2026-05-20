// Articulated-joint binding, dock + control-panel rendering, per-part
// auto-preview state machine, demo tick, and transform application.
//
// Reads/writes mutable joint state via `state.*`. Has no direct dependency on
// the history/persistence modules — the inline script wires `saveEditorState`
// in via `setSaveEditorState(fn)` so this stays a clean leaf in the module
// graph. PR 8 replaces that callback with a direct import once persistence is
// extracted.
//
// Public entry points used by other modules:
//   - bindArticulatedJoints(joints, options)
//     Called by model.loadGLB and history.restoreSnapshot.
//   - captureJointNodes(), objectParentJointName(obj)
//     Used by history.captureSnapshot.
//   - tickJointDemo(), applyJointTransforms()
//     Hooked into the animate loop (scene.js in PR 11; currently the inline
//     animate() calls them directly).
//   - syncJointButtons(), syncDemoFlags(), stopJointAutoPreviewForEdit(action)
//     Used by history.restoreSnapshot and aiEdit.pushUndoSnapshot.

/**
 * @typedef {Object} Joint
 * @property {string} name                            Bone name (must match an Object3D in modelGroup).
 * @property {'rotation'|'translation'} kind          Joint type — sets which axis units apply.
 * @property {'X'|'Y'|'Z'} axis                       Local axis the slider drives.
 * @property {number} [rest_deg]                      Rest value (degrees, rotation joints).
 * @property {number} [min_deg]                       Min slider value (degrees).
 * @property {number} [max_deg]                       Max slider value (degrees).
 * @property {number} [rest_m]                        Rest value (metres, translation joints).
 * @property {number} [min_m]                         Min slider value (metres).
 * @property {number} [max_m]                         Max slider value (metres).
 * @property {string} [skipped_reason]                Present when the AI flagged the joint as unusable.
 * @property {string} [child_mesh]                    Mesh attached to the joint (for display name).
 * @property {string} [description]                   Human label (fallback display name).
 */

import { THREE } from '@nova/three-ext.js';
import { state } from '@nova/state.js';
import { jointDisplayName, jointSafeName, jointUnit, jointPrecision } from '@nova/util.js';

let _saveEditorState = () => {};
export function setSaveEditorState(fn) { _saveEditorState = typeof fn === 'function' ? fn : (() => {}); }

// ── Joint node discovery + snapshot helpers ──────────────────────────────────
export function objectParentJointName(object) {
  let node = object?.parent;
  while (node && node !== state.modelGroup) {
    if (state.articulatedObjects[node.name]) return node.name;
    node = node.parent;
  }
  return null;
}

export function captureJointNodes() {
  // Ensure world matrices are up-to-date before computing transforms.
  state.modelGroup.updateMatrixWorld(true);
  return state.articulatedJoints.map(joint => {
    const obj = state.articulatedObjects[joint.name];
    if (!obj) return null;
    obj.updateMatrixWorld(true);

    const parentJointName = objectParentJointName(obj);
    const parentObj = parentJointName ? state.articulatedObjects[parentJointName] : null;
    // After restoreSnapshot, root joints reparent to modelGroup; child joints
    // reparent to their parent joint object. Intermediate gltf nodes are not
    // recreated, so capture transforms relative to that future parent.
    const restoreParent = parentObj || state.modelGroup;
    restoreParent.updateMatrixWorld(true);

    const toParent = new THREE.Matrix4().copy(restoreParent.matrixWorld).invert();
    const localMat = new THREE.Matrix4().multiplyMatrices(toParent, obj.matrixWorld);
    const pos = new THREE.Vector3(), q = new THREE.Quaternion(), sc = new THREE.Vector3();
    localMat.decompose(pos, q, sc);
    const rot = new THREE.Euler().setFromQuaternion(q, obj.rotation.order || 'XYZ');

    const restPosInObjParent = (obj.userData.restPos || obj.position).clone();
    const restRotInObjParent = obj.userData.restRot || obj.rotation;
    const restQ = new THREE.Quaternion().setFromEuler(restRotInObjParent);
    const restTRS = new THREE.Matrix4().compose(restPosInObjParent, restQ, obj.scale.clone());
    const objParentWorld = obj.parent ? obj.parent.matrixWorld.clone() : new THREE.Matrix4();
    const restWorldMat = new THREE.Matrix4().multiplyMatrices(objParentWorld, restTRS);
    const restLocalMat = new THREE.Matrix4().multiplyMatrices(toParent, restWorldMat);
    const restPos = new THREE.Vector3(), restQ2 = new THREE.Quaternion(), restSc2 = new THREE.Vector3();
    restLocalMat.decompose(restPos, restQ2, restSc2);
    const restRot = new THREE.Euler().setFromQuaternion(restQ2, obj.rotation.order || 'XYZ');

    return { name:joint.name, parentJointName, position:pos, rotation:rot, scale:sc, restPos, restRot };
  }).filter(Boolean);
}

// ── Joint binding ────────────────────────────────────────────────────────────
function findObjectForJoint(joint) {
  let best = null;
  state.modelGroup.traverse(node => {
    if (best || !node.name) return;
    if (node.name === joint.name) best = node;
  });
  return best;
}

export function bindArticulatedJoints(joints, options = {}) {
  state.currentJoints = Array.isArray(joints) ? joints.filter(Boolean) : [];
  state.articulatedJoints = state.currentJoints.filter(j =>
    j && j.name && !j.skipped_reason &&
    (j.kind === 'rotation' || j.kind === 'translation') &&
    j.axis
  );
  state.articulatedObjects = {};
  if (!options.preserveValues) {
    state.jointSliderValues = {};
    state.jointDirectionMultipliers = {};
  }

  if (state.articulatedJoints.length === 0) {
    state.selectedArticulatedJointName = '';
    state.jointAutoPreviewSet.clear();
    for (const k of Object.keys(state.jointDemoPhases)) delete state.jointDemoPhases[k];
    syncDemoFlags();
    syncJointButtons();
    renderJointSliders();
    renderArticulationDock();
    return;
  }

  state.articulatedJoints.forEach(joint => {
    const obj = findObjectForJoint(joint);
    if (!obj) return;
    state.articulatedObjects[joint.name] = obj;
    if (!obj.userData.restPos) obj.userData.restPos = obj.position.clone();
    if (!obj.userData.restRot) obj.userData.restRot = obj.rotation.clone();
    if (state.jointSliderValues[joint.name] === undefined) {
      state.jointSliderValues[joint.name] = joint.kind === 'rotation'
        ? (joint.rest_deg || 0)
        : (joint.rest_m || 0);
    }
    if (state.jointDirectionMultipliers[joint.name] === undefined) {
      state.jointDirectionMultipliers[joint.name] = 1;
    }
  });

  state.articulatedJoints = state.articulatedJoints.filter(joint => state.articulatedObjects[joint.name]);
  if (!state.articulatedJoints.some(joint => joint.name === state.selectedArticulatedJointName)) {
    state.selectedArticulatedJointName = state.articulatedJoints[0]?.name || '';
  }
  renderJointSliders();
  renderArticulationDock();
  if (state.articulatedJoints.length === 0) {
    state.selectedArticulatedJointName = '';
    state.jointAutoPreviewSet.clear();
    for (const k of Object.keys(state.jointDemoPhases)) delete state.jointDemoPhases[k];
    syncDemoFlags();
    syncJointButtons();
    renderArticulationDock();
    return;
  }
  if (options.autoStart === true) {
    state.jointDemoMode = 'all';
    if (state.selectedArticulatedJointName) enableJointAutoPreview(state.selectedArticulatedJointName);
  } else if (!options.preserveValues) {
    state.jointAutoPreviewSet.clear();
    for (const k of Object.keys(state.jointDemoPhases)) delete state.jointDemoPhases[k];
    syncDemoFlags();
  } else {
    [...state.jointAutoPreviewSet].forEach(n => {
      if (!state.articulatedJoints.some(j => j.name === n)) {
        state.jointAutoPreviewSet.delete(n);
        delete state.jointDemoPhases[n];
      }
    });
    syncDemoFlags();
  }
  syncJointButtons();
}

// ── Per-row UI rendering ─────────────────────────────────────────────────────
export function renderJointSliders() {
  const list = document.getElementById('jointsList');
  if (!list) return;
  list.innerHTML = '';
  state.articulatedJoints.forEach(joint => {
    const isRot = joint.kind === 'rotation';
    const min = Number(isRot ? joint.min_deg : joint.min_m) || 0;
    const max = Number(isRot ? joint.max_deg : joint.max_m) || 0;
    const cur = Number(state.jointSliderValues[joint.name] ?? (isRot ? joint.rest_deg : joint.rest_m) ?? 0);
    const unit = isRot ? 'deg' : 'm';
    const safeName = joint.name.replace(/[^a-zA-Z0-9]/g, '_');
    const niceName = jointDisplayName(joint);
    const row = document.createElement('div');
    row.className = 'joint-row';
    row.innerHTML = `
      <div class="joint-row-head">
        <span class="joint-name"></span>
        <span class="joint-kind">${joint.kind} ${String(joint.axis || '').toUpperCase()}</span>
      </div>
      <div class="joint-control">
        <input type="range" id="joint-slider-${safeName}" min="${min}" max="${max}" step="${isRot ? '0.5' : '0.001'}" value="${cur}">
        <span class="joint-value" id="joint-value-${safeName}">${cur.toFixed(isRot ? 1 : 3)} ${unit}</span>
      </div>
      <div class="joint-axis-row">
        <button class="joint-axis-btn" data-axis="X">X</button>
        <button class="joint-axis-btn" data-axis="Y">Y</button>
        <button class="joint-axis-btn" data-axis="Z">Z</button>
        <button class="joint-axis-btn" data-axis="flip">Flip</button>
      </div>
    `;
    row.querySelector('.joint-name').textContent = niceName;
    list.appendChild(row);

    const slider = row.querySelector('input');
    slider.addEventListener('input', e => {
      const value = parseFloat(e.target.value);
      state.jointSliderValues[joint.name] = value;
      updateJointValueUi(joint, value);
      if (state.jointAutoPreviewSet.has(joint.name)) {
        disableJointAutoPreview(joint.name);
        renderArticulationDock();
      }
      applyJointTransforms();
      _saveEditorState();
    });
    row.querySelectorAll('.joint-axis-btn').forEach(btn => {
      const axis = btn.dataset.axis;
      btn.classList.toggle('active', axis === String(joint.axis || '').toUpperCase());
      btn.onclick = () => axis === 'flip'
        ? flipJointDirection(joint.name)
        : setJointAxis(joint.name, axis);
    });
  });
}

function updateJointValueUi(joint, value) {
  const safeName = jointSafeName(joint);
  const formatted = `${Number(value || 0).toFixed(jointPrecision(joint))} ${jointUnit(joint)}`;
  const flyoutValue = document.getElementById(`joint-value-${safeName}`);
  if (flyoutValue) flyoutValue.textContent = formatted;
  const dockValue = document.getElementById(`articulation-value-${safeName}`);
  if (dockValue) dockValue.textContent = formatted;
  const flyoutSlider = document.getElementById(`joint-slider-${safeName}`);
  if (flyoutSlider) flyoutSlider.value = value;
  const dockSlider = document.getElementById(`articulation-slider-${safeName}`);
  if (dockSlider) dockSlider.value = value;
}

export function renderArticulationDock() {
  const dock = document.getElementById('articulationDock');
  const list = document.getElementById('articulationList');
  if (!dock || !list) return;
  const hasJoints = state.articulatedJoints.length > 0;
  dock.classList.toggle('active', hasJoints);
  let restoreAllBtn = document.getElementById('articulationRestoreAllBtn');
  if (!hasJoints) {
    list.innerHTML = '';
    if (restoreAllBtn) restoreAllBtn.style.display = 'none';
    renderArticulationDetail();
    return;
  }

  list.innerHTML = '';
  state.articulatedJoints.forEach(joint => {
    const btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'articulation-item';
    btn.classList.toggle('active', joint.name === state.selectedArticulatedJointName);
    const previewing = state.jointAutoPreviewSet.has(joint.name);
    btn.textContent = (previewing ? '▶ ' : '') + jointDisplayName(joint);
    btn.title = joint.description || joint.name;
    btn.onclick = () => selectArticulatedJoint(joint.name);
    list.appendChild(btn);
  });

  if (!restoreAllBtn) {
    restoreAllBtn = document.createElement('button');
    restoreAllBtn.type = 'button';
    restoreAllBtn.id = 'articulationRestoreAllBtn';
    restoreAllBtn.className = 'articulation-restore-all';
    restoreAllBtn.textContent = 'Restore All';
    restoreAllBtn.title = 'Stop all previews and reset every part to its default pose';
    restoreAllBtn.onclick = () => restoreAllJointPoses();
    dock.appendChild(restoreAllBtn);
  }
  restoreAllBtn.style.display = '';
  renderArticulationDetail();
}

export function renderArticulationDetail() {
  const panel = document.getElementById('articulationControlPanel');
  if (!panel) return;
  const joint = state.articulatedJoints.find(item => item.name === state.selectedArticulatedJointName);
  panel.classList.toggle('active', Boolean(joint));
  if (!joint) {
    panel.innerHTML = '';
    return;
  }
  const isRot = joint.kind === 'rotation';
  const min = Number(isRot ? joint.min_deg : joint.min_m) || 0;
  const max = Number(isRot ? joint.max_deg : joint.max_m) || 0;
  const value = Number(state.jointSliderValues[joint.name] ?? (isRot ? joint.rest_deg : joint.rest_m) ?? 0);
  const safeName = jointSafeName(joint);
  panel.innerHTML = `
    <h3></h3>
    <div class="articulation-meta">${joint.kind} · local ${String(joint.axis || '').toUpperCase()} axis</div>
    <div class="articulation-slider-row">
      <input type="range" id="articulation-slider-${safeName}" min="${min}" max="${max}" step="${isRot ? '0.5' : '0.001'}" value="${value}">
      <span id="articulation-value-${safeName}">${value.toFixed(jointPrecision(joint))} ${jointUnit(joint)}</span>
    </div>
    <div class="articulation-axis-grid">
      <button type="button" data-axis="X" title="Use the joint node's local X axis">X</button>
      <button type="button" data-axis="Y" title="Use the joint node's local Y axis">Y</button>
      <button type="button" data-axis="Z" title="Use the joint node's local Z axis">Z</button>
      <button type="button" data-axis="flip">Flip</button>
    </div>
    <div class="articulation-command-grid">
      <button type="button" id="articulationAutoBtn" class="${state.jointAutoPreviewSet.has(joint.name) ? 'primary' : ''}">${state.jointAutoPreviewSet.has(joint.name) ? 'Stop Preview' : 'Auto Preview'}</button>
      <button type="button" id="articulationRestoreBtn">Restore</button>
    </div>
  `;
  panel.querySelector('h3').textContent = jointDisplayName(joint);
  const slider = panel.querySelector(`#articulation-slider-${safeName}`);
  slider?.addEventListener('input', e => {
    const next = parseFloat(e.target.value);
    state.jointSliderValues[joint.name] = next;
    updateJointValueUi(joint, next);
    if (state.jointAutoPreviewSet.has(joint.name)) {
      disableJointAutoPreview(joint.name);
      renderArticulationDock();
    }
    applyJointTransforms();
    _saveEditorState();
  });
  panel.querySelectorAll('button[data-axis]').forEach(btn => {
    const axis = btn.dataset.axis;
    btn.classList.toggle('active', axis === String(joint.axis || '').toUpperCase());
    btn.onclick = () => axis === 'flip'
      ? flipJointDirection(joint.name)
      : setJointAxis(joint.name, axis);
  });
  const autoBtn = panel.querySelector('#articulationAutoBtn');
  if (autoBtn) autoBtn.onclick = () => toggleSelectedJointAutoPreview();
  const restoreBtn = panel.querySelector('#articulationRestoreBtn');
  if (restoreBtn) restoreBtn.onclick = () => restoreSelectedJointPose();
}

// ── Selection + demo state machine ───────────────────────────────────────────
export function selectArticulatedJoint(jointName) {
  if (!state.articulatedJoints.some(joint => joint.name === jointName)) return;
  state.selectedArticulatedJointName = jointName;
  renderArticulationDock();
}

export function syncJointButtons() {
  const demoBtn = document.getElementById('jointDemoBtn');
  if (demoBtn) demoBtn.textContent = state.jointDemoActive ? 'Auto-demo: ON' : 'Auto-demo: OFF';
  const modeBtn = document.getElementById('jointModeBtn');
  if (modeBtn) modeBtn.textContent = state.jointDemoMode === 'all' ? 'Mode: All' : 'Mode: One';
}

export function toggleJointDemo() {
  if (state.jointAutoPreviewSet.size > 0) {
    state.jointAutoPreviewSet.clear();
    for (const k of Object.keys(state.jointDemoPhases)) delete state.jointDemoPhases[k];
  } else if (state.selectedArticulatedJointName) {
    enableJointAutoPreview(state.selectedArticulatedJointName);
  }
  syncDemoFlags();
  syncJointButtons();
  renderArticulationDock();
}

export function toggleJointDemoMode() {
  state.jointDemoMode = state.jointDemoMode === 'all' ? 'cycle' : 'all';
  state.jointDemoTime = 0;
  state.jointDemoLastFrame = performance.now();
  syncJointButtons();
}

export function resetJointControls() {
  state.jointAutoPreviewSet.clear();
  for (const k of Object.keys(state.jointDemoPhases)) delete state.jointDemoPhases[k];
  state.articulatedJoints.forEach(joint => {
    state.jointSliderValues[joint.name] = joint.kind === 'rotation'
      ? (joint.rest_deg || 0)
      : (joint.rest_m || 0);
    state.jointDirectionMultipliers[joint.name] = 1;
  });
  syncDemoFlags();
  renderJointSliders();
  renderArticulationDock();
  applyJointTransforms();
  _saveEditorState();
}

function resetJointToRest(joint) {
  if (!joint) return;
  state.jointSliderValues[joint.name] = joint.kind === 'rotation'
    ? (joint.rest_deg || 0)
    : (joint.rest_m || 0);
  state.jointDirectionMultipliers[joint.name] = 1;
  updateJointValueUi(joint, state.jointSliderValues[joint.name]);
}

export function isJointAutoPreviewing(name) {
  return state.jointAutoPreviewSet.has(name);
}

export function enableJointAutoPreview(name) {
  if (!state.articulatedJoints.some(j => j.name === name)) return;
  state.jointAutoPreviewSet.add(name);
  state.jointDemoPhases[name] = { time:0, lastFrame:performance.now() };
  syncDemoFlags();
}

export function disableJointAutoPreview(name) {
  state.jointAutoPreviewSet.delete(name);
  delete state.jointDemoPhases[name];
  syncDemoFlags();
}

export function syncDemoFlags() {
  state.jointDemoActive = state.jointAutoPreviewSet.size > 0;
  state.jointAutoPreviewEnabled = state.jointDemoActive;
}

function toggleSelectedJointAutoPreview() {
  if (!state.selectedArticulatedJointName) return;
  if (state.jointAutoPreviewSet.has(state.selectedArticulatedJointName)) {
    disableJointAutoPreview(state.selectedArticulatedJointName);
  } else {
    enableJointAutoPreview(state.selectedArticulatedJointName);
  }
  renderArticulationDock();
}

function restoreSelectedJointPose() {
  const joint = state.articulatedJoints.find(item => item.name === state.selectedArticulatedJointName);
  if (!joint) return;
  disableJointAutoPreview(joint.name);
  resetJointToRest(joint);
  renderJointSliders();
  renderArticulationDock();
  applyJointTransforms();
  _saveEditorState();
}

export function restoreAllJointPoses() {
  if (!state.articulatedJoints.length) return;
  state.jointAutoPreviewSet.clear();
  for (const k of Object.keys(state.jointDemoPhases)) delete state.jointDemoPhases[k];
  state.articulatedJoints.forEach(joint => {
    state.jointSliderValues[joint.name] = joint.kind === 'rotation'
      ? (joint.rest_deg || 0)
      : (joint.rest_m || 0);
    state.jointDirectionMultipliers[joint.name] = 1;
  });
  syncDemoFlags();
  renderJointSliders();
  renderArticulationDock();
  applyJointTransforms();
  _saveEditorState();
}

export function stopJointAutoPreviewForEdit(action) {
  if (!state.articulatedJoints.length) return;
  if (action === 'articulate_3d_model') return;
  state.jointAutoPreviewSet.clear();
  for (const k of Object.keys(state.jointDemoPhases)) delete state.jointDemoPhases[k];
  syncDemoFlags();
  renderArticulationDock();
}

export function flipJointDirection(jointName) {
  state.jointDirectionMultipliers[jointName] = -(state.jointDirectionMultipliers[jointName] || 1);
  renderArticulationDock();
  applyJointTransforms();
  _saveEditorState();
}

export function setJointAxis(jointName, axis) {
  const joint = state.articulatedJoints.find(item => item.name === jointName);
  if (!joint) return;
  joint.axis = String(axis || 'X').toUpperCase();
  state.jointSliderValues[jointName] = joint.kind === 'rotation'
    ? (joint.rest_deg || 0)
    : (joint.rest_m || 0);
  renderJointSliders();
  renderArticulationDock();
  applyJointTransforms();
  _saveEditorState();
}

// ── Per-frame work (called from animate loop) ────────────────────────────────
export function tickJointDemo() {
  if (state.jointAutoPreviewSet.size === 0 || state.articulatedJoints.length === 0) return;
  const now = performance.now();

  const setJointDemoValue = (joint, phase) => {
    const isRot = joint.kind === 'rotation';
    const min = Number(isRot ? joint.min_deg : joint.min_m) || 0;
    const max = Number(isRot ? joint.max_deg : joint.max_m) || 0;
    const span = max - min;
    const safeMin = min + span * 0.15;
    const safeMax = max - span * 0.15;
    const value = safeMin + (safeMax - safeMin) * phase;
    state.jointSliderValues[joint.name] = value;
    const safeName = joint.name.replace(/[^a-zA-Z0-9]/g, '_');
    const slider = document.getElementById(`joint-slider-${safeName}`);
    if (slider) slider.value = value;
    updateJointValueUi(joint, value);
  };

  state.jointAutoPreviewSet.forEach(name => {
    const joint = state.articulatedJoints.find(j => j.name === name);
    if (!joint) { state.jointAutoPreviewSet.delete(name); delete state.jointDemoPhases[name]; return; }
    let phaseState = state.jointDemoPhases[name];
    if (!phaseState) {
      phaseState = { time:0, lastFrame:now };
      state.jointDemoPhases[name] = phaseState;
    }
    const dt = phaseState.lastFrame ? (now - phaseState.lastFrame) / 1000 : 0;
    phaseState.lastFrame = now;
    phaseState.time += dt;
    const phase = 0.5 - 0.5 * Math.cos((phaseState.time / 3.5) * Math.PI * 2);
    setJointDemoValue(joint, phase);
  });
  syncDemoFlags();
}

export function applyJointTransforms() {
  if (!state.articulatedJoints.length) return;
  const axisMap = { X:'x', Y:'y', Z:'z' };
  state.articulatedJoints.forEach(joint => {
    const obj = state.articulatedObjects[joint.name];
    if (!obj) return;
    const axis = axisMap[String(joint.axis || 'X').toUpperCase()] || 'x';
    const value = Number(state.jointSliderValues[joint.name] || 0);
    const direction = state.jointDirectionMultipliers[joint.name] || 1;
    if (joint.kind === 'rotation') {
      const rest = obj.userData.restRot || new THREE.Euler();
      obj.rotation.set(rest.x, rest.y, rest.z);
      obj.rotation[axis] = rest[axis] + THREE.MathUtils.degToRad(value * direction);
      return;
    }
    const rest = obj.userData.restPos || new THREE.Vector3();
    obj.position.copy(rest);
    obj.position[axis] = rest[axis] + value * direction;
  });
}
