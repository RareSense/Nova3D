// AI edit workflow bridge: postMessage requests to the parent Flutter app,
// status display per operation, edit-model selector, and the result handler
// that swaps the model in via loadGLB.
//
// Three operations are exposed: regenerate_3d_part, add_3d_part, and
// articulate_3d_model. Each uses its own status element + button + textarea
// inside its flyout. The postMessage payload field names are frozen — Dart on
// the other side decodes by exact name.

import { state } from '@nova/state.js';
import { bindArticulatedJoints, stopJointAutoPreviewForEdit } from '@nova/articulation.js';
import { pushUndoSnapshot } from '@nova/history.js';
import { loadGLB } from '@nova/model.js';
import { closeFlyouts } from '@nova/ui/flyouts.js';
import { track } from '@nova/analytics.js';

export function selectedPartType() {
  if (!state.selectedMeshIndices.size) return 'selected part';
  const names = [...state.selectedMeshIndices]
    .map(i => state.loadedMeshes[i]?.name)
    .filter(Boolean)
    .slice(0, 4);
  return names.length ? names.join(', ') : 'selected part';
}

export function selectedMeshNames() {
  return [...state.selectedMeshIndices]
    .map(i => state.loadedMeshes[i]?.name)
    .filter(Boolean)
    .slice(0, 30);
}

function setAiBusy(busy) {
  if (!busy) state.activeOperation = null;
  if (busy) stopJointAutoPreviewForEdit(state.activeOperation || 'ai-edit');
  ['regenBtn','addPartBtn','articulateBtn','regenPrompt','addPartPrompt','articulationPrompt','editModelSelect','editModelSelectGrow','editModelSelectArticulate'].forEach(id => {
    const el = document.getElementById(id);
    if (el) el.disabled = busy;
  });
  document.querySelector('.edit-toolbar')?.classList.toggle('ai-busy', busy);
}

export function showEditStatus(message, isError = false) {
  const el = document.getElementById('aiEditStatus');
  if (!el) return;
  el.textContent = message;
  el.classList.add('active');
  el.classList.toggle('error', isError);
  el.classList.toggle('busy', !isError && Boolean(state.activeEditRequestId));
}

function editStatusId(operation) {
  if (operation === 'add_3d_part') return 'addPartStatus';
  if (operation === 'articulate_3d_model') return 'articulationStatus';
  return 'regenStatus';
}

function editButtonId(operation) {
  if (operation === 'add_3d_part') return 'addPartBtn';
  if (operation === 'articulate_3d_model') return 'articulateBtn';
  return 'regenBtn';
}

function showSectionStatus(operation, message, isError = false) {
  const el = document.getElementById(editStatusId(operation));
  if (!el) return;
  el.textContent = message;
  el.classList.add('active');
  el.classList.toggle('error', isError);
  el.classList.toggle('busy', !isError && Boolean(state.activeEditRequestId));
  try { el.scrollIntoView({ block: 'nearest' }); } catch (_) {}
}

function editStatusMessage(message, workflowId) {
  const id = String(workflowId || '').trim();
  return id ? `${message}\nRequest ID: ${id}` : message;
}

function flashEditButton(operation, message) {
  const btn = document.getElementById(editButtonId(operation));
  if (!btn) return;
  const previous = btn.dataset.idleLabel || btn.textContent;
  btn.textContent = message;
  window.setTimeout(() => {
    if (!state.activeEditRequestId) btn.textContent = previous;
  }, 1500);
}

// ── Edit-model selector (API-key driven) ─────────────────────────────────────
function storageValue(name) {
  try {
    return localStorage.getItem(name) ?? localStorage.getItem(`flutter.${name}`);
  } catch (_) {
    return null;
  }
}

function storageBool(name) {
  const value = storageValue(name);
  return value === 'true' || value === true;
}

function storageHasKey(provider) {
  const key = storageValue(`nova3d_api_key_${provider}`);
  return typeof key === 'string' && key.trim().length > 0;
}

