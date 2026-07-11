// Nova3D public showcase gallery.
//
// GRID: a scrollable masonry of LIVE 3D tiles kept smooth at any catalog size by
// one shared WebGLRenderer drawing every visible tile via the scissor technique
// (no per-tile context), with virtualization (only near-viewport tiles load; GPU
// memory capped by disposing far ones).
//
// DETAIL (click a tile): embeds the REAL editor (nova3d_viewer.html) in showcase
// mode — so wireframe/x-ray/normals, explode/collapse, part list + highlight,
// transform and download are the editor's own working code, not a reimplementation.
// CODE and INPUTS are shown as sibling tabs. Read-only: it only fetches the public
// manifest and never writes anything.

import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';
import { colorizeIfUncolored } from '../nova3d/showcase_colorize.js';

const MAX_LOADED = 28;        // cap simultaneously-loaded tile models (GPU memory)
const NEAR_MARGIN = '900px';  // preload/keep models this far outside viewport
const DRAG_THRESHOLD = 6;     // px before a press counts as a drag (else = click)

const loader = new GLTFLoader();
const scrollEl = document.getElementById('scroll');
const gridEl = document.getElementById('grid');
const statusEl = document.getElementById('status');
const countEl = document.getElementById('count');

// ── Shared renderer + environment ────────────────────────────────────────────
const canvas = document.getElementById('stageCanvas');
const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true });
renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
renderer.setClearColor(0x000000, 0);
renderer.autoClear = false;
renderer.outputColorSpace = THREE.SRGBColorSpace;

const pmrem = new THREE.PMREMGenerator(renderer);
const ENV = pmrem.fromScene(new RoomEnvironment(), 0.04).texture;

function sizeRenderer() { renderer.setSize(window.innerWidth, window.innerHeight, false); }
sizeRenderer();
window.addEventListener('resize', sizeRenderer);

// ── Tiles ────────────────────────────────────────────────────────────────────
const cards = [];

function buildScene() {
  const scene = new THREE.Scene();
  scene.environment = ENV;
  const key = new THREE.DirectionalLight(0xffffff, 1.4);
  key.position.set(2, 3, 2);
  scene.add(key);
  scene.add(new THREE.HemisphereLight(0xffffff, 0x554e77, 0.5));
  return scene;
}

function makeCamera() {
  const cam = new THREE.PerspectiveCamera(32, 1, 0.01, 100);
  cam.position.set(0, 0, 3);
  return cam;
}

// Centre the model at the origin, normalise its size, and wrap it in a pivot.
// The pivot is what we scale and rotate, so rotation orbits the true geometric
// centre. Rotating the model node directly (with an unscaled position offset on
// the same node) left off-centre models — e.g. "The Impossible Machine", whose
// bounding box sits ~16 units above origin — scaled out of frame → blank tile.
// Returns the pivot to add to the scene and spin.
function fitModel(gltfScene, camera) {
  gltfScene.updateWorldMatrix(true, true);
  const box = new THREE.Box3().setFromObject(gltfScene);
  const size = box.getSize(new THREE.Vector3());
  const center = box.getCenter(new THREE.Vector3());
  const maxDim = Math.max(size.x, size.y, size.z) || 1;

  gltfScene.position.sub(center);       // geometry centred on the pivot's origin
  const pivot = new THREE.Group();
  pivot.add(gltfScene);
  pivot.scale.setScalar(1.6 / maxDim);  // same on-screen size for every model

  const dist = 1.6 / (2 * Math.tan((camera.fov * Math.PI) / 180 / 2));
  camera.position.set(0, 0.15, dist * 1.5);
  camera.lookAt(0, 0, 0);
  camera.updateProjectionMatrix();
  return pivot;
}

function disposeObject(obj) {
  obj.traverse((n) => {
    if (!n.isMesh) return;
    n.geometry?.dispose?.();
    for (const m of Array.isArray(n.material) ? n.material : [n.material]) {
      if (!m) continue;
      for (const k in m) { const v = m[k]; if (v && v.isTexture) v.dispose(); }
      m.dispose?.();
    }
  });
}

