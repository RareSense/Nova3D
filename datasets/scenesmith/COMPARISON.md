# Comparison of the 20 matched scenes

Each pair has the **same input description and scene ID**, with independently generated SceneSmith and Nova3D outputs. The original SceneSmith archives are downloadable; no rerun of SceneSmith is needed to inspect these pairs.

## Released representations

The counts below refer to the selected 20 archives, not every capability of either system.

| Content | SceneSmith | Nova3D |
|---|---|---|
| Scene authoring and editing | Blender scene and declarative model placement in all 20; the generator is also open source | Generated Python scene program in all 20; no `.blend` supplied |
| Scene assembly | Drake DMD model instances, frames, placements, and welds | Named parts, semantic classes, bounds, static/moving state, and body declarations |
| Explicit annotation files | Names, transforms, and physics in native scene files; prompt requirements in the shared CSV | Five JSON files per scene: parts, measurements, articulation, physics, materials |
| Collision geometry and body properties | SDF/MJCF collision geometry, mass/inertia, friction, and joint declarations | SDF/MJCF/USD collision geometry and physical declarations, also exposed in JSON |
| Revolute/prismatic joints | 87 scalar joint instances across 11 scenes | 93 hinge/slide parts across 18 scenes |
| MJCF mechanism hierarchy | All 87 scalar joints belong to bodies nested inside parent bodies | All 93 scalar joints belong to bodies directly under the world; these files do not encode moving-parent articulation chains |
| Free bodies in MJCF | 1,070 free joints across the 20 files | 1,341 free joints across the 20 files |
| MuJoCo | Whole-scene MJCF in 20/20 | Whole-scene MJCF in 20/20 |
| USD | Scene and supporting layers in 20/20 | `environment.usda` in 20/20 |
| SDF | Asset/room models assembled through Drake DMD; some asset files contain a world wrapper | `model.sdf` and assembled `world.sdf` in 20/20 |
| Drake | Scene DMD and furniture-welded variant in 20/20 | No Drake DMD in these packages |
| PyBullet | No dedicated runner in the selected archives | Scene JSON and runner in 20/20 |
| Browser geometry | glTF asset meshes; no whole-scene GLB in the selected archives | Whole-scene GLB in 20/20 |
| Appearance | Mesh textures and explicit MJCF material/texture declarations | Mesh textures in the package; the MJCF files use per-geometry RGBA and have no material/texture declarations |
| Prompt annotations | Original object counts, attributes, object-object and object-anchor relations | The same requirements apply to the paired Nova outputs and are included in the comparison records |

**More parts or joints is not automatically better.** SceneSmith model instances and Nova mesh parts use different grouping. Joint counts describe what was authored, not whether all requested mechanisms were built or operate successfully. Material files describe available appearance data, not visual quality.

## Per-scene articulation

Scalar joints are revolute/prismatic joints in the assembled SceneSmith SDF assets and hinge/slide joints in Nova's declarations. Counts also agree with each scene's MJCF. This checks counts only; it does not establish identical dynamics across exports.

