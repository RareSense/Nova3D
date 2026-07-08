import * as THREE from 'three';

// Color-code a model that ships NO colour at all — no textures, no COLOR_0
// vertex colours, and only the glTF default (white / fully-metallic) material.
// Such a model would otherwise render as a grey metallic blob; giving each part
// a distinct colour makes an untextured generation read as a clean, structured
// model. Any model that already carries colour (textures, vertex colours, or a
// tinted material) is left completely untouched.
//
// Returns true if it recoloured, false if the model was left as-is.
export function colorizeIfUncolored(root) {
  if (!root) return false;
  const meshes = [];
  let hasColour = false;

  root.traverse((n) => {
    if (!n.isMesh) return;
    meshes.push(n);
    const attrs = n.geometry && n.geometry.attributes;
    if (attrs && attrs.color) hasColour = true;
    for (const m of Array.isArray(n.material) ? n.material : [n.material]) {
      if (!m) continue;
      if (m.map || m.emissiveMap || m.vertexColors) hasColour = true;
      const c = m.color;
      // A non-near-white base colour means the author tinted this part.
      if (c && !(c.r > 0.92 && c.g > 0.92 && c.b > 0.92)) hasColour = true;
    }
  });

  if (hasColour || !meshes.length) return false;

  // Distinct hues via the golden-ratio increment so neighbours never collide.
  meshes.forEach((mesh, i) => {
    const color = new THREE.Color().setHSL((i * 0.61803398875) % 1, 0.55, 0.62);
    mesh.material = new THREE.MeshStandardMaterial({ color, metalness: 0.0, roughness: 0.65 });
  });
  return true;
}
