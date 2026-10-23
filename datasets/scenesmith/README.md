# Text-to-Scene Environments for Embodied AI

[Nova3D Website](https://nova3d.xyz) · [Open Nova Studio](https://studio.nova3d.xyz)

**20 indoor simulation environments generated with [Nova3D](https://nova3d.xyz/robotics) from descriptions released with [SceneSmith](https://scenesmith.github.io/), with editable scene programs, object and part annotations, articulated mechanisms, and native simulator exports.**

[SceneSmith: Agentic Generation of Simulation-Ready Indoor Scenes](https://proceedings.mlr.press/v306/pfaff26a.html) (ICML 2026), by **Nicholas Pfaff, Thomas Cohn, Sergey Zakharov, Rick Cory, and Russ Tedrake** at **MIT and Toyota Research Institute**, investigates natural-language generation of environments for robot simulation. This collection contributes Nova3D outputs for 20 of its released descriptions, retaining the original prompt text and scene IDs.

Nova3D generates and executes procedural code to construct the rooms, furnishings, materials, and mechanisms. Each release connects the description to its generated program, exported geometry, annotations, and simulation files, allowing researchers to inspect and modify how a scene was constructed.

The collection covers **four living rooms, three dining rooms, two bedrooms, two kitchens, two recreation rooms, and seven specialized settings**: an artist studio, laboratory, library, dental office, server room, pet grooming salon, and bakery.

## Contributions

| Contribution | Released content | Research Applications |
|---|---|---|
| Common-prompt scene collection | 20 original descriptions with IDs linking to SceneSmith's published outputs. | Examine object coverage and spatial arrangements for the same scene request. |
| Procedural scene representation | Generated Python source and design specifications alongside the resulting assets. | Inspect construction logic and edit geometry, layouts, and physical parameters. |
| Semantic and spatial annotations | Object and part identities, labels, bounds, positions, and dimensions. | Check requested counts and relationships; measure clearance and relative placement. |
| Articulated and rigid-body structure | Joint pivots, axes, limits, collision geometry, and body/contact properties. | Construct opening, closing, and object-interaction experiments. |
| Native simulation assets | USD, MJCF, SDF, and PyBullet files with mesh and texture dependencies. | Load the same generated environment in different simulation workflows. |

## Inputs and correspondence

Each Nova3D generation used **GPT-6 Astra** and the original text description. Scene IDs retain the upstream mapping; SceneSmith geometry and images were not generation inputs. [Prompt provenance and selection](https://huggingface.co/datasets/BoooomNing/nova-scenesmith/blob/main/docs/PROVENANCE.md) records the sample and source revision.

For example, [`scene_034`](https://huggingface.co/datasets/BoooomNing/nova-scenesmith/blob/main/scenes/scene_034/inputs/scene-description.txt) requests a dining room with a central bar table, a wall shelf holding a plant and jug, a fridge, and a wine cabinet. Its [scene source](https://huggingface.co/datasets/BoooomNing/nova-scenesmith/blob/main/scenes/scene_034/source/asset.py) and [annotations](https://huggingface.co/datasets/BoooomNing/nova-scenesmith/blob/main/scenes/scene_034/metadata/parts.json) let researchers inspect the resulting objects, arrangement, and mechanisms.

The common descriptions support paired inspection of Nova3D and SceneSmith outputs. A controlled method comparison additionally requires matched generation budgets and a shared evaluation protocol.

## Access

**[Dataset and downloads on Hugging Face](https://huggingface.co/datasets/BoooomNing/nova-scenesmith)** · **[SceneSmith project](https://scenesmith.github.io/)** · **[ICML paper](https://proceedings.mlr.press/v306/pfaff26a.html)**

Browse the scene table or download a complete ZIP per environment. Each archive includes the source program, original description, annotations, and simulator files with their relative dependencies.
