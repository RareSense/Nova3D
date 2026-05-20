// Cross-cutting pure helpers. No DOM, no module state — safe to import anywhere.

import { THREE } from '@nova/three-ext.js';

export function structuredCloneSafe(value) {
  if (value == null) return value;
  try {
    if (typeof structuredClone === 'function') return structuredClone(value);
  } catch (_) {}
  try { return JSON.parse(JSON.stringify(value)); } catch (_) { return value; }
}

export function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, ch => ({ '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;' }[ch]));
}

export function formatActionLabel(action) {
  return String(action || 'edit').replace(/[-_]/g, ' ').replace(/\b\w/g, c => c.toUpperCase());
}

export function vecToData(v) {
  return v ? [v.x || 0, v.y || 0, v.z || 0] : [0, 0, 0];
}

export function vecFromData(data, fallback = 0) {
  return new THREE.Vector3(
    Number(data?.[0] ?? fallback),
    Number(data?.[1] ?? fallback),
    Number(data?.[2] ?? fallback),
  );
}

export function eulerToData(e) {
  return e ? [e.x || 0, e.y || 0, e.z || 0, e.order || 'XYZ'] : [0, 0, 0, 'XYZ'];
}

export function eulerFromData(data) {
  return new THREE.Euler(
    Number(data?.[0] ?? 0),
    Number(data?.[1] ?? 0),
    Number(data?.[2] ?? 0),
    data?.[3] || 'XYZ',
  );
}

const ICON_ATTRS = 'viewBox="0 0 24 24" fill="none" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"';
const ICON_PATHS = {
  'eye':         '<path d="M2 12s3.5-6 10-6 10 6 10 6-3.5 6-10 6-10-6-10-6Z"/><circle cx="12" cy="12" r="3"/>',
  'eye-off':     '<path d="m3 3 18 18"/><path d="M10.6 10.6a3 3 0 0 0 3.8 3.8"/><path d="M9.9 5.2A10.8 10.8 0 0 1 12 5c6.5 0 10 7 10 7a18.2 18.2 0 0 1-2.7 3.6"/><path d="M6.6 6.6C3.6 8.7 2 12 2 12s3.5 7 10 7c1.3 0 2.5-.2 3.6-.6"/>',
  'isolate':     '<path d="M4 7V4h3"/><path d="M17 4h3v3"/><path d="M20 17v3h-3"/><path d="M7 20H4v-3"/><rect x="9" y="9" width="6" height="6" rx="1"/>',
  'show-all':    '<path d="M2 12s3.5-6 10-6 10 6 10 6-3.5 6-10 6-10-6-10-6Z"/><circle cx="12" cy="12" r="3"/><path d="M4 4h4"/><path d="M4 4v4"/><path d="M20 20h-4"/><path d="M20 20v-4"/>',
  'select-all':  '<rect x="4" y="4" width="16" height="16" rx="2"/><path d="M8 12h8"/><path d="M12 8v8"/>',
  'clear':       '<rect x="4" y="4" width="16" height="16" rx="2"/><path d="m9 9 6 6"/><path d="m15 9-6 6"/>',
  'invert':      '<path d="M7 7h10v10H7z"/><path d="M4 4h6"/><path d="M4 4v6"/><path d="M20 20h-6"/><path d="M20 20v-6"/>',
};

export function iconSvg(name) {
  return `<svg ${ICON_ATTRS}>${ICON_PATHS[name] || ''}</svg>`;
}

export function jointDisplayName(joint) {
  const raw = joint.child_mesh || joint.description || joint.name || 'joint';
  return String(raw).replace(/^joint_/, '').replace(/_/g, ' ');
}

export function jointSafeName(joint) {
  return String(joint.name || '').replace(/[^a-zA-Z0-9]/g, '_');
}

export function jointUnit(joint) {
  return joint.kind === 'rotation' ? 'deg' : 'm';
}

export function jointPrecision(joint) {
  return joint.kind === 'rotation' ? 1 : 3;
}

export function normalizeTexture(texture, colorSpace = THREE.SRGBColorSpace) {
  if (texture && 'colorSpace' in texture) texture.colorSpace = colorSpace;
  return texture;
}