| Scene ID | Environment | SceneSmith joints | Nova joints |
|---|---|---:|---:|
| [scene_034](https://huggingface.co/datasets/BoooomNing/nova-scenesmith/blob/main/comparison/scenes/scene_034.json) | Dining room with central bar table | 17 | 5 |
| [scene_182](https://huggingface.co/datasets/BoooomNing/nova-scenesmith/blob/main/comparison/scenes/scene_182.json) | Pop Art artist studio | 0 | 1 |
| [scene_051](https://huggingface.co/datasets/BoooomNing/nova-scenesmith/blob/main/comparison/scenes/scene_051.json) | Bedroom with wardrobe | 6 | 7 |
| [scene_029](https://huggingface.co/datasets/BoooomNing/nova-scenesmith/blob/main/comparison/scenes/scene_029.json) | Living room with bookshelves | 0 | 1 |
| [scene_178](https://huggingface.co/datasets/BoooomNing/nova-scenesmith/blob/main/comparison/scenes/scene_178.json) | Minecraft-themed gaming room | 0 | 2 |
| [scene_036](https://huggingface.co/datasets/BoooomNing/nova-scenesmith/blob/main/comparison/scenes/scene_036.json) | Dining room with six chairs | 0 | 0 |
| [scene_147](https://huggingface.co/datasets/BoooomNing/nova-scenesmith/blob/main/comparison/scenes/scene_147.json) | Science laboratory | 4 | 4 |
| [scene_089](https://huggingface.co/datasets/BoooomNing/nova-scenesmith/blob/main/comparison/scenes/scene_089.json) | Basement gaming room | 3 | 5 |
| [scene_064](https://huggingface.co/datasets/BoooomNing/nova-scenesmith/blob/main/comparison/scenes/scene_064.json) | Kitchen with bistro table | 6 | 10 |
| [scene_028](https://huggingface.co/datasets/BoooomNing/nova-scenesmith/blob/main/comparison/scenes/scene_028.json) | Living room with sofa and television | 0 | 2 |
| [scene_017](https://huggingface.co/datasets/BoooomNing/nova-scenesmith/blob/main/comparison/scenes/scene_017.json) | Dining room with wine cabinets | 12 | 7 |
| [scene_119](https://huggingface.co/datasets/BoooomNing/nova-scenesmith/blob/main/comparison/scenes/scene_119.json) | Library with reading tables | 0 | 4 |
| [scene_125](https://huggingface.co/datasets/BoooomNing/nova-scenesmith/blob/main/comparison/scenes/scene_125.json) | Dental office | 4 | 6 |
| [scene_024](https://huggingface.co/datasets/BoooomNing/nova-scenesmith/blob/main/comparison/scenes/scene_024.json) | Teenager bedroom with workstation | 11 | 10 |
| [scene_135](https://huggingface.co/datasets/BoooomNing/nova-scenesmith/blob/main/comparison/scenes/scene_135.json) | Server room | 0 | 4 |
| [scene_056](https://huggingface.co/datasets/BoooomNing/nova-scenesmith/blob/main/comparison/scenes/scene_056.json) | Living room with vintage typewriter | 4 | 0 |
| [scene_142](https://huggingface.co/datasets/BoooomNing/nova-scenesmith/blob/main/comparison/scenes/scene_142.json) | Pet grooming salon | 2 | 4 |
| [scene_161](https://huggingface.co/datasets/BoooomNing/nova-scenesmith/blob/main/comparison/scenes/scene_161.json) | Living room with coffee table | 0 | 3 |
| [scene_138](https://huggingface.co/datasets/BoooomNing/nova-scenesmith/blob/main/comparison/scenes/scene_138.json) | Bakery | 0 | 4 |
| [scene_084](https://huggingface.co/datasets/BoooomNing/nova-scenesmith/blob/main/comparison/scenes/scene_084.json) | Kitchen with bar seating | 18 | 14 |

## Evidence and definitions

[Paired-scene CSV](https://huggingface.co/datasets/BoooomNing/nova-scenesmith/resolve/main/comparison/paired-scenes.csv) contains download links and per-scene measurements. Each scene ID above opens a JSON record with the shared prompt and its requirements, SceneSmith model names and placements, native joint/link declarations, Nova part and joint records, export counts, and source hashes.

- `scenesmith_dmd_model_instances`: all `add_model` entries, including architecture and repeated asset instances. This is not a count of unique asset files.
- `nova_labeled_parts`: exported pieces in `parts.json`; one inventory object may contain several pieces. Do not compare this directly with the DMD instance count as object-count accuracy.
- `*_scalar_joints` / `*_scalar_joint_instances`: hinge/revolute or slide/prismatic declarations, excluding fixed and free joints. Source SDF counts include repeated instances.
- `*_free_joints`: free-body declarations in MJCF. They are not door or drawer joints.
- `*_joints_on_nested_bodies` and `*_joints_on_world_children`: whether the joint's body is nested in another body or directly attached to the MJCF world. These counts describe hierarchy, not motion quality.
- Boolean format columns mean a corresponding file is present. They do not mean a simulator task was passed. `scenesmith_glb` checks any GLB in the archive; `nova_scene_glb` checks the assembled scene GLB.
- `scenesmith_asset_world_wrappers`: at least one asset SDF contains a `<world>` wrapper. It does not mean an assembled room is available as a Gazebo world.
- `*_texture_images` counts image files, not distinct materials or appearance quality. SceneSmith's count covers the archive; Nova's covers `simulation/textures/`.
- `*_mjcf_materials` counts explicit MJCF material declarations. Nova's per-geometry RGBA colors are a different representation.
- `scenesmith_metadata_json_files` counts JSON files in the original archive. Zero does not mean absent semantics or physics: those are represented in its native files.
- `nova_annotation_json_files` counts the five released annotation files per scene.
- `*_scene_python` checks Python files in the selected archive versus Nova's `source/asset.py`. The absence of per-scene Python in a SceneSmith archive does not mean its generator code is unavailable.

## Inspection method

The original archives are pinned to `5425b6ac0ee7d5043af75f9ec78494cf5c94f3ca`. We inspected all 20 archive manifests, parsed their Drake scene descriptions and referenced SDF models, and parsed both releases' MJCF files. Source hashes were checked before inspection. Files excluded from the local parser staging, including `.blend`, were counted from the complete archive manifests. No scene programs were executed for this comparison.

This release comparison does not report image-quality scores, prompt-adherence scores, collision-free motion, or robot-task success. Those require separate evaluation; neither generated scene is reference truth. Model and budget differences also prevent attributing a measured difference to the generator alone.

## Retrieve a matched pair

```python
from huggingface_hub import hf_hub_download

scene_id = "scene_034"
original = hf_hub_download(
    "nepfaff/scenesmith-example-scenes", f"Room/{scene_id}.tar",
    repo_type="dataset", revision="5425b6ac0ee7d5043af75f9ec78494cf5c94f3ca",
)
nova = hf_hub_download(
    "BoooomNing/nova-scenesmith", f"archives/{scene_id}.zip",
    repo_type="dataset", revision="v1.0.0",
)
```

For the original SceneSmith scene, the entrypoints are `combined_house/house.blend`, `combined_house/house.dmd.yaml`, and `mujoco/scene.xml`. For Nova, see the [dataset's simulator entrypoints](https://huggingface.co/datasets/BoooomNing/nova-scenesmith#download). Preserve each archive's directory structure and dependencies.

[SceneSmith project](https://scenesmith.github.io/) · [Original dataset](https://huggingface.co/datasets/nepfaff/scenesmith-example-scenes) · [SceneSmith generator](https://github.com/nepfaff/scenesmith)
