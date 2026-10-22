# Programmable Indoor Environments from SceneSmith Prompts

**20 indoor simulation environments generated with [Nova3D](https://nova3d.xyz/robotics) from the original natural-language descriptions in [SceneSmith’s released scene dataset](https://huggingface.co/datasets/nepfaff/scenesmith-example-scenes).** Each environment includes editable scene source, semantic and spatial annotations, articulated mechanisms, physical properties, and native simulator exports.

[SceneSmith](https://scenesmith.github.io/) studies simulation-ready indoor scene generation from natural language. Nova3D generates these environments as procedural programs from the same descriptions. Shared scene IDs connect the two sets of outputs; SceneSmith images and meshes were not supplied as generation inputs.

The collection covers four living rooms, three dining rooms, two bedrooms, two kitchens, two recreation rooms, and seven specialized settings: an artist studio, laboratory, library, dental office, server room, grooming salon, and bakery. Generation used **GPT-6 Astra**.

**[Dataset and downloads on Hugging Face](https://huggingface.co/datasets/BoooomNing/nova-scenesmith)** · **[SceneSmith paper](https://arxiv.org/abs/2602.09153)**

## Contributions

| Component | Released content |
|---|---|
| Shared descriptions | Original prompts and SceneSmith scene identifiers for paired inspection. |
| Editable source | Scene programs, design specifications, and parameters. |
| Semantic and spatial annotations | Part identities, classes, bounds, and dimensions. |
| Articulation and physics | Joint pivots, axes, limits, body properties, and collision geometry. |
| Simulator exports | USD, MuJoCo MJCF, Gazebo SDF, and PyBullet resources. |
| Visual assets | GLB scenes, rendered views, materials, and textures. |

## Access

The Hugging Face release provides an interactive scene table and a complete ZIP for each environment, preserving mesh and texture dependencies. It also includes individual source and annotation files, download instructions, and attribution.
