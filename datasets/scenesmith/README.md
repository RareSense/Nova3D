# Procedural Indoor Environments for Robot Simulation

[Nova3D Website](https://nova3d.xyz) · [Open Nova Studio](https://studio.nova3d.xyz)

**20 indoor scenes generated with [Nova3D](https://nova3d.xyz/robotics) from the text descriptions released with [SceneSmith](https://scenesmith.github.io/). The collection provides procedural Python scene programs, part-level annotations, physical properties, and simulator exports.**

[SceneSmith (ICML 2026)](https://proceedings.mlr.press/v306/pfaff26a.html), by **Nicholas Pfaff, Thomas Cohn, Sergey Zakharov, Rick Cory, and Russ Tedrake** at **MIT and Toyota Research Institute**, releases both scene descriptions and generated environments. Here, **the same description is paired with two independently generated scenes: the original SceneSmith output and a Nova3D output**. Nova received only the text description. The original SceneSmith scene files are linked separately for comparison.

The collection covers **four living rooms, three dining rooms, two bedrooms, two kitchens, two recreation rooms, and seven specialized settings**: an artist studio, laboratory, library, dental office, server room, pet grooming salon, and bakery. All 20 Nova scenes were generated with **GPT-6 Astra**.

## Contributions

| Released content | Purpose |
|---|---|
| Per-scene Python source | Edit geometry, layout, materials, and physical parameters in the scene program. |
| Part labels, IDs, bounds, and dimensions | Inspect scene structure and spatial relationships. |
| Joint and body annotations | Inspect pivots, axes, limits, masses, inertias, and contact properties. |
| USD, MJCF, SDF, GLB, and PyBullet files | Use the generated scenes in simulation and visualization tools. |
| Matched SceneSmith outputs and original descriptions | Compare both systems against the same requested scene content. |

## Comparison with SceneSmith

**Articulation appears in 18 of the 20 Nova scenes, compared with 11 SceneSmith scenes generated from the same descriptions.**

![Articulation coverage: SceneSmith 11/20; Nova3D 18/20.](figures/articulation-coverage.png)

The graph counts scenes with declared hinge or slide joints. [See every scene's results and the release comparison](COMPARISON.md). Each row's `scenesmith_output` link provides the corresponding original scene.

## Access

**[Dataset and downloads](https://huggingface.co/datasets/BoooomNing/nova-scenesmith)** · **[Paired-scene comparison](COMPARISON.md)**

Each Nova scene ZIP includes its source, input prompt, annotations, and simulator files with mesh and texture dependencies. The dataset table also links directly to the corresponding original SceneSmith archive.