function editModelOptionsFromStorage() {
  const options = [];
  if (storageBool('nova3d_api_key_valid_anthropic') && storageHasKey('anthropic')) {
    options.push(
      { id: 'anthropic_claude_sonnet',       label: 'Claude Sonnet 4.6 (Anthropic key)', provider: 'Anthropic' },
      { id: 'anthropic_claude_opus_4_8',     label: 'Claude Opus 4.8 (Anthropic key)',   provider: 'Anthropic' },
    );
  }
  if (storageBool('nova3d_api_key_valid_openai') && storageHasKey('openai')) {
    options.push({ id: 'openai_gpt55', label: 'GPT-5.5 (OpenAI key)', provider: 'OpenAI' });
  }
  if (storageBool('nova3d_api_key_valid_openrouter') && storageHasKey('openrouter')) {
    options.push(
      { id: 'openrouter_gpt55',                label: 'GPT-5.5 (OpenRouter key)',                  provider: 'OpenRouter' },
      { id: 'openrouter_gemini',               label: 'Gemini 3.1 Pro Preview (OpenRouter key)',    provider: 'OpenRouter' },
      { id: 'openrouter_claude_sonnet',        label: 'Claude Sonnet 4.6 (OpenRouter key)',         provider: 'OpenRouter' },
      { id: 'openrouter_claude_opus',          label: 'Claude Opus 4.8 (OpenRouter key)',           provider: 'OpenRouter' },
    );
  }
  if (storageBool('nova3d_api_key_valid_gemini') && storageHasKey('gemini')) {
    options.push({ id: 'gemini_gemini', label: 'Gemini 3.1 Pro Preview (Gemini key)', provider: 'Gemini' });
  }
  return options;
}

function selectedEditModelId() {
  const articulateOpen = document.getElementById('flyArticulate')?.classList.contains('open');
  const growOpen       = document.getElementById('flyAiGrow')?.classList.contains('open');
  const id = articulateOpen ? 'editModelSelectArticulate' : (growOpen ? 'editModelSelectGrow' : 'editModelSelect');
  return document.getElementById(id)?.value || '';
}

function normalizeAssetVersion(version) {
  if (!version || typeof version !== 'object') return null;
  const modelUrl = String(version.model_url || version.modelUrl || '').trim();
  const workflowId = String(version.workflow_id || version.workflowId || '').trim();
  if (!modelUrl || !workflowId) return null;
  return {
    messageId: String(version.message_id || version.messageId || workflowId),
    label: String(version.label || 'Model version'),
    operation: String(version.operation || 'generation'),
    modelUrl,
    sourceModelUrl: String(version.source_model_url || version.sourceModelUrl || modelUrl),
    workflowId,
    modelArtifact: version.model_artifact || version.modelArtifact || null,
    codeArtifact: version.code_artifact || version.codeArtifact || null,
    jointsArtifact: version.joints_artifact || version.jointsArtifact || null,
    joints: Array.isArray(version.joints) ? version.joints : [],
  };
}

function setAssetVersions(versions) {
  const parsed = Array.isArray(versions)
    ? versions.map(normalizeAssetVersion).filter(Boolean)
    : [];
  if (!parsed.length) return;
  state.aiVersions = parsed;
  const currentWorkflow = String(state.currentSourceWorkflowId || '');
  const currentModel = String(state.currentSourceModelUrl || state.currentModelUrl || '');
  const idx = parsed.findIndex(version =>
    (currentWorkflow && version.workflowId === currentWorkflow) ||
    (currentModel && (version.modelUrl === currentModel || version.sourceModelUrl === currentModel))
  );
  state.aiVersionIndex = idx >= 0 ? idx : parsed.length - 1;
}

function appendAssetVersion(version) {
  const parsed = normalizeAssetVersion(version);
  if (!parsed) return;
  const existingIdx = state.aiVersions.findIndex(item => item.workflowId === parsed.workflowId);
  if (existingIdx >= 0) {
    state.aiVersions[existingIdx] = parsed;
    state.aiVersionIndex = existingIdx;
    return;
  }
  state.aiVersions.push(parsed);
  state.aiVersionIndex = state.aiVersions.length - 1;
}

export function renderEditModelSelector() {
  if (!state.editModelOptions.length) state.editModelOptions = editModelOptionsFromStorage();
  ['editModelSelect','editModelSelectGrow','editModelSelectArticulate'].forEach(selectId => {
    const select = document.getElementById(selectId);
    if (!select) return;
    const previous = select.value || state.editDefaultModelId;
    select.innerHTML = '';
    state.editModelOptions.forEach(option => {
      const opt = document.createElement('option');
      opt.value = option.id || '';
      opt.textContent = option.label || option.provider || '';
      select.appendChild(opt);
    });
    const next = state.editModelOptions.some(option => option.id === previous)
      ? previous
      : (state.editModelOptions.some(option => option.id === state.editDefaultModelId)
          ? state.editDefaultModelId
          : state.editModelOptions[0]?.id);
    select.value = next || '';
    select.disabled = Boolean(state.activeEditRequestId);
  });
}

