// Scene/camera/renderer/orbit/transform-controls ownership, lighting + HDRI
// environment, the RAF animate loop with a frame-callback registry, resize
// handling, camera framing, mode switching (orbit/translate/rotate/scale),
// auto-rotate toggle.
//
// Cross-module hooks (set by inline boot in PR 11):
//   - setSceneHooks({
//       attachTransformToSelection, detachProxy, pushUndoSnapshot,
//       setupToolbarExtras, sculptOnEsc, closeFlyouts,
//     })
//   The hooks decouple scene from selection.js and aiEdit/ui/flyouts that
//   haven't been extracted yet (PR 12 finishes those).
//
// Frame-callback registry: any module that needs per-frame work registers via
// `addFrameCallback(fn)`. Callbacks are wrapped in try/catch so a buggy
// consumer can't kill rendering. `controls.update()` and `renderer.render(...)`
// always run last; they are NOT frame callbacks.

import { THREE, OrbitControls, TransformControls, RGBELoader } from '@nova/three-ext.js';
import { state } from '@nova/state.js';
import { setEnvironmentMap } from '@nova/materials.js';
import { applyBgPreset, applyBgCustomColor, DEFAULT_BG_PRESET } from '@nova/bgPresets.js';

export const DEFAULT_EXPOSURE = 0.5;

let _attachTransformToSelection = () => {};
let _detachProxy = () => {};
let _pushUndoSnapshot = () => {};

export function setSceneHooks({ attachTransformToSelection, detachProxy, pushUndoSnapshot } = {}) {
  if (typeof attachTransformToSelection === 'function') _attachTransformToSelection = attachTransformToSelection;
  if (typeof detachProxy === 'function')                 _detachProxy                = detachProxy;
  if (typeof pushUndoSnapshot === 'function')            _pushUndoSnapshot           = pushUndoSnapshot;
}

// ── Frame-callback registry ──────────────────────────────────────────────────
const frameCallbacks = new Set();

export function addFrameCallback(fn) {
  if (typeof fn === 'function') frameCallbacks.add(fn);
}

export function removeFrameCallback(fn) {
  frameCallbacks.delete(fn);
}

// ── Camera framing ───────────────────────────────────────────────────────────
export function frameCameraToModel(model, fill = 0.8) {
  const box = new THREE.Box3().setFromObject(model);
  if (box.isEmpty()) return;
  const sphere = new THREE.Sphere(); box.getBoundingSphere(sphere);
  const fovRad = state.camera.fov * Math.PI / 180;
  const vDist = sphere.radius / Math.sin(fovRad/2);
  const hDist = sphere.radius / Math.sin(Math.atan(Math.tan(fovRad/2) * state.camera.aspect));
  const dist  = Math.max(vDist, hDist) / fill;
  const dir   = new THREE.Vector3(0, .18, 1).normalize();
  state.camera.position.copy(sphere.center).addScaledVector(dir, dist);
  state.camera.near = Math.max(0.01, dist * .001);
  state.camera.far  = Math.max(100, dist * 50);
  state.camera.updateProjectionMatrix();
  state.controls.target.copy(sphere.center);
  state.controls.update();
}

// ── Lighting + HDRI ──────────────────────────────────────────────────────────
function buildProceduralEnv() {
  const pmrem = new THREE.PMREMGenerator(state.renderer); pmrem.compileEquirectangularShader();
  const es = new THREE.Scene(); es.background = new THREE.Color(0x111111);
  const wm = new THREE.MeshBasicMaterial({ color: 0xffffff, side: THREE.DoubleSide, toneMapped: false });
  const top = new THREE.Mesh(new THREE.PlaneGeometry(10, 3), wm); top.position.set(0, 5, 0); top.rotation.x = Math.PI/2; es.add(top);
  const front = new THREE.Mesh(new THREE.PlaneGeometry(8, 2), wm); front.position.set(0, 2, -6); es.add(front);
  setEnvironmentMap(pmrem.fromScene(es, .02).texture);
  pmrem.dispose();
}

function setupEnvironment() {
  const L1 = new THREE.DirectionalLight(0xffffff, 2);   L1.position.set(3, 5, 3);   state.scene.add(L1);
  const L2 = new THREE.DirectionalLight(0xffffff, 1);   L2.position.set(-3, 2, -3); state.scene.add(L2);
  state.scene.add(new THREE.HemisphereLight(0xffffff, 0x444444, 1.5));
  const sL = new THREE.DirectionalLight(0xffffff, 0.5); sL.position.set(0, 10, 0);
  sL.castShadow = true; sL.shadow.mapSize.set(1024, 1024);
  sL.shadow.camera.near = .1; sL.shadow.camera.far = 20;
  sL.shadow.camera.left = sL.shadow.camera.bottom = -3;
  sL.shadow.camera.right = sL.shadow.camera.top = 3;
  sL.shadow.bias = -0.003; sL.shadow.radius = 8; state.scene.add(sL);
  const sP = new THREE.Mesh(new THREE.PlaneGeometry(10, 10), new THREE.ShadowMaterial({ opacity: .06 }));
  sP.rotation.x = -Math.PI/2; sP.position.y = -1.3; sP.receiveShadow = true; state.scene.add(sP);

  new RGBELoader().load(
    'https://dl.polyhaven.org/file/ph-assets/HDRIs/hdr/1k/studio_small_08_1k.hdr',
    tex => {
      tex.mapping = THREE.EquirectangularReflectionMapping;
      const pmrem = new THREE.PMREMGenerator(state.renderer);
      const processed = pmrem.fromEquirectangular(tex).texture;
      tex.dispose();
      pmrem.dispose();
      setEnvironmentMap(processed);
    },
    undefined,
    () => buildProceduralEnv()
  );
}

