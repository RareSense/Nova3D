# Datasets

Nova3D reconstructs scenes as editable programs that define geometry, semantic labels, articulated mechanisms, and physical properties. Our dataset releases provide these programs alongside simulation assets, annotations, reconstruction inputs, and material resources for research.

## Contributions

Available content and formats are specified per collection.

| Contribution | Dataset content | Research Applications |
|---|---|---|
| Object and part decomposition | Identified geometry, object inventories, and component relationships. | Select, move, replace, or remove individual components. |
| Semantic annotations | Part names, semantic classes, and instance references linked to geometry. | Associate observations and task targets with identified entities. |
| Spatial annotations | Bounds, dimensions, positions, and scene measurements. | Analyze size, clearance, and spatial relationships. |
| Articulated mechanisms | Hinged and sliding parts with pivots, axes, travel limits, and damping. | Study motion, constraints, and interaction. |
| Physical properties | Collision geometry, mass, inertia, friction, and restitution. | Simulate contact and motion; vary physical parameters. |
| Editable source | Geometry programs and design specifications alongside assets. | Inspect construction logic and create controlled geometry and layout variants. |
| Native exports | Files for simulation and visualization tools. | Use assets across supported applications. |
| PBR appearance | Surface materials, textures, and scene assets. | Configure appearance and lighting for rendering experiments. |
| Construction records | Inputs, source, inventories, parameter declarations, and file hashes. | Inspect provenance and reproduce configurations. |

## Released collections

| Collection | Scope | Access |
|---|---|---|
| [Nova3D-Bench (preview)](https://huggingface.co/datasets/raresense/nova3d-bench-preview) | Benchmark used in *Nova3D: Code-Native Generation of Programmable 3D Assets*: 54 prompts across six domains and three difficulty levels, with text and image conditioning, output previews from 13 pipelines, and available generated source code. | [Hugging Face](https://huggingface.co/datasets/raresense/nova3d-bench-preview) |
| [Interactive Real-to-Sim Environments for Embodied AI](wanderland/) | 20 outdoor environments reconstructed from [Wanderland](https://ai4ce.github.io/wanderland/) observations, with object and part annotations, articulated joints, contact physics, PBR materials, and native simulator exports. | [Hugging Face](https://huggingface.co/datasets/raresense/nova-wanderland) |

Each collection page describes its inputs, annotations, available formats, and attribution. Scene files and downloads are hosted on Hugging Face.