let latestEditConfig = null;

export function applyEditConfig(data) {
  if (!data || typeof data !== 'object') return;
  latestEditConfig = data;
  if (data.modelArtifact !== undefined) state.currentModelArtifact = data.modelArtifact || null;
  if (data.codeArtifact !== undefined) state.currentCodeArtifact = data.codeArtifact || null;
  if (data.jointsArtifact !== undefined) state.currentJointsArtifact = data.jointsArtifact || null;
  if (Array.isArray(data.joints)) {
    state.currentJoints = data.joints;
    bindArticulatedJoints(state.currentJoints, { preserveValues: true });
  }
  if (data.sourceModelUrl !== undefined) {
    state.currentSourceModelUrl = String(data.sourceModelUrl || '');
    // Parent-resolved source is authoritative and arrives outside the iframe
    // URL so signed query strings never enter replay/history/referrer data.
    if (state.currentSourceModelUrl) state.currentModelUrl = state.currentSourceModelUrl;
  }
  if (data.instructionPrompt !== undefined) state.currentInstructionPrompt = String(data.instructionPrompt || '');
  if (data.sourceWorkflowId !== undefined) state.currentSourceWorkflowId = String(data.sourceWorkflowId || '');
  if (Array.isArray(data.assetVersions)) setAssetVersions(data.assetVersions);
  if (Array.isArray(data.editModelOptions)) {
    state.editModelOptions = data.editModelOptions.filter(option => option && option.id && option.label);
  }
  if (data.editDefaultModelId !== undefined) state.editDefaultModelId = String(data.editDefaultModelId || '');
  renderEditModelSelector();
}

export function reapplyLatestEditConfig() {
  if (latestEditConfig) applyEditConfig(latestEditConfig);
}

// ── Request flow ─────────────────────────────────────────────────────────────
function requestAiEdit(operation, description, partType = '') {
  const clean = description.trim();
  const isArticulation = operation === 'articulate_3d_model';
  const sourceModelUrl = state.currentSourceModelUrl || state.currentModelUrl || '';
  const hasServerReadableModel = state.currentModelArtifact || (sourceModelUrl && !sourceModelUrl.startsWith('blob:'));
  if (!clean && !isArticulation) {
    showSectionStatus(operation, 'Describe the edit first.', true);
    flashEditButton(operation, 'Needs description');
    return;
  }
  if (!state.currentCodeArtifact && !state.currentSourceWorkflowId) {
    showSectionStatus(operation, 'This model has no code artifact. Generate it again before AI editing.', true);
    flashEditButton(operation, 'No source code');
    return;
  }
  if (isArticulation && !hasServerReadableModel) {
    showSectionStatus(operation, 'This model has no source GLB artifact. Generate or edit it again before articulating.', true);
    flashEditButton(operation, 'No model source');
    return;
  }
  const modelOptionId = selectedEditModelId();
  if (!modelOptionId) {
    showSectionStatus(operation, 'Add an OpenRouter, OpenAI, Anthropic, or Gemini key in Settings before using AI edits.', true);
    flashEditButton(operation, 'Needs API key');
    return;
  }
  if (state.activeEditRequestId) return;
  state.activeEditRequestId = `edit-${Date.now()}-${Math.random().toString(16).slice(2)}`;
  state.activeOperation = operation;
  setAiBusy(true);
  const activeButton = document.getElementById(editButtonId(operation));
  if (activeButton) {
    activeButton.dataset.idleLabel = activeButton.textContent;
    activeButton.textContent = 'Starting...';
  }
  showSectionStatus(operation, operation === 'add_3d_part'
    ? 'Starting add-part edit...'
    : (isArticulation ? 'Starting articulation...' : 'Starting selected-part regeneration...'));
  track('ai_edit_requested', {
    operation,
    description: clean,
    description_length: clean.length,
    selected_mesh_count: selectedMeshNames().length,
    selected_mesh_names: selectedMeshNames(),
    model_option_id: modelOptionId,
    part_count: state.loadedMeshes.length,
  });
  state.activeEditStartedAt = Date.now();
  window.parent?.postMessage({
    type: 'nova3d-edit-request',
    viewerId: state.viewerId,
    requestId: state.activeEditRequestId,
    operation,
    description: clean,
    partType,
    codeArtifact: state.currentCodeArtifact,
    modelArtifact: state.currentModelArtifact,
    sourceModelUrl: sourceModelUrl.startsWith('blob:') ? '' : sourceModelUrl,
    instructionPrompt: state.currentInstructionPrompt,
    selectedMeshes: selectedMeshNames(),
    sourceWorkflowId: state.currentSourceWorkflowId,
    modelOptionId,
  }, window.location.origin);
  const sentRequestId = state.activeEditRequestId;
  window.setTimeout(() => {
    if (state.activeEditRequestId === sentRequestId) {
      showSectionStatus(operation, 'Sent edit request to Nova3D. Waiting for workflow status...');
    }
  }, 1200);
}