function loadCardModel(card) {
  if (card.loaded || card.loading || !card.entry.glb_url) return;
  card.loading = true;
  loader.load(
    card.entry.glb_url,
    (gltf) => {
      card.loading = false;
      if (card.disposed) { disposeObject(gltf.scene); return; }
      card.model = fitModel(gltf.scene, card.camera); // pivot wrapping the model
      colorizeIfUncolored(card.model); // untextured/colourless → colour-coded
      card.scene.add(card.model);
      card.loaded = true;
      card.spin.style.display = 'none';
      enforceLoadCap();
    },
    undefined,
    () => { card.loading = false; card.spin.textContent = 'preview unavailable'; },
  );
}

function unloadCardModel(card) {
  if (card.model) { card.scene.remove(card.model); disposeObject(card.model); card.model = null; }
  card.loaded = false;
  card.spin.style.display = '';
  card.spin.textContent = '◆ loading…';
}

function enforceLoadCap() {
  const loaded = cards.filter((c) => c.loaded);
  if (loaded.length <= MAX_LOADED) return;
  const mid = window.scrollY + window.innerHeight / 2;
  loaded
    .map((c) => ({ c, d: Math.abs(cardCenterY(c) - mid) }))
    .sort((a, b) => b.d - a.d)
    .slice(0, loaded.length - MAX_LOADED)
    .forEach(({ c }) => { if (!c.near) unloadCardModel(c); });
}

function cardCenterY(card) {
  const r = card.stage.getBoundingClientRect();
  return window.scrollY + r.top + r.height / 2;
}

function createCard(entry) {
  const el = document.createElement('div');
  el.className = 'card';
  el.innerHTML = `
    <div class="stage"><div class="spin">◆ loading…</div><div class="drag-hint">drag to rotate</div></div>
    <div class="meta">
      <p class="title"></p>
      <div class="row"><span class="badge"></span></div>
      <p class="prompt"></p>
    </div>`;
  el.querySelector('.title').textContent = entry.title || 'Untitled';
  el.querySelector('.badge').textContent = entry.model || 'Nova3D';
  const promptEl = el.querySelector('.prompt');
  if (entry.prompt) promptEl.textContent = entry.prompt; else promptEl.remove();

  const stage = el.querySelector('.stage');

  // Reference-image input(s), if any: a picture-in-picture chip in the corner.
  const refs = (entry.reference_images || []).filter(Boolean);
  if (refs.length) {
    const chip = document.createElement('div');
    chip.className = 'ref-chip';
    chip.title = refs.length > 1 ? `${refs.length} reference images` : 'Reference image';
    chip.innerHTML =
      `<img src="${encodeURI(refs[0])}" alt="input" loading="lazy" decoding="async"` +
      ` onerror="this.closest('.ref-chip').remove()">` +
      (refs.length > 1 ? `<span class="ref-count">+${refs.length - 1}</span>` : '');
    stage.appendChild(chip);
  }
  const card = {
    entry, el, stage, spin: el.querySelector('.spin'),
    scene: buildScene(), camera: makeCamera(), model: null,
    loaded: false, loading: false, near: false, disposed: false,
    rot: { x: 0.1, y: 0.4 }, dragging: false,
  };

  // Drag rotates this tile; a press without drag opens the detail (editor).
  let startX = 0, startY = 0, moved = 0, down = false;
  stage.addEventListener('pointerdown', (e) => {
    down = true; moved = 0; startX = e.clientX; startY = e.clientY;
    card.dragging = true; stage.setPointerCapture(e.pointerId);
  });
  stage.addEventListener('pointermove', (e) => {
    if (!down) return;
    const dx = e.clientX - startX, dy = e.clientY - startY;
    moved = Math.max(moved, Math.abs(dx) + Math.abs(dy));
    card.rot.y += dx * 0.01;
    card.rot.x = Math.max(-1.2, Math.min(1.2, card.rot.x + dy * 0.01));
    startX = e.clientX; startY = e.clientY;
  });
  const endDrag = (e) => {
    if (!down) return;
    down = false; card.dragging = false;
    try { stage.releasePointerCapture(e.pointerId); } catch (_) {}
    if (moved < DRAG_THRESHOLD) openDetail(entry);
  };
  stage.addEventListener('pointerup', endDrag);
  stage.addEventListener('pointercancel', endDrag);

  return card;
}

