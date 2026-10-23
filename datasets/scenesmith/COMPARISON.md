# Programmable scene construction and interaction

**Nova releases the construction program alongside each simulation environment.** Researchers can change room and furniture geometry, identify individual parts through semantic and physical annotations, and configure how objects move and interact. The source covers the assembled scene, including its layout, materials and mechanisms.

This collection uses 20 descriptions from [SceneSmith](https://scenesmith.github.io/). Corresponding SceneSmith outputs are linked for each scene, providing a reference for comparing the released representations.

## Released representations

| Research resource | SceneSmith outputs | Nova3D outputs |
|---|---|---|
| **Scene construction** | Blender scenes and declarative assembly files | A Python construction program for every scene, including geometry, layout, materials and mechanisms |
| **Geometry controls** | Native scene and asset editing | Source constants and functions defining room, furniture and mechanism dimensions |
| **Part annotations** | Named models, transforms and native asset structures | Dedicated JSON records for part IDs, semantic classes, bounds, dimensions and physical bodies |
| **Interaction structure** | Articulated assets and free bodies in simulator files | Articulated parts and free bodies, linked to part-level geometry and physical records |
| **Physical parameters** | Native joint and body properties | Native properties plus separate annotations for inspecting and changing physical behavior |
| **Simulation and inspection** | Drake scene descriptions, MJCF, USD, SDF assets and Blender files | MJCF, USD, an assembled SDF world, a PyBullet scene runner and whole-scene GLB |

## Change the construction, not just the placement

In the dining-room source, room dimensions, table size, shelf width and refrigerator width are explicit construction values. Researchers can revise the geometry at its source rather than treating each exported mesh as a fixed asset. The same program defines the furniture components, materials and mechanisms.

![Room geometry and its construction constants in the released source.](media/procedural-source.png)

[Dining-room source program](https://huggingface.co/datasets/BoooomNing/nova-scenesmith/blob/main/scenes/scene_034/source/asset.py)

## Connect task targets to scene parts

The dining room includes refrigerator doors, wine-cabinet doors, a serving drawer, movable stools and tableware. Part IDs connect their semantic labels, dimensions and physical records. This structure lets researchers select a particular door or object, locate its pivot and motion axis, and inspect the properties relevant to an interaction task.

![Scene parts and the refrigerator door's semantic and physical records.](media/parts-and-physics.png)

[Part annotations](https://huggingface.co/datasets/BoooomNing/nova-scenesmith/blob/main/scenes/scene_034/metadata/parts.json) · [Joint annotations](https://huggingface.co/datasets/BoooomNing/nova-scenesmith/blob/main/scenes/scene_034/metadata/articulation.json)

## Vary physical behavior under a fixed action

A drawer in the released studio scene provides a reproducible example. With the same **15.8 N applied force**, changing its travel limit or friction produces three measured responses:

| Configuration | Drawer travel after 1 second |
|---|---:|
| Original configuration | **36 cm** |
| Travel limit reduced to 18 cm | **18 cm** |
| Joint friction increased to 20 N | **0.6 cm** |

![Drawer motion replayed from the measured simulation trajectories.](media/drawer-variation.gif)

![Measured drawer travel under three physical configurations.](media/controlled-physics.png)

This experiment runs in the complete released MuJoCo scene. It illustrates how physical parameters can be varied while holding the scene and applied action fixed—a useful setup for sensitivity studies and task design.

[Run the experiment](https://huggingface.co/datasets/BoooomNing/nova-scenesmith/blob/main/examples/README.md) · [Download the measurements](https://huggingface.co/datasets/BoooomNing/nova-scenesmith/blob/main/examples/parameter-sweep.csv)

## Continue editing an existing environment

[Nova Studio](https://studio.nova3d.xyz) provides a natural-language interface for revising scene source. Example editing requests include:

- Change the central table's width while retaining seating clearance.
- Shorten a drawer's travel and increase its resistance.
- Move a cabinet while preserving its opening direction.

The released source provides the construction record for continued editing of geometry, layout, appearance and mechanisms.

## Supporting measurements

<details>
<summary>Articulation measurements for all 20 scene pairs</summary>

The MJCF files contain hinge/slide joints in 18 Nova scenes and revolute/prismatic joints in 11 SceneSmith scenes, totaling 93 and 87 joints respectively. Both releases include articulated assets. The plots retain every selected pair.

![Articulation coverage across the 20 scenes.](figures/articulation-coverage.png)

![Joint counts for all 20 scene pairs.](figures/paired-joint-counts.png)

[Per-scene measurements](https://huggingface.co/datasets/BoooomNing/nova-scenesmith/resolve/main/comparison/paired-scenes.csv) · [File inspection](FILE_INSPECTION.md)

</details>

<details>
<summary>Paired scene inspection views</summary>

![SceneSmith and Nova environments for the first three selected descriptions.](media/paired-scenes.png)

The first three pairs retain their original scene IDs. SceneSmith views use MJCF in MuJoCo; Nova views use GLB in Blender, with ceilings hidden for inspection.

</details>

<details>
<summary>Measurement protocol and provenance</summary>

File inspection covers all 20 pairs. Counts describe native declarations, not task-success scores; mesh parts, inventory objects and free joints are distinct units. The generations used different models and budgets. The drawer experiment applies force directly to the joint and measures the response for one second; it does not measure robot-policy performance. The animation replays the measured coordinates. Natural-language requests above illustrate the editing interface rather than additional experiment runs.

[Selection and provenance](https://huggingface.co/datasets/BoooomNing/nova-scenesmith/blob/main/docs/PROVENANCE.md) · [Experiment settings and reproduction](https://huggingface.co/datasets/BoooomNing/nova-scenesmith/blob/main/examples/README.md) · [Complete file inspection](FILE_INSPECTION.md)

</details>
