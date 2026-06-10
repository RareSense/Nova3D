// Materials, render-profile, environment-map application, metal/gem factories,
// and snapshot-serialization helpers for materials. Reads `state.envMap` /
// `state.scene` / `state.modelGroup` so it
// can be loaded before scene init — fields are populated by the inline boot
// script and PR 11 (scene.js).

import { THREE } from '@nova/three-ext.js';
import { state } from '@nova/state.js';
import { genNormalMap, genRoughnessMap } from '@nova/noise.js';

export const DEFAULT_ENV_INTENSITY = 1.15;

export function applyRenderProfileToMaterial(material) {
  const materials = Array.isArray(material) ? material : [material];
  materials.forEach(mat => {
    if (!mat || (!mat.isMeshStandardMaterial && !mat.isMeshPhysicalMaterial)) return;
    if (state.envMap) mat.envMap = state.envMap;
    if (mat.envMapIntensity === undefined || mat.envMapIntensity === null) {
      mat.envMapIntensity = DEFAULT_ENV_INTENSITY;
    }
    mat.needsUpdate = true;
  });
}

export function applyRenderProfileToObject(root) {
  if (!root) return;
  root.traverse?.(child => {
    if (child.isMesh) applyRenderProfileToMaterial(child.material);
  });
}

export function setEnvironmentMap(texture) {
  state.envMap = texture;
  if (state.scene) state.scene.environment = state.envMap;
  applyRenderProfileToObject(state.modelGroup);
}


// ── Highlight overlay material ───────────────────────────────────────────────
export const highlightMat = new THREE.MeshStandardMaterial({
  color:0x00ffff, emissive:0x004444, wireframe:false, transparent:true, opacity:0.7
});

// ── Realistic material factories ─────────────────────────────────────────────
export function makeGold() {
  const s = Math.random()*1e4;
  return new THREE.MeshPhysicalMaterial({
    color:new THREE.Color(1,.766,.336), metalness:1, roughness:.15,
    roughnessMap:genRoughnessMap(512,.15,.06,s), normalMap:genNormalMap(512,10,.25,s),
    normalScale:new THREE.Vector2(.12,.12), envMap: state.envMap, envMapIntensity:1,
    clearcoat:.3, clearcoatRoughness:.1, reflectivity:.9
  });
}

export function makeSilver(color=new THREE.Color(.95,.95,.95)) {
  const s = Math.random()*1e4;
  return new THREE.MeshPhysicalMaterial({
    color, metalness:1, roughness:.1,
    roughnessMap:genRoughnessMap(512,.1,.05,s), normalMap:genNormalMap(512,12,.2,s),
    normalScale:new THREE.Vector2(.1,.1), envMap: state.envMap, envMapIntensity:1.2,
    clearcoat:.4, clearcoatRoughness:.05, reflectivity:.95
  });
}

export function makeRoseGold() {
  const s = Math.random()*1e4;
  return new THREE.MeshPhysicalMaterial({
    color:new THREE.Color(.91,.72,.65), metalness:1, roughness:.16,
    roughnessMap:genRoughnessMap(512,.16,.06,s), normalMap:genNormalMap(512,10,.25,s),
    normalScale:new THREE.Vector2(.12,.12), envMap: state.envMap, envMapIntensity:1,
    clearcoat:.3, clearcoatRoughness:.1, reflectivity:.9
  });
}

export function makePlatinum() {
  const s = Math.random()*1e4;
  return new THREE.MeshPhysicalMaterial({
    color:new THREE.Color(.92,.92,.92), metalness:1, roughness:.08,
    roughnessMap:genRoughnessMap(512,.08,.04,s), normalMap:genNormalMap(512,14,.15,s),
    normalScale:new THREE.Vector2(.08,.08), envMap: state.envMap, envMapIntensity:1.3,
    clearcoat:.5, clearcoatRoughness:.05, reflectivity:.95
  });
}

