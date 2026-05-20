// Nova viewer entry point. Loads ahead of <body> parse, so DOM-dependent
// work happens inside the DOMContentLoaded handler below.
//
// Responsibilities:
//   1. Wire cross-module callback hooks (these decouple modules that would
//      otherwise form import cycles around the snapshot/persistence layer).
//   2. Install the delegated action dispatcher and register every data-action.
//   3. Read URL query params and seed state.
//   4. Run scene.init() + the rest of the setup* calls in the correct order.
//   5. Restore from IndexedDB if we have a saved state for this stateKey;
//      otherwise load the URL-supplied `glb` parameter.

import { THREE } from '@nova/three-ext.js';
import { iconSvg } from '@nova/util.js';
import { state, fsStorageKey } from '@nova/state.js';
import { setupBgPresets, buildBgSwatches } from '@nova/bgPresets.js';
import { installActionDelegation, registerAction } from '@nova/ui/actions.js';
import {
  setSaveEditorState,
  tickJointDemo,
  applyJointTransforms,
} from '@nova/articulation.js';
import {
  popUndo, popRedo, pushUndoSnapshot, syncHistoryUi,
  setHistoryUiRefreshers, setHistorySaveEditorState,
} from '@nova/history.js';
import {
  saveEditorState, flushEditorState, restoreEditorState,
  setPersistenceSceneRefreshers,
} from '@nova/persistence.js';
import {
  setModelHooks, updateMeshStats,
  loadGLB, downloadCurrentGLB,
  deleteSelected, duplicateSelection, mirrorSelection,
  mergeSelected, flipNormals, centerOrigin, recalcNormals, separateByLooseParts,
  subdivideSelected, smoothSelected, decimateSelected, applyMirrorModifier,
  applyMaterialPreset, applyCustomMaterial,
} from '@nova/model.js';
import {
  setSelectionHooks,
  updateMeshList, updateHighlights,
  attachTransformToSelection, detachProxy,
  setupRaycasting, setupMeshButtons, setupTransformPanel,
  resetTransform,
} from '@nova/selection.js';
import {
  setSceneHooks, addFrameCallback,
  init as initScene, onResize, frameCameraToModel, toggleAutoRotate,
} from '@nova/scene.js';
import {
  toggleWireframe, toggleXray, toggleBoundingBox, toggleNormals, setExposure,
} from '@nova/ui/displayPanel.js';
import { setupFlyouts, setViewportMode, setupViewportMode, isFullUi } from '@nova/ui/flyouts.js';
import { setupKeyboard } from '@nova/ui/keyboard.js';
import { setupSculpting } from '@nova/sculpt.js';
import {
  setupEditBridge, renderEditModelSelector,
  requestRegeneratePart, requestAddPart, requestArticulation,
  showEditStatus,
} from '@nova/aiEdit.js';

// ── Cross-module callback wires ──────────────────────────────────────────────
// These hooks let modules that would otherwise form an import cycle stay
// strictly acyclic (e.g. articulation needs `saveEditorState`, but persistence
// already depends on history which depends on articulation — so we set the
// reference at boot rather than importing).
setSaveEditorState(saveEditorState);
setHistorySaveEditorState(saveEditorState);
setHistoryUiRefreshers({
  detachProxy: () => detachProxy(),
  refreshUi:   () => { updateMeshList(); updateMeshStats(); updateHighlights(); },
});
setPersistenceSceneRefreshers({
  onResize:      () => onResize(),
  reframeCamera: (group) => frameCameraToModel(group),
});
setModelHooks({
  refreshMeshUi:      () => { updateMeshList(); updateMeshStats(); },
  refreshHighlights:  () => updateHighlights(),
  detachProxy:        () => detachProxy(),
  frameCameraToModel: (group) => frameCameraToModel(group),
  showDownloadError:  (msg) => showEditStatus(msg, true),
});
setSelectionHooks({
  isFullUi: () => isFullUi(),
});
setSceneHooks({
  attachTransformToSelection: () => attachTransformToSelection(),
  detachProxy:                () => detachProxy(),
  pushUndoSnapshot:           (action) => pushUndoSnapshot(action),
});

// Articulation's per-frame work runs as a scene frame callback.
addFrameCallback(() => { tickJointDemo(); applyJointTransforms(); });

// State boot — anything that depends on DOM is deferred to DOMContentLoaded
// below. Three.js objects are safe to construct at module load.
state.raycaster = new THREE.Raycaster();
state.mouse     = new THREE.Vector2();
try { state.autoRotateEnabled = localStorage.getItem('nova3d_autoRotate') !== 'false'; } catch (_) {}

