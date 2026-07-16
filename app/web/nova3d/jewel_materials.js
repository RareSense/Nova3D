// Jewelry-grade material system shared by every surface that shows a published
// ring: the private publish UI (tools/showcase/rings_admin.html), the public
// showcase tiles (web/showcase/gallery.js) and the enlarged editor preview
// (nova3d_viewer.html?jewel=1). One implementation — so a ring looks IDENTICAL
// at publish time, in the grid and in the detail view.
//
// Gems are ray-traced in the fragment shader: the view ray refracts into the
// stone, reflects off the stone's own facet geometry (BVH) with total internal
// reflection, then samples the studio HDRI — R/G/B traced at slightly
// different IORs for fire, plus a Schlick surface reflection so flat step cuts
// (baguette / emerald cut) read as polished instead of matte. Same technique
// as iJewel / drei's MeshRefractionMaterial.
//
// MATERIALS SPEC (stored inline in rings.json entries and as the entry's
// {id}/materials.json blob):
//   { "version": 1,
//     "metal": "gold18k",                       // JEWEL_MATS key for metal parts
//     "assignments": { "<mesh name>": "<JEWEL_MATS key>", ... } }
// Meshes missing from `assignments` fall back to name classification
// (classifyPartName), so a partial spec still renders sensibly.
//
// PARITY RULES — every surface must do BOTH, or rings will not match:
//   1. setJewelRendering(renderer)   → NeutralToneMapping, exposure 1.0
//   2. loadJewelEnv(renderer, cb)    → light the scene with cb's pmrem texture
//      and pass its raw texture to applyJewelSpec / updateJewelEnv.

import * as THREE from 'three';
import { RGBELoader } from 'three/addons/loaders/RGBELoader.js';
import {
  MeshBVH, MeshBVHUniformStruct, shaderStructs, shaderIntersectFunction, SAH,
} from 'three-mesh-bvh';

export const JEWEL_ENV_URL =
  'https://dl.polyhaven.org/file/ph-assets/HDRIs/hdr/1k/brown_photostudio_02_1k.hdr';
export const DEFAULT_METAL = 'gold18k';

export const JEWEL_MATS = {
  gold18k:      { label: 'Yellow Gold',  kind: 'metal', color: 0xffd88a, rough: 0.08 },
  roseGold:     { label: 'Rose Gold',    kind: 'metal', color: 0xf6c1a6, rough: 0.08 },
  whiteGold:    { label: 'White Gold',   kind: 'metal', color: 0xf7f4ec, rough: 0.07 },
  platinum:     { label: 'Platinum',     kind: 'metal', color: 0xe9e9e7, rough: 0.11 },
  silver:       { label: 'Silver',       kind: 'metal', color: 0xfbfaf6, rough: 0.05 },
  blackRhodium: { label: 'Black Rhod.',  kind: 'metal', color: 0x3b3b40, rough: 0.28 },

  diamond:      { label: 'Diamond',      kind: 'gem', color: 0xffffff, atten: 0xffffff, ior: 2.42, disp: 0.02 },
  champagne:    { label: 'Champagne',    kind: 'gem', color: 0xf6e3bd, atten: 0xc89a4e, ior: 2.42, disp: 0.02 },
  ruby:         { label: 'Ruby',         kind: 'gem', color: 0xf26a8c, atten: 0x9e0f34, ior: 1.76 },
  sapphire:     { label: 'Sapphire',     kind: 'gem', color: 0x4f7ce0, atten: 0x0c2f9e, ior: 1.76 },
  emerald:      { label: 'Emerald',      kind: 'gem', color: 0x46c684, atten: 0x02702f, ior: 1.57, rough: 0.03 },
  amethyst:     { label: 'Amethyst',     kind: 'gem', color: 0xb488e2, atten: 0x5c1e96, ior: 1.54 },
  citrine:      { label: 'Citrine',      kind: 'gem', color: 0xf2bb4d, atten: 0xa96400, ior: 1.54 },
  aquamarine:   { label: 'Aquamarine',   kind: 'gem', color: 0xaee2de, atten: 0x2f9e96, ior: 1.57 },
  topaz:        { label: 'London Topaz', kind: 'gem', color: 0x4b9dbd, atten: 0x0e4a66, ior: 1.61 },
  garnet:       { label: 'Garnet',       kind: 'gem', color: 0xcd5050, atten: 0x570a10, ior: 1.73 },
  peridot:      { label: 'Peridot',      kind: 'gem', color: 0xbcd45c, atten: 0x647f04, ior: 1.65 },
  tanzanite:    { label: 'Tanzanite',    kind: 'gem', color: 0x7480e2, atten: 0x28329e, ior: 1.69 },
  morganite:    { label: 'Morganite',    kind: 'gem', color: 0xf4c6c6, atten: 0xc06a78, ior: 1.58 },
  blackDiamond: { label: 'Black Diam.',  kind: 'gem', color: 0x17171c, atten: 0x000000, ior: 2.42, rough: 0.04, dark: true },

  pearlWhite:   { label: 'White Pearl',  kind: 'pearl', color: 0xfdfaf3, sheen: 0xf6dfda },
  pearlGolden:  { label: 'Golden Pearl', kind: 'pearl', color: 0xf0d9a2, sheen: 0xf6c86a },
  pearlPink:    { label: 'Pink Pearl',   kind: 'pearl', color: 0xf6d5d8, sheen: 0xf2aab6 },
  pearlBlack:   { label: 'Tahitian',     kind: 'pearl', color: 0x2e3438, sheen: 0x4fa08c, irid: 0.85 },
  opal:         { label: 'Opal',         kind: 'pearl', color: 0xf2f0ea, sheen: 0xffffff, irid: 1, opal: true },
};

