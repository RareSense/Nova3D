// Central mutable state for the Nova viewer. Single object reference, imported
// by every module. Modules read with `state.foo` and write with `state.foo = ...`.
//
// IMPORTANT: never destructure at module top level (`const { scene } = state`).
// Reassigned fields (scene, modelGroup, envMap, loadedMeshes, currentJoints,
// articulatedJoints, editModelOptions) would be captured as their boot-time
// `null`/empty values. Always access via `state.foo` so reads stay live.

export const MAX_UNDO = 30;

export const state = {
  // ── Scene ────────────────────────────────────────────────────────────────
  scene: null,
  camera: null,
  renderer: null,
  controls: null,
  transformControls: null,
  modelGroup: null,
  transformProxy: null,
  envMap: null,
  container: null,   // set in init() after DOMContentLoaded
  raycaster: null,   // initialised in main / init
  mouse: null,

  // ── Selection ────────────────────────────────────────────────────────────
  loadedMeshes: [],                    // [{ mesh, originalMaterial, name, geometry }]
  selectedMeshIndices: new Set(),
  lastSelectedMeshIndex: null,
  lastSelectionAction: null,

  // ── Display ──────────────────────────────────────────────────────────────
  autoRotateEnabled: true,
  currentMode: 'orbit',                // 'orbit' | 'translate' | 'rotate' | 'scale'
  displayState: { wireframe:false, flatShading:false, xray:false, boundingBox:false, normals:false },
  boxHelpers: [],
  normalHelpers: [],

  // ── Sculpt ───────────────────────────────────────────────────────────────
  sculptMode: false,
  sculptTool: 'grab',
  isSculpting: false,
  sculptHitPt: null,
  sculptTgtIdx: -1,

  // ── History (mutated in place) ───────────────────────────────────────────
  undoHistory: [],
  redoHistory: [],

  // ── AI edit ──────────────────────────────────────────────────────────────
  currentCodeArtifact: null,
  currentModelUrl: null,
  currentSourceModelUrl: '',
  currentModelArtifact: null,
  currentJointsArtifact: null,
  currentJoints: [],
  currentInstructionPrompt: '',
  currentSourceWorkflowId: '',
  activeEditRequestId: null,
  activeOperation: null,
  editModelOptions: [],
  editDefaultModelId: '',

  // ── Articulation ─────────────────────────────────────────────────────────
  articulatedJoints: [],
  selectedArticulatedJointName: '',
  articulatedObjects: {},               // map: jointName → THREE.Object3D
  jointSliderValues: {},
  jointDirectionMultipliers: {},
  jointDemoActive: true,                // legacy flag kept in sync with set size
  jointAutoPreviewEnabled: true,        // legacy flag kept in sync with set size
  jointDemoMode: 'all',                 // 'all' | 'one'
  jointDemoTime: 0,
  jointDemoLastFrame: 0,
  jointAutoPreviewSet: new Set(),       // Set<jointName>
  jointDemoPhases: {},                  // map: jointName → { time, lastFrame }

  // ── Session ──────────────────────────────────────────────────────────────
  viewerId: 'standalone-viewer',
  stateKey: 'standalone-viewer',
};

export function editorStorageKey() {
  return `nova3d-viewer-state:${state.stateKey || state.viewerId}`;
}

export function fsStorageKey() {
  return 'nova3d-fs:' + (state.stateKey || state.viewerId);
}