// ── Delegated action registry ────────────────────────────────────────────────
function registerAllActions() {
  registerAction('autorotate-toggle', () => toggleAutoRotate());
  registerAction('history-toggle',    () => {
    const col = document.getElementById('historyCol');
    if (col) col.classList.toggle('collapsed');
  });
  registerAction('undo',          () => popUndo());
  registerAction('redo',          () => popRedo());
  registerAction('download-glb',  () => downloadCurrentGLB());

  registerAction('display-wireframe', () => toggleWireframe());
  registerAction('display-xray',      () => toggleXray());
  registerAction('display-bbox',      () => toggleBoundingBox());
  registerAction('display-normals',   () => toggleNormals());
  registerAction('exposure',          (el) => setExposure(el.value));

  registerAction('transform-reset',    () => resetTransform());
  registerAction('mirror',             (el) => mirrorSelection(el.dataset.axis));
  registerAction('mesh-delete',        () => deleteSelected());
  registerAction('mesh-duplicate',     () => duplicateSelection());
  registerAction('mesh-merge',         () => mergeSelected());
  registerAction('mesh-separate',      () => separateByLooseParts());
  registerAction('mesh-flip-normals',  () => flipNormals());
  registerAction('mesh-center-origin', () => centerOrigin());
  registerAction('mesh-recalc-normals',() => recalcNormals());

  registerAction('material-preset', (el) => applyMaterialPreset(el.dataset.preset));
  registerAction('material-custom', () => applyCustomMaterial());

  registerAction('ai-remix',      () => requestRegeneratePart());
  registerAction('ai-grow',       () => requestAddPart());
  registerAction('ai-articulate', () => requestArticulation());
}

function renderSelectionIcons() {
  document.querySelectorAll('[data-icon]').forEach(el => { el.innerHTML = iconSvg(el.dataset.icon); });
}

// ── Bootstrap ────────────────────────────────────────────────────────────────
document.addEventListener('DOMContentLoaded', () => {
  state.container = document.getElementById('canvas-container');
  const appRoot = document.querySelector('.app');
  if (appRoot) installActionDelegation(appRoot);
  registerAllActions();
  setupBgPresets();
  initScene();
  renderSelectionIcons();
  setupKeyboard();
  setupRaycasting();
  setupMeshButtons();
  setupFlyouts();
  setupSculpting();
  setupViewportMode();
  setupEditBridge();
  syncHistoryUi();
  setupTransformPanel();
  buildBgSwatches();

  const params = new URLSearchParams(window.location.search);
  state.viewerId = params.get('viewerId') || state.viewerId;
  state.stateKey = params.get('stateKey') || params.get('glb') || state.viewerId;
  // Also check sessionStorage: if the iframe was reloaded by the browser
  // while it was in the fullscreen overlay, restore editor mode automatically.
  let startInEditor = params.get('mode') === 'editor';
  try { startInEditor = startInEditor || sessionStorage.getItem(fsStorageKey()) === '1'; } catch (_) {}
  setViewportMode(startInEditor);

  const artifactParam = params.get('codeArtifact');
  if (artifactParam) {
    try { state.currentCodeArtifact = JSON.parse(artifactParam); } catch (_) { state.currentCodeArtifact = null; }
  }
  const modelArtifactParam = params.get('modelArtifact');
  if (modelArtifactParam) {
    try { state.currentModelArtifact = JSON.parse(modelArtifactParam); } catch (_) { state.currentModelArtifact = null; }
  }
  const jointsArtifactParam = params.get('jointsArtifact');
  if (jointsArtifactParam) {
    try { state.currentJointsArtifact = JSON.parse(jointsArtifactParam); } catch (_) { state.currentJointsArtifact = null; }
  }
  const jointsParam = params.get('joints');
  if (jointsParam) {
    try {
      const parsed = JSON.parse(jointsParam);
      state.currentJoints = Array.isArray(parsed) ? parsed : [];
    } catch (_) {
      state.currentJoints = [];
    }
  }
  const modelOptionsParam = params.get('editModelOptions');
  if (modelOptionsParam) {
    try {
      const parsed = JSON.parse(modelOptionsParam);
      state.editModelOptions = Array.isArray(parsed)
        ? parsed.filter(option => option && option.id && option.label)
        : [];
    } catch (_) {
      state.editModelOptions = [];
    }
  }
  state.editDefaultModelId      = params.get('editDefaultModelId') || '';
  state.currentSourceModelUrl   = params.get('sourceModelUrl') || params.get('glb') || '';
  state.currentInstructionPrompt = params.get('instructionPrompt') || '';
  state.currentSourceWorkflowId = params.get('sourceWorkflowId') || '';
  renderEditModelSelector();

  const glbUrl = params.get('glb');
  const autoR  = params.get('autoRotate');
  if (autoR === 'false') {
    state.autoRotateEnabled = false;
    state.controls.autoRotate = false;
    const btn = document.getElementById('tbAutoRotate');
    if (btn) btn.classList.remove('active');
  }

  window.addEventListener('pagehide',     () => { void flushEditorState(); });
  window.addEventListener('beforeunload', () => { void flushEditorState(); });

  // restoreEditorState is async (IndexedDB); only load from the URL param
  // when no saved state exists for this model.
  restoreEditorState().then(restored => {
    if (!glbUrl || restored) return;
    if (state.container.clientWidth > 0 && state.container.clientHeight > 0) {
      loadGLB(glbUrl, { sourceModelUrl: state.currentSourceModelUrl });
    } else {
      const ro = new ResizeObserver((_, obs) => {
        if (state.container.clientWidth > 0 && state.container.clientHeight > 0) {
          obs.disconnect();
          loadGLB(glbUrl, { sourceModelUrl: state.currentSourceModelUrl });
        }
      });
      ro.observe(state.container);
    }
  });
});
