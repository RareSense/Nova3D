// Visual explode/collapse mode. This module owns the temporary per-mesh offsets
// so the sidebar action stays independent from mesh editing and display modes.

import { THREE } from '@nova/three-ext.js';
import { state } from '@nova/state.js';
import { track } from '@nova/analytics.js';

const EXPLODE_SPEED = 2;
const EXPLODE_DISTANCE = 30;

const explodeState = {
  active: false,
  target: 0,
  t: 0,
  entries: [],
  meshCount: 0,
};

let controlsBound = false;

function setButtonState() {
  const btn = document.getElementById('tbExplode');
  if (!btn) return;
  btn.classList.toggle('active', explodeState.target > 0);
  btn.title = explodeState.target > 0 ? 'Collapse parts' : 'Explode parts';
  const label = btn.querySelector('.et-label');
  if (label) label.textContent = explodeState.target > 0 ? 'Collapse' : 'Explode';
  const tip = btn.querySelector('.et-tip');
  if (tip) tip.textContent = explodeState.target > 0 ? 'Collapse model parts' : 'Explode model parts';
}

function buildExplodeEntries() {
  explodeState.entries = [];
  explodeState.meshCount = state.loadedMeshes.length;
  if (!state.loadedMeshes.length || !state.modelGroup) return;

  state.modelGroup.updateMatrixWorld(true);
  const groupInverse = new THREE.Matrix4().copy(state.modelGroup.matrixWorld).invert();
  const centers = state.loadedMeshes.map(entry => {
    const mesh = entry.mesh;
    mesh.geometry.computeBoundingBox();
    const center = new THREE.Vector3();
    mesh.geometry.boundingBox.getCenter(center);
    mesh.localToWorld(center);
    center.applyMatrix4(groupInverse);
    return center;
  });

  const centroid = new THREE.Vector3();
  centers.forEach(center => centroid.add(center));
  centroid.divideScalar(Math.max(centers.length, 1));

  const box = new THREE.Box3().setFromObject(state.modelGroup);
  const sphere = new THREE.Sphere();
  box.getBoundingSphere(sphere);
  const modelRadius = sphere.radius || 1;

  let maxDistanceFromCenter = 0;
  state.loadedMeshes.forEach((entry, idx) => {
    const mesh = entry.mesh;
    const directionInGroup = centers[idx].clone().sub(centroid);
    const distanceFromCenter = directionInGroup.length();
    maxDistanceFromCenter = Math.max(maxDistanceFromCenter, distanceFromCenter);
    if (distanceFromCenter < 0.0001) {
      directionInGroup.set(Math.random() - 0.5, Math.random() - 0.5, Math.random() - 0.5);
    }
    directionInGroup.normalize();

    const directionWorld = directionInGroup.clone().transformDirection(state.modelGroup.matrixWorld);
    const parentInverse = new THREE.Matrix4();
    if (mesh.parent) parentInverse.copy(mesh.parent.matrixWorld).invert();
    const directionLocal = directionWorld.transformDirection(parentInverse).normalize();

    const testWorld = new THREE.Vector3().copy(directionLocal).applyMatrix4(mesh.parent ? mesh.parent.matrixWorld : new THREE.Matrix4());
    const originWorld = new THREE.Vector3().applyMatrix4(mesh.parent ? mesh.parent.matrixWorld : new THREE.Matrix4());
    const worldScale = testWorld.sub(originWorld).length() || 1;
    directionLocal.multiplyScalar(1 / worldScale);

    const rotationAxis = new THREE.Vector3(Math.random() - 0.5, Math.random() - 0.5, Math.random() - 0.5).normalize();
    const rotationAngle = (Math.random() * 0.25 + 0.05) * Math.PI;
    explodeState.entries.push({
      mesh,
      modelRadius,
      originalPosition: mesh.position.clone(),
      originalRotation: mesh.rotation.clone(),
      directionLocal,
      rotationAxis,
      rotationAngle,
      distanceFromCenter,
      stagger: 0,
    });
  });

  maxDistanceFromCenter = Math.max(maxDistanceFromCenter, 0.001);
  explodeState.entries.forEach(entry => {
    entry.stagger = entry.distanceFromCenter / maxDistanceFromCenter;
  });
}

function ensureEntries() {
  if (!explodeState.entries.length || explodeState.meshCount !== state.loadedMeshes.length) {
    buildExplodeEntries();
  }
}

export function toggleExplode() {
  track('explode_view_used', { enabled: !explodeState.active, mesh_count: state.loadedMeshes.length });
  if (!state.loadedMeshes.length) return;
  ensureEntries();
  explodeState.target = explodeState.target > 0 ? 0 : 1;
  explodeState.active = true;
  setButtonState();
}

export function resetExplode({ restore = true } = {}) {
  if (restore) {
    explodeState.entries.forEach(entry => {
      entry.mesh.position.copy(entry.originalPosition);
      entry.mesh.rotation.copy(entry.originalRotation);
    });
  }
  explodeState.active = false;
  explodeState.target = 0;
  explodeState.t = 0;
  explodeState.entries = [];
  explodeState.meshCount = 0;
  setButtonState();
}

export function setupExplodeControls() {
  if (controlsBound) return;
  controlsBound = true;
  const btn = document.getElementById('tbExplode');
  if (!btn) return;
  btn.addEventListener('click', (evt) => {
    evt.preventDefault();
    evt.stopPropagation();
    toggleExplode();
  });
  setButtonState();
}

export function updateExplode(dt = 1 / 60) {
  if (!explodeState.active) return;
  ensureEntries();
  if (!explodeState.entries.length) {
    resetExplode({ restore: false });
    return;
  }
  const speed = (EXPLODE_SPEED / 10) * 3;
  if (Math.abs(explodeState.t - explodeState.target) > 0.001) {
    const sign = explodeState.target > explodeState.t ? 1 : -1;
    explodeState.t += sign * speed * dt;
    explodeState.t = Math.max(0, Math.min(1, explodeState.t));
  } else {
    explodeState.t = explodeState.target;
    if (explodeState.t === 0) explodeState.active = false;
  }

  const quaternion = new THREE.Quaternion();
  const euler = new THREE.Euler();
  explodeState.entries.forEach(entry => {
    const delay = entry.stagger * 0.25;
    const raw = Math.max(0, Math.min(1, (explodeState.t - delay) / (1 - delay)));
    const eased = raw < 0.5 ? 2 * raw * raw : 1 - Math.pow(-2 * raw + 2, 2) / 2;
    const spread = entry.modelRadius * (EXPLODE_DISTANCE / 50);
    entry.mesh.position.copy(entry.originalPosition).addScaledVector(entry.directionLocal, eased * spread);
    quaternion.setFromAxisAngle(entry.rotationAxis, eased * entry.rotationAngle);
    euler.setFromQuaternion(quaternion);
    entry.mesh.rotation.set(
      entry.originalRotation.x + euler.x,
      entry.originalRotation.y + euler.y,
      entry.originalRotation.z + euler.z,
    );
  });

  if (explodeState.t === 0 && explodeState.target === 0) {
    explodeState.entries = [];
    explodeState.meshCount = 0;
  }
}