// ── Part-name classification (matches the ring pipeline's naming) ────────────
const TYPE_RULES = [
  [/pearl/i, 'pearlWhite'], [/opal/i, 'opal'], [/ruby/i, 'ruby'],
  [/sapphire/i, 'sapphire'], [/emerald/i, 'emerald'], [/amethyst/i, 'amethyst'],
  [/citrine/i, 'citrine'], [/aqua/i, 'aquamarine'], [/topaz/i, 'topaz'],
  [/garnet/i, 'garnet'], [/peridot/i, 'peridot'], [/tanzanit/i, 'tanzanite'],
  [/morganite/i, 'morganite'], [/onyx|black[_ ]?diamond/i, 'blackDiamond'],
];
const GEM_RE = /diamond|gem|stone|crystal|jewel|brill|cz|cubic|solitaire|pave|moissanite|briolette|cabochon/i;

export function classifyPartName(name, metal = DEFAULT_METAL) {
  for (const [re, key] of TYPE_RULES) if (re.test(name)) return key;
  if (GEM_RE.test(name)) return 'diamond';
  return JEWEL_MATS[metal] ? metal : DEFAULT_METAL;
}

// Group key for "link similar": strips trailing numeric suffixes
// (accent_gem_theta_105 → accent_gem, corner_prong_0_1 → corner_prong).
export function partBaseName(name) {
  return (name || '').toLowerCase().replace(/(?:[_\s-]*(?:theta|idx)?[_\s-]*\d+)+$/, '');
}

// ── Renderer parity ──────────────────────────────────────────────────────────
export function setJewelRendering(renderer) {
  renderer.toneMapping = THREE.NeutralToneMapping;
  renderer.toneMappingExposure = 1.0;
}

// ── Studio environment (per-renderer cache; raw equirect kept for gems) ──────
const envCache = new WeakMap(); // renderer → { raw, pmrem, failed, callbacks }

export function loadJewelEnv(renderer, onReady) {
  let e = envCache.get(renderer);
  if (!e) {
    e = { raw: null, pmrem: null, failed: false, callbacks: [] };
    envCache.set(renderer, e);
    new RGBELoader().load(JEWEL_ENV_URL, (tex) => {
      tex.mapping = THREE.EquirectangularReflectionMapping;
      const pm = new THREE.PMREMGenerator(renderer);
      e.pmrem = pm.fromEquirectangular(tex).texture;
      pm.dispose();
      e.raw = tex; // NOT disposed: the gem shader samples the equirect directly
      e.callbacks.splice(0).forEach((cb) => { try { cb(e); } catch (_) {} });
    }, undefined, () => {
      e.failed = true;
      e.callbacks.splice(0).forEach((cb) => { try { cb(e); } catch (_) {} });
    });
  }
  if (onReady) {
    if (e.raw || e.failed) onReady(e);
    else e.callbacks.push(onReady);
  }
  return e;
}

// ── Ray-traced faceted gem shader ────────────────────────────────────────────
const GEM_VERT = /* glsl */`
varying vec3 vWorldPosition;
varying vec3 vNormal;
varying mat4 vModelMatrixInverse;
void main(){
  vec4 wp=modelMatrix*vec4(position,1.0);
  vWorldPosition=wp.xyz;
  vNormal=normalize(mat3(modelMatrix)*normal);
  vModelMatrixInverse=inverse(modelMatrix);
  gl_Position=projectionMatrix*viewMatrix*wp;
}`;