// ── Render loop (scissor per visible tile) ───────────────────────────────────
let last = performance.now();
// Paused while the host app shows a modal over us (texturing hand-off): the tiles
// are hidden behind it anyway, and a live WebGL loop on the shared browser thread
// makes the host's text input janky. We keep the RAF alive so it resumes cleanly.
let renderPaused = false;
function renderLoop(now) {
  if (renderPaused) { last = now; requestAnimationFrame(renderLoop); return; }
  const dt = Math.min(0.05, (now - last) / 1000);
  last = now;

  renderer.setScissorTest(false);
  renderer.clear(true, true, true);
  renderer.setScissorTest(true);

  const H = window.innerHeight;
  for (const card of cards) {
    const r = card.stage.getBoundingClientRect();
    if (r.bottom <= 0 || r.top >= H || r.width < 2 || !card.loaded) continue;
    if (!card.dragging) card.rot.y += dt * 0.35;
    if (card.model) card.model.rotation.set(card.rot.x, card.rot.y, 0);
    const w = r.width, h = r.height, bottom = H - r.bottom;
    renderer.setViewport(r.left, bottom, w, h);
    renderer.setScissor(r.left, bottom, w, h);
    if (card.camera.aspect !== w / h) { card.camera.aspect = w / h; card.camera.updateProjectionMatrix(); }
    renderer.render(card.scene, card.camera);
  }
  requestAnimationFrame(renderLoop);
}

// ── Detail overlay (embeds the real editor + CODE + INPUTS) ──────────────────
const detailEl = document.getElementById('detail');
const detailEditor = document.getElementById('detailEditor');
const detailCode = document.getElementById('detailCode');
const detailInputs = document.getElementById('detailInputs');
const dlGlb = document.getElementById('dlGlb');
const dlCode = document.getElementById('dlCode');
const txBtn = document.getElementById('txBtn');
let currentEntry = null;

// The Texture action needs the Nova3D app as a host to receive the request and
// open the texturing conversation. A standalone/public gallery has no parent
// window, so the button only appears when embedded in an iframe.
const EMBEDDED = !!(window.parent && window.parent !== window);
if (EMBEDDED) txBtn.style.display = '';

// Texturing is fetched server-side, so both artifacts must be absolute http(s)
// URLs (relative dev URLs cannot be resolved by the backend).
function isAbsoluteHttp(u) {
  return typeof u === 'string' && (u.startsWith('https://') || u.startsWith('http://'));
}
function canTexture(entry) {
  return EMBEDDED && !!entry && isAbsoluteHttp(entry.glb_url) && isAbsoluteHttp(entry.code_url);
}

function openDetail(entry) {
  currentEntry = entry;
  detailEl.classList.add('open');
  setDetailTab('model');
  dlGlb.disabled = !entry.glb_url;
  dlCode.disabled = !entry.code_url;
  if (EMBEDDED) txBtn.disabled = !canTexture(entry);

  // MODEL → the real editor in showcase mode (AI-edit tools hidden), this glb.
  detailEditor.src = entry.glb_url
    ? `/nova3d_viewer.html?showcase=1&mode=editor&stateKey=${encodeURIComponent('showcase-' + (entry.id || ''))}`
      + `&glb=${encodeURIComponent(entry.glb_url)}`
    : 'about:blank';

  // INPUTS
  detailInputs.innerHTML = '';
  const add = (label, html) => detailInputs.insertAdjacentHTML('beforeend', `<h3>${label}</h3>${html}`);
  add('Model', `<p>${escapeHtml(entry.model || 'Nova3D')}</p>`);
  if (entry.prompt) add('Prompt', `<p>${escapeHtml(entry.prompt)}</p>`);
  const refs = (entry.reference_images || []).filter(Boolean);
  if (refs.length) add('Reference images',
    `<div class="refs">${refs.map((u) => `<img src="${encodeURI(u)}" alt="reference">`).join('')}</div>`);

  // CODE (lazy)
  detailCode.textContent = 'Loading code…';
  if (entry.code_url) {
    fetch(entry.code_url).then((r) => r.text())
      .then((t) => { detailCode.textContent = t; })
      .catch(() => { detailCode.textContent = 'Code unavailable.'; });
  } else {
    detailCode.textContent = 'No source code for this entry.';
  }
}

function closeDetail() {
  detailEl.classList.remove('open');
  detailEditor.src = 'about:blank'; // free the editor + its WebGL context
  renderPaused = false; // in case a texture hand-off paused us
}

function setDetailTab(tab) {
  document.querySelectorAll('.tab').forEach((t) => t.classList.toggle('active', t.dataset.tab === tab));
  detailEditor.style.display = tab === 'model' ? 'block' : 'none';
  detailCode.style.display = tab === 'code' ? 'block' : 'none';
  detailInputs.style.display = tab === 'inputs' ? 'block' : 'none';
}

