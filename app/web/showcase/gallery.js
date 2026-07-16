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
// Versioned import: ES `import` specifiers don't inherit the <script ?v=>, so
// bump this in lockstep with the script tag whenever showcase_colorize.js
// changes, otherwise browsers keep a stale cached copy of it.
import { colorizeIfUncolored } from '../nova3d/showcase_colorize.js?v=5';
// Jewelry materials for rings published WITH a materials spec: the tile renders
// the exact metal/gem/pearl assignment chosen at publish time (same module the
// publish UI and the detail viewer use). Bump ?v= with the file.
import {
  applyJewelSpec, updateJewelEnv, loadJewelEnv, setJewelRendering,
} from '../nova3d/jewel_materials.js?v=2';

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

function buildScene(entry) {
  const scene = new THREE.Scene();
  if (entryHasJewelSpec(entry)) {
    // Jewel parity: HDRI-only lighting + the same soft key light the publish
    // UI uses — the studio env swaps in as soon as it has downloaded.
    const env = loadJewelEnv(renderer);
    scene.environment = env.pmrem || ENV;
    const key = new THREE.DirectionalLight(0xffffff, 0.55);
    key.position.set(1.5, 8, 2);
    scene.add(key);
    return scene;
  }
  scene.environment = ENV;
  const key = new THREE.DirectionalLight(0xffffff, 1.4);
  key.position.set(2, 3, 2);
  scene.add(key);
  scene.add(new THREE.HemisphereLight(0xffffff, 0x554e77, 0.5));
  return scene;
}