const GEM_FRAG = /* glsl */`
precision highp isampler2D;
precision highp usampler2D;
varying vec3 vWorldPosition;
varying vec3 vNormal;
varying mat4 vModelMatrixInverse;
uniform mat4 modelMatrix;
uniform sampler2D envMap;
uniform float bounces;
${shaderStructs}
${shaderIntersectFunction}
uniform BVH bvh;
uniform float ior;
uniform float fresnel;
uniform float aberrationStrength;
uniform vec3 colorFactor;
uniform float envIntensity;
uniform float selected;

vec3 sampleEnv(vec3 dir){
  vec2 uv=vec2(atan(dir.z,dir.x)*0.1591549431+0.5,asin(clamp(dir.y,-1.0,1.0))*0.3183098862+0.5);
  return texture2D(envMap,uv).rgb;
}
vec3 totalInternalReflection(vec3 incoming,float ior_){
  vec3 rayDirection=refract(incoming,vNormal,1.0/ior_);
  vec3 rayOrigin=vWorldPosition+rayDirection*0.001;
  rayOrigin=(vModelMatrixInverse*vec4(rayOrigin,1.0)).xyz;
  rayDirection=normalize((vModelMatrixInverse*vec4(rayDirection,0.0)).xyz);
  for(float i=0.0;i<8.0;i++){
    if(i>=bounces)break;
    uvec4 faceIndices=uvec4(0u);
    vec3 faceNormal=vec3(0.0,0.0,1.0);
    vec3 barycoord=vec3(0.0);
    float side=1.0;
    float dist=0.0;
    bvhIntersectFirstHit(bvh,rayOrigin,rayDirection,faceIndices,faceNormal,barycoord,side,dist);
    vec3 hitPos=rayOrigin+rayDirection*max(dist-0.001,0.0);
    vec3 tempDir=refract(rayDirection,faceNormal*side,ior_);
    if(length(tempDir)!=0.0){rayDirection=tempDir;break;}
    rayDirection=reflect(rayDirection,faceNormal*side);
    rayOrigin=hitPos+rayDirection*0.01;
  }
  return normalize((modelMatrix*vec4(rayDirection,0.0)).xyz);
}
void main(){
  vec3 viewDirection=normalize(vWorldPosition-cameraPosition);
  vec3 dG=totalInternalReflection(viewDirection,max(ior,1.0));
  vec3 col;
  if(aberrationStrength>0.0){
    vec3 dR=totalInternalReflection(viewDirection,max(ior*(1.0-aberrationStrength),1.0));
    vec3 dB=totalInternalReflection(viewDirection,max(ior*(1.0+aberrationStrength),1.0));
    col=vec3(sampleEnv(dR).r,sampleEnv(dG).g,sampleEnv(dB).b);
  }else{
    col=sampleEnv(dG);
  }
  col*=envIntensity*colorFactor;
  // polished-surface reflection (Schlick) — flat table facets mirror the studio
  vec3 reflDir=reflect(viewDirection,vNormal);
  vec3 reflCol=sampleEnv(reflDir)*envIntensity;
  float cosT=clamp(-dot(viewDirection,vNormal),0.0,1.0);
  float F0=pow((ior-1.0)/(ior+1.0),2.0);
  float F=F0+(1.0-F0)*pow(1.0-cosT,5.0);
  col=mix(col,reflCol,F);
  float f=pow(max(0.0,1.0+dot(viewDirection,vNormal)),10.0)*fresnel;
  col=mix(col,vec3(1.0),f);
  col=mix(col,vec3(0.0,0.9,1.0),selected*0.4);
  gl_FragColor=vec4(col,1.0);
  #include <tonemapping_fragment>
  #include <colorspace_fragment>
}`;

// BVH uniform struct per geometry, freed with the geometry itself.
function bvhStructFor(geometry) {
  let s = geometry.userData._jewelBvh;
  if (!s) {
    s = new MeshBVHUniformStruct();
    s.updateFrom(new MeshBVH(geometry.clone(), { strategy: SAH }));
    geometry.userData._jewelBvh = s;
    geometry.addEventListener('dispose', () => {
      try { s.dispose(); } catch (_) {}
      delete geometry.userData._jewelBvh;
    });
  }
  return s;
}

function meshWorldSize(mesh) {
  const box = new THREE.Box3().setFromObject(mesh);
  if (box.isEmpty()) return 0.1;
  const s = box.getSize(new THREE.Vector3());
  return Math.max((s.x + s.y + s.z) / 3, 0.02);
}

const metalRough = (d, polish) => Math.min(0.6, d.rough + (1 - polish / 100) * 0.4);

