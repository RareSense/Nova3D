import * as THREE from 'three';

// Color-code a model that ships no REAL colour — no textures, no tinted
// materials, and no chromatic vertex colours. Such a model would otherwise
// render as a grey blob; giving each part a distinct colour makes an
// untextured generation read as a clean, structured model.
//
// An ACHROMATIC COLOR_0 attribute (r≈g≈b on every vertex) does NOT count as
// colour: the pipeline bakes ambient-occlusion into vertex colours, which is
// pure shading. Those meshes still get per-part colours; when the AO layer is
// present it multiplies into the tint (colour + baked depth), and meshes with
// no colour attribute at all get the plain flat tint.
// Any model that carries real colour is left completely untouched.
//
// Returns true if it recoloured, false if the model was left as-is.

function attributeIsChromatic(attr) {
  const count = attr.count;
  const stride = Math.max(1, Math.floor(count / 200));
  const denorm = attr.normalized && attr.array && attr.array.BYTES_PER_ELEMENT === 1 ? 255 : 1;
  for (let i = 0; i < count; i += stride) {
    let r = attr.getX(i), g = attr.getY(i), b = attr.getZ(i);
    if (denorm !== 1 && (r > 1 || g > 1 || b > 1)) { r /= denorm; g /= denorm; b /= denorm; }
    const mx = Math.max(r, g, b), mn = Math.min(r, g, b);
    if (mx - mn > 0.04) return true;   // real hue, not grayscale shading
  }
  return false;
}

export function colorizeIfUncolored(root) {
  if (!root) return false;
  const meshes = [];
  let hasColour = false;

  root.traverse((n) => {
    if (!n.isMesh) return;
    meshes.push(n);
    const attrs = n.geometry && n.geometry.attributes;
    if (attrs && attrs.color && attributeIsChromatic(attrs.color)) hasColour = true;
    for (const m of Array.isArray(n.material) ? n.material : [n.material]) {
      if (!m) continue;
      if (m.map || m.emissiveMap) hasColour = true;
      const c = m.color;
      // A non-near-white base colour means the author tinted this part.
      if (c && !(c.r > 0.92 && c.g > 0.92 && c.b > 0.92)) hasColour = true;
    }
  });

  if (hasColour || !meshes.length) return false;

  applyColorCoding(meshes, 0.55, 0.62);
  return true;
}

// Force per-part colour-coding on EVERY mesh, ignoring the model's own
// materials — used for the rings tab, where we deliberately show FORM and part
// decomposition in soft pastels instead of the gold / pearl / gem materials the
// ring code produced. Unlike colorizeIfUncolored this always recolours.
export function colorizePastel(root) {
  if (!root) return false;
  const meshes = [];
  root.traverse((n) => { if (n.isMesh) meshes.push(n); });
  if (!meshes.length) return false;
  // Pastel = high lightness, gentle saturation. Sits well on the gallery's
  // lilac→pink→cream backdrop.
  applyColorCoding(meshes, 0.50, 0.80);
  return true;
}

// Distinct hues via the golden-ratio increment so neighbours never collide.
// vertexColors only when the mesh actually carries the (achromatic AO)
// attribute — it multiplies the baked shading into the tint. Meshes without
// it get the plain flat tint.
function applyColorCoding(meshes, saturation, lightness) {
  meshes.forEach((mesh, i) => {
    const color = new THREE.Color().setHSL((i * 0.61803398875) % 1, saturation, lightness);
    const attrs = mesh.geometry && mesh.geometry.attributes;
    mesh.material = new THREE.MeshStandardMaterial({
      color,
      metalness: 0.0,
      roughness: 0.65,
      vertexColors: !!(attrs && attrs.color),
    });
  });
}
