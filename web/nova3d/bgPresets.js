// Background preset registry, gradient builder, swatches DOM, and the two
// localStorage keys (`nova3d_bgPreset`, `nova3d_bgCustom`) that survive page
// reloads. Reads `state.scene` to set `scene.background`.

import { THREE } from '@nova/three-ext.js';
import { state } from '@nova/state.js';
import { normalizeTexture } from '@nova/util.js';
import { registerAction } from '@nova/ui/actions.js';

export const DEFAULT_BG_PRESET = 'white';

export const BG_PRESETS = {
  white:  { swatch:'#f8fafc', stops:['#ffffff','#f5f7fb','#e6ebf2'] },
  studio: { swatch:'#1a1a2e', stops:['#1a1a2e','#0f0f1a','#060610'] },
};

function _applyBgStops(stops, saveKey) {
  const cvs = document.createElement('canvas'); cvs.width = cvs.height = 512;
  const ctx = cvs.getContext('2d');
  const g = ctx.createRadialGradient(256,256,0,256,256,420);
  g.addColorStop(0,stops[0]); g.addColorStop(.6,stops[1]); g.addColorStop(1,stops[2]);
  ctx.fillStyle = g; ctx.fillRect(0,0,512,512);
  if (state.scene) state.scene.background = normalizeTexture(new THREE.CanvasTexture(cvs));
  if (saveKey) try { localStorage.setItem('nova3d_bgPreset', saveKey); } catch (e) {}
}

export function applyBgPreset(name) {
  const p = BG_PRESETS[name] || BG_PRESETS[DEFAULT_BG_PRESET];
  _applyBgStops(p.stops, name);
  document.querySelectorAll('.bg-swatch').forEach(el => el.classList.toggle('active', el.dataset.preset === name));
  const wheel = document.getElementById('bgColorWheel');
  if (wheel) wheel.classList.remove('active');
}

export function applyBgCustomColor(hex) {
  const r = parseInt(hex.slice(1,3),16), g = parseInt(hex.slice(3,5),16), b = parseInt(hex.slice(5,7),16);
  const lighten = (v,a) => Math.round(Math.min(255, v + (255-v) * a)).toString(16).padStart(2,'0');
  const darken  = (v,a) => Math.round(Math.max(0, v * a)).toString(16).padStart(2,'0');
  const light = '#' + lighten(r,.25) + lighten(g,.25) + lighten(b,.25);
  const dark  = '#' + darken(r,.75) + darken(g,.75) + darken(b,.75);
  _applyBgStops([light, hex, dark], null);
  try { localStorage.setItem('nova3d_bgCustom', hex); localStorage.removeItem('nova3d_bgPreset'); } catch (e) {}
  document.querySelectorAll('.bg-swatch').forEach(el => el.classList.remove('active'));
  const wheel = document.getElementById('bgColorWheel');
  if (wheel) { wheel.classList.add('active'); wheel.style.setProperty('--swatch', hex); }
}

export function buildBgSwatches() {
  const host = document.getElementById('bgSwatches'); if (!host) return;
  let savedPreset, savedCustom;
  try {
    savedPreset = localStorage.getItem('nova3d_bgPreset');
    savedCustom = localStorage.getItem('nova3d_bgCustom');
  } catch (e) {}
  const current = savedPreset || DEFAULT_BG_PRESET;

  host.innerHTML =
    Object.entries(BG_PRESETS).map(([name, p]) =>
      `<button class="bg-swatch${(!savedCustom && current === name) ? ' active' : ''}" data-preset="${name}" title="${name}" style="background:${p.swatch}" data-action="bg-preset"></button>`
    ).join('') +
    `<label class="bg-swatch bg-swatch-wheel${savedCustom ? ' active' : ''}" id="bgColorWheel" title="Custom colour"
       style="--swatch:${savedCustom || '#8b5cf6'}">
       <input type="color" value="${savedCustom || '#8b5cf6'}" data-input-action="bg-custom" style="opacity:0;position:absolute;width:0;height:0">
     </label>`;
}

export function setupBgPresets() {
  registerAction('bg-preset', (el) => applyBgPreset(el.dataset.preset));
  registerAction('bg-custom', (el) => applyBgCustomColor(el.value));
}
