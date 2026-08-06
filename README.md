<div align="center">

# Nova3D

**Code-native 3D generation: assets are executable programs, not opaque meshes.**

<a href="https://nova3d.xyz"><img src="https://api.iconify.design/lucide:globe-2.svg?color=%2358a6ff" width="16" height="16" align="center" alt="Website" /> website</a> · <a href="https://app.nova3d.xyz"><img src="https://api.iconify.design/lucide:box.svg?color=%2358a6ff" width="16" height="16" align="center" alt="App" /> app</a> · <a href="https://arxiv.org/abs/2607.22738"><img src="https://api.iconify.design/simple-icons:arxiv.svg?color=%23b31b1b" width="16" height="16" align="center" alt="Paper" /> paper</a> · <a href="https://discord.gg/QEH8mzcwdR"><img src="https://api.iconify.design/simple-icons:discord.svg?color=%235865f2" width="16" height="16" align="center" alt="Discord" /> discord</a> · <a href="https://x.com/nova3d_ai"><img src="https://api.iconify.design/simple-icons:x.svg?color=%238b949e" width="16" height="16" align="center" alt="X" /> X</a> · <a href="https://github.com/RareSense/Nova3D/issues"><img src="https://api.iconify.design/octicon:issue-opened-16.svg?color=%2358a6ff" width="16" height="16" align="center" alt="Issues" /> issues</a>

<br/>

<img src="app/assets/gifs/nova3d/drill_machine.gif" width="32%" />&nbsp;<img src="app/assets/gifs/nova3d/escalator.gif" width="32%" />&nbsp;<img src="app/assets/gifs/nova3d/oven.gif" width="32%" />

</div>

## What is Nova3D?

Nova3D generates 3D assets as **executable construction procedures**. Instead of emitting a single fused mesh, the pipeline writes Blender-native Python that compiles to a structured GLB with **named, separately addressable parts**, a real assembly hierarchy, joint pivots, and PBR materials.

The asset's source of truth is the program; the mesh is just its compiled output. Because anything coded is programmable, every generated object is born **inspectable, addressable, editable, and animatable**; properties a baked mesh cannot natively expose.

This is architecturally different from diffusion-based generators (Meshy, Tripo, Rodin), which extract a single merged mesh with no part boundaries, and from CSG/OpenSCAD systems, which guarantee solids but cap out on organic shapes, hierarchy, and materials. Nova3D uses Blender's scene graph as the native representation, a strict superset of both.


## Getting started

The web client lives in [`app/`](app/) and connects to the hosted Nova3D service; no local backend required. See **[`app/README.md`](app/README.md)** for prerequisites, setup, features, and troubleshooting.


## Repository structure

This repository is the home for Nova3D's open clients and integrations. The hosted generation backend is (currently) closed-source.

```
Nova3D/
├── app/              # Flutter/Dart web client  ·  see app/README.md
├── mcp/              # Nova3D MCP server  ·  see mcp/README.md
├── blender-plugin/   # Blender plugin (coming soon)
├── claude-skills/    # Claude skills (coming soon)
├── docs/             # architecture & the "3D as code" thesis (coming soon)
└── examples/         # gallery of generated assets + their source programs (coming soon)
```

> Surfaces are being moved in one at a time. Today the **client app** lives in [`app/`](app/).

## Demo

<div align="center">

<a href="https://www.youtube.com/watch?v=309zNw0JETU"><img src="docs/media/demo_one_shot.png" width="100%" alt="Nova3D one-shot 3D model generation demo" /></a>

☝️ One shot: **3D models with 4K PBR textures, ready for games, animation, VFX, and more with Nova3D**

</div>

## Comparison