document.getElementById('detailClose').addEventListener('click', closeDetail);
detailEl.addEventListener('click', (e) => { if (e.target === detailEl) closeDetail(); });
document.querySelectorAll('.tab').forEach((t) => t.addEventListener('click', () => setDetailTab(t.dataset.tab)));
window.addEventListener('keydown', (e) => { if (e.key === 'Escape' && detailEl.classList.contains('open')) closeDetail(); });

// ── Downloads (fetch as blob so it works cross-origin too) ───────────────────
async function downloadUrl(url, filename) {
  try {
    const resp = await fetch(url);
    if (!resp.ok) throw new Error(String(resp.status));
    const blob = await resp.blob();
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob); a.download = filename; a.click();
    setTimeout(() => URL.revokeObjectURL(a.href), 1500);
  } catch (_) { /* ignore */ }
}
function safeName(title, ext) {
  const s = (title || 'model').toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '');
  return `${s || 'model'}.${ext}`;
}
dlGlb.addEventListener('click', () => {
  if (currentEntry?.glb_url) downloadUrl(currentEntry.glb_url, safeName(currentEntry.title, 'glb'));
});
dlCode.addEventListener('click', () => {
  if (currentEntry?.code_url) downloadUrl(currentEntry.code_url, safeName(currentEntry.title, 'py'));
});

// ── Texture (embedded only): hand the model to the Nova3D app ─────────────────
// Posts the model's public URLs to the host app, which gates sign-in and opens
// a new texturing conversation. We send only public URLs + a title; the host
// validates before acting.
let txPosting = false;
txBtn.addEventListener('click', () => {
  if (txPosting || txBtn.disabled || !canTexture(currentEntry)) return;
  txPosting = true;
  txBtn.disabled = true;
  // Free the shared browser thread + keyboard focus for the host's dialog: pause
  // our render loop and hand focus back to the parent window. Focus staying in
  // this iframe leaves the dialog's inputs untypeable; a live render loop makes
  // typing janky.
  renderPaused = true;
  txBtn.blur();
  try { window.parent.focus(); } catch (_) { /* cross-origin: host also blurs */ }
  window.parent.postMessage({
    type: 'nova3d-showcase-texture',
    entry: {
      id: currentEntry.id || '',
      title: currentEntry.title || 'Showcase model',
      glb_url: currentEntry.glb_url || '',
      code_url: currentEntry.code_url || '',
    },
  }, '*');
  // The host normally navigates away (unmounting this gallery). If it doesn't
  // (e.g. the user cancels the texture dialog), re-enable + resume rendering.
  setTimeout(() => {
    txPosting = false;
    renderPaused = false;
    if (currentEntry) txBtn.disabled = !canTexture(currentEntry);
  }, 2500);
});

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, (c) =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

// ── Boot ─────────────────────────────────────────────────────────────────────
function manifestUrl() {
  const p = new URLSearchParams(location.search).get('manifest');
  return p && p.trim() ? p.trim() : null;
}

async function boot() {
  const url = manifestUrl();
  if (!url) { statusEl.textContent = 'No showcase configured.'; return; }
  let data;
  try {
    const resp = await fetch(url, { cache: 'no-store' });
    if (!resp.ok) throw new Error(String(resp.status));
    data = await resp.json();
  } catch (_) {
    statusEl.textContent = 'Could not load the showcase.';
    return;
  }
  const entries = Array.isArray(data?.entries) ? data.entries : [];
  if (!entries.length) { statusEl.textContent = 'The showcase is empty.'; return; }

  statusEl.style.display = 'none';
  countEl.textContent = `${entries.length} model${entries.length === 1 ? '' : 's'}`;

  const io = new IntersectionObserver((batches) => {
    for (const b of batches) {
      const card = b.target._card;
      if (!card) continue;
      card.near = b.isIntersecting;
      if (card.near) loadCardModel(card);
    }
    enforceLoadCap();
  }, { root: scrollEl, rootMargin: NEAR_MARGIN, threshold: 0 });

  for (const entry of entries) {
    const card = createCard(entry);
    card.el._card = card;
    cards.push(card);
    gridEl.appendChild(card.el);
    io.observe(card.el);
  }

  requestAnimationFrame(renderLoop);
}

boot();