// ctx: { raw: equirect HDR texture | null, envInt = 1, polish = 100, fast = false }
export function makeJewelMaterial(key, mesh, ctx = {}) {
  const d = JEWEL_MATS[key] || JEWEL_MATS.diamond;
  const envInt = ctx.envInt ?? 1;
  const polish = ctx.polish ?? 100;
  let m;
  if (d.kind === 'metal') {
    m = new THREE.MeshPhysicalMaterial({
      color: d.color, metalness: 1, roughness: metalRough(d, polish),
      envMapIntensity: 1.15 * envInt, side: THREE.DoubleSide,
    });
  } else if (d.kind === 'pearl') {
    m = new THREE.MeshPhysicalMaterial({
      color: d.color, metalness: 0, roughness: d.opal ? 0.14 : 0.24,
      clearcoat: 1, clearcoatRoughness: 0.12,
      iridescence: d.irid ?? 0.45, iridescenceIOR: 1.9,
      iridescenceThicknessRange: d.opal ? [100, 800] : [120, 440],
      sheen: 0.6, sheenColor: new THREE.Color(d.sheen), sheenRoughness: 0.4,
      envMapIntensity: 1.1 * envInt, side: THREE.DoubleSide,
    });
  } else if (ctx.fast) {
    m = new THREE.MeshPhysicalMaterial({
      color: d.color, metalness: 0.25, roughness: d.rough ?? 0.02,
      envMapIntensity: 3 * envInt, side: THREE.DoubleSide,
    });
    if (!d.dark) { m.transparent = true; m.opacity = 0.92; }
  } else if (ctx.raw) {
    // colored stones: filter the internal bounces toward the deep tone
    const filter = new THREE.Color(d.color)
      .lerp(new THREE.Color(d.atten), d.atten === 0xffffff ? 0 : 0.55);
    m = new THREE.ShaderMaterial({
      uniforms: {
        envMap: { value: ctx.raw },
        bvh: { value: bvhStructFor(mesh.geometry) },
        bounces: { value: 3 },
        ior: { value: d.ior },
        aberrationStrength: { value: d.disp ?? 0.008 },
        fresnel: { value: 0.25 },
        colorFactor: { value: filter },
        envIntensity: { value: 1.2 * envInt },
        selected: { value: 0 },
      },
      vertexShader: GEM_VERT, fragmentShader: GEM_FRAG, side: THREE.FrontSide,
    });
    m.isJewelGem = true;
  } else {
    // studio HDRI not downloaded yet — glassy placeholder; updateJewelEnv()
    // upgrades it to the ray-traced shader once the env arrives.
    const size = meshWorldSize(mesh);
    m = new THREE.MeshPhysicalMaterial({
      color: d.color, metalness: 0, roughness: d.rough ?? 0.005,
      transmission: d.dark ? 0.25 : 1, thickness: size * 1.1, ior: d.ior,
      attenuationColor: new THREE.Color(d.atten), attenuationDistance: size * 0.9,
      clearcoat: 0.5, clearcoatRoughness: 0.02,
      envMapIntensity: 2.3 * envInt, specularIntensity: 1, side: THREE.FrontSide,
    });
    m.isJewelPlaceholder = true;
  }
  m.userData.jewelKey = key;
  return m;
}

// Apply a materials spec to every mesh under `root`. Meshes not covered by the
// spec fall back to name classification. Returns the affected meshes.
export function applyJewelSpec(root, spec, ctx = {}) {
  const metal = (spec && JEWEL_MATS[spec.metal]) ? spec.metal : DEFAULT_METAL;
  const assignments = (spec && spec.assignments) || {};
  const meshes = [];
  root.traverse((n) => {
    if (!n.isMesh || !n.geometry?.attributes?.position?.count) return;
    const key = JEWEL_MATS[assignments[n.name]] ? assignments[n.name]
      : classifyPartName(n.name || '', metal);
    n.material = makeJewelMaterial(key, n, ctx);
    n.userData.jewelKey = key;
    meshes.push(n);
  });
  return meshes;
}

// Swap/upgrade gem materials after the HDRI finishes loading (or on env change).
export function updateJewelEnv(root, ctx = {}) {
  if (!ctx.raw) return;
  root.traverse((n) => {
    if (!n.isMesh || !n.userData.jewelKey) return;
    const m = n.material;
    if (m?.isJewelGem) {
      m.uniforms.envMap.value = ctx.raw;
    } else if (m?.isJewelPlaceholder) {
      m.dispose();
      n.material = makeJewelMaterial(n.userData.jewelKey, n, ctx);
    }
  });
}