[![Nova3D vs TRELLIS vs Hunyuan3D](https://i.imgur.com/QAAgIQ8.png)](https://www.youtube.com/watch?v=iL_NX_hBq9k)

☝️ Side-by-side with TRELLIS and Hunyuan3D. Nova3D is optimized for **structured asset generation**, but the advantage is not limited to multipart editing; it also shows stronger single-asset fidelity: cleaner silhouette control, sharper feature delineation, and more coherent surface transitions. **Explicit part structure is an added capability, not a quality tradeoff.**

[![Nova3D vs PartPacker vs Tripo Segmentation](https://i.imgur.com/wWjVuRr.png)](https://www.youtube.com/watch?v=msGZs4EMnvs)

☝️ Part-aware comparison with NVIDIA PartPacker and Tripo. Nova3D preserves discrete components as independently addressable objects with stable boundaries, clearer instance separation, and better **edit locality**; assets stay actionable after generation (inspect, regenerate, restyle, articulate, export) without collapsing back into one undifferentiated mesh.

### Visual fidelity: same prompt vs the mesh-native generators

<div align="center"><img src="docs/media/comparison_slider.gif" width="100%" alt="Animated textured and wireframe comparison: Nova3D vs Meshy, TRELLIS.2, and TripoSG" /></div>

*Textured, as delivered: Nova3D vs the mesh-native generators (Meshy, TRELLIS.2, TripoSG).*

*Wireframe (mesh topology). Nova3D builds clean parts; internal structure is visible; the diffusion models output dense isosurface meshes.*

## Anatomy of a generation

<div align="center"><img src="docs/media/anatomy_ring.jpg" width="100%" alt="Measured gold engagement ring generated by Nova3D" /></div>

☝️ Prompt: Create a gold engagement ring with an **oval center stone measuring 6.82 × 8.75 × 4.40 mm**, raised prong setting, and small pavé diamonds along the upper band. Use a **17.00 mm inner diameter (US size 6.5)**, **6.22 mm crown height**, **20.96 mm overall width**, and **26.42 mm overall height**.

Every visually distinct component is its own named, editable mesh, grouped into named sub-assemblies, and prompt-stated counts and dimensions hold up when measured back from the result.

### Built as parts, not segmented after the fact

<div align="center"><img src="docs/media/segmentation_explode.gif" width="78%" alt="Four assets exploded into their parts" /></div>

*Nova3D never builds a fused mesh in the first place; every component is generated as its own named, watertight part, so any piece can be selected, retextured, replaced, or rigged on its own. The others can only approximate this afterward: PartCrafter returns a handful of unnamed chunks, and CubePart must be handed the part names, then slices a finished mesh into capped, approximate regions. *

## Assembly hierarchy

<div align="center"><img src="docs/media/assembly_hierarchy.gif" width="100%" alt="Building exported as a labeled assembly hierarchy" /></div>

*Parts don't just have names; they're wired into a labeled assembly tree with a joint pivot at every articulation point. This robot arm exports as a depth-7 kinematic chain: rotating any pivot moves its whole subtree. The program writes that tree itself; mesh generators export a flat list with nothing to grab or rig.*

## Articulation

<div align="center"><img src="docs/media/articulation_crane.gif" width="100%" alt="Tracked crane articulating, geometry frozen" /></div>

*Rigging is an additive code pass: joints are added at real pivots referencing parts the program already named; the existing geometry never moves.*

## UV-ready from the source

<div align="center"><img src="docs/media/uv_from_code.png" width="100%" alt="Auto-generated clean, packed UV atlas for a generated asset" /></div>

*Each part gets its own UV chart, auto-packed into one clean, non-overlapping atlas grouped by sub-assembly.*

## Technical philosophy

**1. Script-native, not mesh-native.** Most AI 3D generators do image-to-3D diffusion. Nova3D is prompt-to-code / image-to-code, targeting Blender's API, which yields a logical named hierarchy, surgical edits (change the handle without regenerating the cup), and proper PBR materials instead of baked vertex colors.

**2. Model-agnostic.** Nova3D is a generation harness. Swap providers (OpenRouter, OpenAI, Anthropic, Gemini) via the settings menu; the pipeline handles validation and execution regardless of which LLM writes the code.

**3. Precision + organic flow.** Unlike pure CSG/OpenSCAD systems that struggle with organic shapes, Nova3D leverages Blender's full modifier suite (subdivision, sculpting, booleans) for high-fidelity models.


## License

[MIT](LICENSE) © RareSense. The clients and integrations in this repository are open-source; the hosted generation backend is proprietary.

<p align="center">
  <small>Built on the same engine powering <b><a href="https://formanova.ai">FormaNova</a></b> for specialized jewelry CAD.</small>
</p>