export function makeCopper() {
  const s = Math.random()*1e4;
  return new THREE.MeshPhysicalMaterial({
    color:new THREE.Color(.72,.45,.20), metalness:1, roughness:.25,
    roughnessMap:genRoughnessMap(512,.25,.08,s), normalMap:genNormalMap(512,10,.3,s),
    normalScale:new THREE.Vector2(.15,.15), envMap: state.envMap, envMapIntensity:.9,
    clearcoat:.15, clearcoatRoughness:.2, reflectivity:.85
  });
}

export function makeDiamond(mesh) {
  const mat = new THREE.MeshPhysicalMaterial({
    color:new THREE.Color(0xffffff), metalness:0, roughness:0,
    transmission:.95, thickness:2, ior:2.42, envMap: state.envMap, envMapIntensity:2.5,
    clearcoat:1, clearcoatRoughness:0, transparent:true, opacity:1,
    specularIntensity:1.5, specularColor:new THREE.Color(0xffffff), reflectivity:1
  });
  if (mesh) mesh.material = mat;
  return mat;
}

export const GEM_PRESETS = {
  Ruby:     { color:0xE0115F, transmission:.85, ior:1.77, thickness:1.5 },
  Emerald:  { color:0x50C878, transmission:.75, ior:1.58, thickness:1.5 },
  Sapphire: { color:0x0F52BA, transmission:.88, ior:1.77, thickness:1.5 },
  Amethyst: { color:0x9966CC, transmission:.90, ior:1.55, thickness:1.5 },
  Topaz:    { color:0xFFC87C, transmission:.90, ior:1.63, thickness:1.5 },
};

export const METAL_FACTORIES = {
  Gold:        makeGold,
  'Rose Gold': makeRoseGold,
  'White Gold': () => makeSilver(new THREE.Color(.9,.9,.9)),
  Platinum:    makePlatinum,
  Silver:      makeSilver,
  Copper:      makeCopper,
};

// ── Snapshot serialization ───────────────────────────────────────────────────
export function serializeMaterial(mat) {
  return {
    type: mat?.type || 'MeshStandardMaterial',
    color: mat?.color?.getHex?.() ?? 0xaaaaaa,
    emissive: mat?.emissive?.getHex?.() ?? 0x000000,
    metalness: mat?.metalness ?? 0,
    roughness: mat?.roughness ?? 0.8,
    envMapIntensity: mat?.envMapIntensity ?? 1,
    clearcoat: mat?.clearcoat ?? 0,
    clearcoatRoughness: mat?.clearcoatRoughness ?? 0,
    transmission: mat?.transmission ?? 0,
    ior: mat?.ior ?? 1.5,
    thickness: mat?.thickness ?? 0,
    transparent: mat?.transparent ?? false,
    opacity: mat?.opacity ?? 1,
    side: mat?.side ?? THREE.FrontSide,
    wireframe: mat?.wireframe ?? false,
    flatShading: mat?.flatShading ?? false,
    depthWrite: mat?.depthWrite ?? true,
    depthTest: mat?.depthTest ?? true,
  };
}

export function materialFromParams(p = {}) {
  const ctor = p.type === 'MeshPhysicalMaterial' ? THREE.MeshPhysicalMaterial : THREE.MeshStandardMaterial;
  const mat = new ctor({
    color:p.color??0xaaaaaa, emissive:p.emissive??0x000000,
    metalness:p.metalness??0, roughness:p.roughness??0.8,
    envMap: state.envMap, envMapIntensity:p.envMapIntensity??1,
    transparent:p.transparent??false, opacity:p.opacity??1,
    side:p.side??THREE.FrontSide, wireframe:p.wireframe??false,
    flatShading:p.flatShading??false, depthWrite:p.depthWrite??true,
    depthTest:p.depthTest??true
  });
  if ('clearcoat' in mat) mat.clearcoat = p.clearcoat??0;
  if ('clearcoatRoughness' in mat) mat.clearcoatRoughness = p.clearcoatRoughness??0;
  if ('transmission' in mat) mat.transmission = p.transmission??0;
  if ('ior' in mat) mat.ior = p.ior??1.5;
  if ('thickness' in mat) mat.thickness = p.thickness??0;
  applyRenderProfileToMaterial(mat);
  mat.needsUpdate = true;
  return mat;
}