function entryHasJewelSpec(entry) {
  return entry?.kind === 'ring' && entry.materials && typeof entry.materials === 'object';
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
      if (entryHasJewelSpec(card.entry)) {
        // Ring published with a materials spec: render the exact metals/gems
        // chosen at publish time (identical to the publish UI + detail view).
        const env = loadJewelEnv(renderer, (e) => {
          if (card.disposed || !card.model) return;
          if (e.pmrem) card.scene.environment = e.pmrem;
          updateJewelEnv(card.model, { raw: e.raw });
        });
        applyJewelSpec(card.model, card.entry.materials, { raw: env.raw });
      } else {
        // Legacy rings (no spec): force soft pastel part-coding instead of grey.
        // Everything else: colour-code only if it ships no colour.
        colorizeIfUncolored(card.model,
          card.entry.kind === 'ring' ? { force: true, pastel: true } : {});
      }
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
    scene: buildScene(entry), camera: makeCamera(), model: null,
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
const detailPbr = document.getElementById('detailPbr');
const tabPbr = document.getElementById('tabPbr');

// Preferred PBR map order (chat-preview parity); unknown names sort after.
const MAP_ORDER = ['albedo', 'normal', 'roughness', 'metallic', 'ao', 'height'];
const dlGlb = document.getElementById('dlGlb');
const dlCode = document.getElementById('dlCode');
const dlZip = document.getElementById('dlZip');
const txBtn = document.getElementById('txBtn');
let currentEntry = null;

// The Texture action needs the Nova3D app as a host to receive the request and
// open the texturing conversation. A standalone/public gallery has no parent
// window, so the button only appears when embedded in an iframe. It is also
// hidden on texture entries — their glb is already textured, so re-texturing it
// would condition the pipeline on the wrong (painted) renders.
const EMBEDDED = !!(window.parent && window.parent !== window);

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
  dlZip.style.display = entry.maps_zip_url ? '' : 'none';
  const texEntry = entry.kind === 'texture';
  txBtn.style.display = EMBEDDED && !texEntry ? '' : 'none';
  if (EMBEDDED) txBtn.disabled = !canTexture(entry);

  // PBR tab: the full artist deliverable set, grouped by folder in the same
  // order as the app's chat preview. Entries published before the assets list
  // existed fall back to their flat maps dict.
  let assets = Array.isArray(entry.assets) ? entry.assets.filter((a) => a && a.url) : [];
  if (!assets.length && entry.maps && typeof entry.maps === 'object') {
    assets = Object.keys(entry.maps)
      .sort((a, b) => {
        const ia = MAP_ORDER.indexOf(a), ib = MAP_ORDER.indexOf(b);
        return (ia === -1 ? 99 : ia) - (ib === -1 ? 99 : ib) || a.localeCompare(b);
      })
      .map((n) => ({folder: 'maps', name: `${n}.png`, url: entry.maps[n],
                    label: `${n[0].toUpperCase()}${n.slice(1)} map`}));
  }
  tabPbr.style.display = assets.length ? '' : 'none';
  detailPbr.innerHTML = '';
  if (assets.length) {
    const SECTIONS = [
      ['maps', 'PBR MAPS'], ['tiles/albedo', 'TILES · ALBEDO'],
      ['tiles/relief', 'TILES · RELIEF'], ['atlases', 'ATLASES'],
      ['uv', 'UV LAYOUTS'], ['', 'PIPELINE'],
    ];
    const known = new Set(SECTIONS.map(([f]) => f));
    for (const a of assets) if (!known.has(a.folder || '')) SECTIONS.push([a.folder, a.folder.toUpperCase()]);
    for (const [folder, heading] of SECTIONS) {
      const group = assets.filter((a) => (a.folder || '') === folder);
      if (!group.length) continue;
      const cards = group.map((a) => {
        const label = escapeHtml(a.label || a.name);
        const isImage = /\.(png|jpe?g|webp|svg)$/i.test(a.name || '');
        const inner = isImage
          ? `<img src="${encodeURI(a.url)}" alt="${label}" loading="lazy" decoding="async">`
          : `<a class="file" href="${encodeURI(a.url)}" target="_blank" rel="noopener">{ } ${escapeHtml(a.name)}</a>`;
        return `<figure>${inner}<figcaption>${label}</figcaption></figure>`;
      }).join('');
      detailPbr.insertAdjacentHTML('beforeend', `<h3>${heading}</h3><div class="maps">${cards}</div>`);
    }
  }

  // MODEL → the real editor in showcase mode (AI-edit tools hidden), this glb.
  // Rings with a published materials spec open in jewel mode (identical
  // rendering to the tile + publish UI); legacy rings keep the pastel coding.
  detailEditor.src = entry.glb_url
    ? `/nova3d_viewer.html?showcase=1&mode=editor&stateKey=${encodeURIComponent('showcase-' + (entry.id || ''))}`
      + `&glb=${encodeURIComponent(entry.glb_url)}`
      + ringDetailParams(entry)
    : 'about:blank';

  // INPUTS
  detailInputs.innerHTML = '';
  const add = (label, html) => detailInputs.insertAdjacentHTML('beforeend', `<h3>${label}</h3>${html}`);
  add('Model', `<p>${escapeHtml(entry.model || 'Nova3D')}</p>`);
  if (entry.prompt) add('Prompt', `<p>${escapeHtml(entry.prompt)}</p>`);
  if (entry.kind === 'texture' && entry.workflow_id) {
    add('Texture run', `<p>${escapeHtml(entry.workflow_id)}</p>`);
  }
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

// Ring detail params: jewel mode needs the materials spec URL. Entries publish
// a {id}/materials.json blob; if only the inline spec exists, pass it as a
// data: URL (fetch() resolves those) so the viewer needs no extra endpoint.
function ringDetailParams(entry) {
  if (entry.kind !== 'ring') return '';
  if (entryHasJewelSpec(entry)) {
    const url = entry.materials_url
      || ('data:application/json,' + encodeURIComponent(JSON.stringify(entry.materials)));
    return `&jewel=1&materials=${encodeURIComponent(url)}`;
  }
  return '&pastel=1';
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
  detailPbr.style.display = tab === 'pbr' ? 'block' : 'none';
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
dlZip.addEventListener('click', () => {
  if (currentEntry?.maps_zip_url) {
    downloadUrl(currentEntry.maps_zip_url, safeName(currentEntry.title + '_maps', 'zip'));
  }
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

// ── Boot + catalog tabs (generations | textures) ─────────────────────────────
// Generations read the ?manifest= URL as before; textures read the sibling
// `textures.json` blob in the same container, derived from that URL. Each tab
// keeps its fetched entries cached; switching disposes the mounted cards and
// mounts the other list into the same shared-renderer grid.
function manifestUrl() {
  const p = new URLSearchParams(location.search).get('manifest');
  return p && p.trim() ? p.trim() : null;
}

function texturesManifestUrl() {
  return siblingManifestUrl('textures.json');
}

// Rings are generation-shaped entries (glb + code) published to a sibling
// `rings.json` in the same public container, from the ring-only skill.
function ringsManifestUrl() {
  return siblingManifestUrl('rings.json');
}

// Derive a sibling manifest (textures.json / rings.json) from the generations
// manifest URL, preserving any query string.
function siblingManifestUrl(name) {
  const url = manifestUrl();
  if (!url) return null;
  if (/showcase\.json/.test(url)) return url.replace(/showcase\.json/, name);
  return url.replace(/\/[^/?#]*(\?.*)?$/, `/${name}$1`);
}

let io = null;
let renderLoopStarted = false;
const catalogs = { generations: null, textures: null, rings: null }; // fetched entry caches
let activeCat = 'generations';

function disposeCards() {
  if (io) { io.disconnect(); io = null; }
  for (const card of cards) {
    card.disposed = true;
    if (card.model) { card.scene.remove(card.model); disposeObject(card.model); card.model = null; }
    card.el.remove();
  }
  cards.length = 0;
}

function mountEntries(entries, noun) {
  disposeCards();
  // Ring tiles use the publish UI's tone mapping (Khronos PBR-neutral) so the
  // published materials match it exactly; other catalogs keep the default
  // look. Safe to flip per mount: a mount recreates every card + material.
  if (noun === 'ring') setJewelRendering(renderer);
  else { renderer.toneMapping = THREE.NoToneMapping; renderer.toneMappingExposure = 1; }
  if (!entries.length) {
    statusEl.style.display = '';
    statusEl.textContent = noun === 'texture'
      ? 'No textures published yet.'
      : noun === 'ring'
        ? 'No rings published yet.'
        : 'The showcase is empty.';
    countEl.textContent = '';
    return;
  }
  statusEl.style.display = 'none';
  countEl.textContent = `${entries.length} ${noun}${entries.length === 1 ? '' : 's'}`;

  io = new IntersectionObserver((batches) => {
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

  if (!renderLoopStarted) {
    renderLoopStarted = true;
    requestAnimationFrame(renderLoop);
  }
}

async function fetchEntries(url) {
  const resp = await fetch(url, { cache: 'no-store' });
  if (!resp.ok) throw new Error(String(resp.status));
  const data = await resp.json();
  return Array.isArray(data?.entries) ? data.entries : [];
}

async function showCatalog(cat) {
  activeCat = cat;
  document.querySelectorAll('.cat-tab').forEach((t) =>
    t.classList.toggle('active', t.dataset.cat === cat));
  const noun = cat === 'textures' ? 'texture' : cat === 'rings' ? 'ring' : 'model';

  // Cache non-empty catalogs only: an empty tab should re-fetch so a
  // newly-published entry (e.g. a first ring) shows on tab revisit, not
  // only after a full page reload.
  if (catalogs[cat] && catalogs[cat].length) { mountEntries(catalogs[cat], noun); return; }

  disposeCards();
  countEl.textContent = '';
  statusEl.style.display = '';
  statusEl.textContent = 'Loading showcase…';

  const url = cat === 'textures' ? texturesManifestUrl()
    : cat === 'rings' ? ringsManifestUrl()
    : manifestUrl();
  if (!url) { statusEl.textContent = 'No showcase configured.'; return; }
  let entries;
  try {
    entries = await fetchEntries(url);
  } catch (_) {
    // A missing textures.json / rings.json just means nothing is published yet.
    entries = cat === 'generations' ? null : [];
    if (entries === null) { statusEl.textContent = 'Could not load the showcase.'; return; }
  }
  if (cat === 'textures') for (const e of entries) e.kind = e.kind || 'texture';
  if (cat === 'rings') for (const e of entries) e.kind = e.kind || 'ring';
  catalogs[cat] = entries;
  if (activeCat === cat) mountEntries(entries, noun);
}

// ── Per-tab deep linking ─────────────────────────────────────────────────────
// Each tab has its own app URL (/showcase, /showcase/textures, /showcase/rings).
// The gallery lives in an iframe, so the host app owns the address bar: on a tab
// click we postMessage the new tab OUT so the app can update the URL; the app
// postMessages a tab IN (e.g. on back/forward or a deep link within the SPA) and
// we switch without echoing back — that one-way notify keeps the two in sync
// without a feedback loop. Standalone (no parent) it just reads ?tab= on load.
const CATS = ['generations', 'textures', 'rings'];
function validCat(v) { return CATS.includes(v) ? v : null; }

function initialCat() {
  return validCat(new URLSearchParams(location.search).get('tab')) || 'generations';
}

function notifyParentTab(cat) {
  if (window.parent && window.parent !== window) {
    try { window.parent.postMessage({ type: 'nova3d-showcase-tab', tab: cat }, '*'); } catch (_) {}
  }
}

document.querySelectorAll('.cat-tab').forEach((t) =>
  t.addEventListener('click', () => {
    if (t.dataset.cat === activeCat) return;
    showCatalog(t.dataset.cat);
    notifyParentTab(t.dataset.cat); // user-initiated → update the app URL
  }));

// Host app → gallery: switch tab without notifying back (avoids a loop).
window.addEventListener('message', (e) => {
  const d = e.data;
  if (!d || d.type !== 'nova3d-showcase-set-tab') return;
  const cat = validCat(d.tab);
  if (cat && cat !== activeCat) showCatalog(cat);
});

showCatalog(initialCat());