export function requestRegeneratePart() {
  requestAiEdit(
    'regenerate_3d_part',
    document.getElementById('regenPrompt')?.value || '',
    selectedPartType()
  );
}

export function requestAddPart() {
  requestAiEdit('add_3d_part', document.getElementById('addPartPrompt')?.value || '');
}

export function requestArticulation() {
  requestAiEdit('articulate_3d_model', document.getElementById('articulationPrompt')?.value || '');
}

// ── Result handler (parent → viewer) ─────────────────────────────────────────
export function setupEditBridge() {
  window.addEventListener('message', event => {
    if (event.origin !== window.location.origin || event.source !== window.parent) return;
    const data = event.data || {};
    if (data.type === 'nova3d-edit-config') {
      applyEditConfig(data);
      return;
    }
    if (data.type !== 'nova3d-edit-result') return;
    if (data.requestId !== state.activeEditRequestId) return;
    const op = state.activeOperation || 'regenerate_3d_part';
    if (data.status === 'running') {
      showSectionStatus(op, editStatusMessage(data.message || 'Editing model...', data.workflowId));
      return;
    }
    setAiBusy(false);
    state.activeEditRequestId = null;
    state.activeOperation = null;
    ['regenBtn','addPartBtn','articulateBtn'].forEach(id => {
      const el = document.getElementById(id);
      if (el?.dataset.idleLabel) {
        el.textContent = el.dataset.idleLabel;
        delete el.dataset.idleLabel;
      }
    });
    const editDurationMs = state.activeEditStartedAt
      ? Date.now() - state.activeEditStartedAt
      : null;
    if (data.status !== 'completed') {
      track('ai_edit_failed', {
        operation: op,
        workflow_id: data.workflowId,
        error_message: data.message || 'Edit failed.',
        duration_ms: editDurationMs,
      });
      showSectionStatus(op, editStatusMessage(data.message || 'Edit failed.', data.workflowId), true);
      return;
    }
    if (!data.modelUrl || !data.codeArtifact) {
      track('ai_edit_failed', {
        operation: op,
        workflow_id: data.workflowId,
        error_message: 'missing_model_artifact',
        duration_ms: editDurationMs,
      });
      showSectionStatus(op, editStatusMessage('Edit finished but did not return a usable model artifact.', data.workflowId), true);
      return;
    }
    track('ai_edit_succeeded', {
      operation: op,
      workflow_id: data.workflowId,
      duration_ms: editDurationMs,
      joint_count: Array.isArray(data.joints) ? data.joints.length : 0,
    });
    pushUndoSnapshot(op);
    appendAssetVersion({
      messageId: `edit-${data.workflowId || Date.now()}`,
      label: op === 'articulate_3d_model' ? 'Articulated model' : (op === 'add_3d_part' ? 'Added part' : 'Regenerated selected part'),
      operation: op,
      modelUrl: data.modelUrl,
      sourceModelUrl: data.sourceModelUrl || data.modelUrl,
      workflowId: data.workflowId,
      modelArtifact: data.modelArtifact || null,
      codeArtifact: data.codeArtifact || null,
      jointsArtifact: data.jointsArtifact || null,
      joints: Array.isArray(data.joints) ? data.joints : [],
    });
    state.currentCodeArtifact = data.codeArtifact;
    state.currentModelArtifact = data.modelArtifact || null;
    state.currentSourceModelUrl = String(data.sourceModelUrl || data.modelUrl || '');
    state.currentJointsArtifact = data.jointsArtifact || null;
    state.currentJoints = Array.isArray(data.joints) ? data.joints : [];
    if (data.workflowId) state.currentSourceWorkflowId = String(data.workflowId);
    showSectionStatus(op, editStatusMessage(op === 'articulate_3d_model' ? 'Articulation complete.' : 'Edit complete.', data.workflowId));
    if (op === 'articulate_3d_model') {
      window.setTimeout(closeFlyouts, 700);
    }
    loadGLB(data.modelUrl, {
      recordHistory: false,
      sourceModelUrl: state.currentSourceModelUrl,
      startJointDemo: op === 'articulate_3d_model',
    });
  });
}