// ── init / animate / resize ──────────────────────────────────────────────────
export function init() {
  state.scene = new THREE.Scene();
  let bgCustom; try { bgCustom = localStorage.getItem('nova3d_bgCustom'); } catch (e) {}
  if (bgCustom) {
    // restore custom colour (runs before buildBgSwatches so wheel picks it up)
    let bg; try { bg = localStorage.getItem('nova3d_bgPreset') || DEFAULT_BG_PRESET; } catch (e) { bg = DEFAULT_BG_PRESET; }
    applyBgPreset(bg);
    applyBgCustomColor(bgCustom);
  } else {
    let bg; try { bg = localStorage.getItem('nova3d_bgPreset') || DEFAULT_BG_PRESET; } catch (e) { bg = DEFAULT_BG_PRESET; }
    applyBgPreset(bg);
  }

  state.camera = new THREE.PerspectiveCamera(30, state.container.clientWidth / state.container.clientHeight, 0.1, 100);
  state.camera.position.set(0, 2, 5);

  state.renderer = new THREE.WebGLRenderer({ antialias: true, preserveDrawingBuffer: true, logarithmicDepthBuffer: true });
  state.renderer.setSize(state.container.clientWidth, state.container.clientHeight);
  state.renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
  state.renderer.toneMapping         = THREE.ACESFilmicToneMapping;
  state.renderer.toneMappingExposure = DEFAULT_EXPOSURE;
  state.renderer.outputColorSpace    = THREE.SRGBColorSpace;
  state.renderer.shadowMap.enabled   = true;
  state.renderer.shadowMap.type      = THREE.PCFSoftShadowMap;
  state.container.appendChild(state.renderer.domElement);

  state.controls = new OrbitControls(state.camera, state.renderer.domElement);
  state.controls.enableDamping   = true;
  state.controls.dampingFactor   = 0.05;
  state.controls.autoRotate      = state.autoRotateEnabled;
  state.controls.autoRotateSpeed = 1.0;
  state.controls.target.set(0, 0, 0);
  state.controls.minDistance = 2;
  state.controls.maxDistance = 12;

  state.transformControls = new TransformControls(state.camera, state.renderer.domElement);
  state.transformControls.setSize(0.8);
  state.transformControls.addEventListener('dragging-changed', e => { state.controls.enabled = !e.value; });
  state.transformControls.addEventListener('mouseDown', () => _pushUndoSnapshot('transform'));
  state.transformControls.addEventListener('objectChange', () => {});
  state.scene.add(state.transformControls);

  state.modelGroup     = new THREE.Group(); state.scene.add(state.modelGroup);
  state.transformProxy = new THREE.Group(); state.scene.add(state.transformProxy);

  setupEnvironment();
  setupToolbar();

  // ResizeObserver handles both the initial iframe sizing by Flutter
  // (which fires before window.resize) and all subsequent resizes.
  new ResizeObserver(() => onResize()).observe(state.container);
  animate();
}

function animate() {
  requestAnimationFrame(animate);
  for (const fn of frameCallbacks) {
    try { fn(); }
    catch (e) { console.warn('[nova3d] frame callback threw:', e); }
  }
  state.controls.update();
  state.renderer.render(state.scene, state.camera);
}

export function onResize() {
  const w = state.container.clientWidth, h = state.container.clientHeight;
  if (!w || !h) return;
  state.camera.aspect = w / h;
  state.camera.updateProjectionMatrix();
  state.renderer.setSize(w, h);
}

// ── Toolbar + mode switching ─────────────────────────────────────────────────
export function setupToolbar() {
  document.getElementById('tbOrbit').onclick  = () => setMode('orbit');
  document.getElementById('tbMove').onclick   = () => setMode('translate');
  document.getElementById('tbRotate').onclick = () => setMode('rotate');
  document.getElementById('tbScale').onclick  = () => setMode('scale');
  const arBtn = document.getElementById('tbAutoRotate');
  if (arBtn) { arBtn.classList.toggle('active', state.autoRotateEnabled); arBtn.title = state.autoRotateEnabled ? 'Auto-rotate: ON' : 'Auto-rotate: OFF'; }
}

export function setMode(mode) {
  if (state.sculptMode && mode !== 'orbit') return;
  state.currentMode = mode;
  document.querySelectorAll('.vp-btn').forEach(b => b.classList.remove('active'));
  if (mode === 'orbit') {
    document.getElementById('tbOrbit').classList.add('active');
    _detachProxy(); state.transformControls.detach();
  } else {
    const map = { translate: 'tbMove', rotate: 'tbRotate', scale: 'tbScale' };
    document.getElementById(map[mode]).classList.add('active');
    state.transformControls.setMode(mode);
    _attachTransformToSelection();
  }
}

export function toggleAutoRotate() {
  state.autoRotateEnabled = !state.autoRotateEnabled;
  state.controls.autoRotate = state.autoRotateEnabled;
  try { localStorage.setItem('nova3d_autoRotate', String(state.autoRotateEnabled)); } catch (e) {}
  const btn = document.getElementById('tbAutoRotate');
  if (btn) { btn.classList.toggle('active', state.autoRotateEnabled); btn.title = 'Auto-rotate'; }
}
