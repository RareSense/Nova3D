<div align="center">

<a href="https://app.nova3d.xyz"><img src="docs/media/robotics/banner.svg" width="100%" alt="Nova3D Robotics: worlds for robots, written as code" /></a>

<a href="https://nova3d.xyz"><img src="https://api.iconify.design/lucide:globe-2.svg?color=%230e1013" width="16" height="16" align="center" alt="Website" /> website</a> · <a href="https://app.nova3d.xyz"><img src="https://api.iconify.design/lucide:box.svg?color=%230e1013" width="16" height="16" align="center" alt="App" /> open studio</a> · <a href="https://arxiv.org/abs/2607.22738"><img src="https://api.iconify.design/simple-icons:arxiv.svg?color=%23b31b1b" width="16" height="16" align="center" alt="Paper" /> paper</a> · <a href="https://discord.gg/QEH8mzcwdR"><img src="https://api.iconify.design/simple-icons:discord.svg?color=%235865f2" width="16" height="16" align="center" alt="Discord" /> discord</a> · <a href="https://x.com/nova3d_ai"><img src="https://api.iconify.design/simple-icons:x.svg?color=%230e1013" width="16" height="16" align="center" alt="X" /> X</a> · <a href="https://github.com/RareSense/Nova3D/issues"><img src="https://api.iconify.design/octicon:issue-opened-16.svg?color=%230e1013" width="16" height="16" align="center" alt="Issues" /> issues</a>

<a href="https://github.com/RareSense/Nova3D/stargazers"><img src="https://img.shields.io/github/stars/RareSense/Nova3D?style=flat-square&labelColor=0e1013&color=f0c27b" alt="Stars"></a>
<img src="https://img.shields.io/badge/MuJoCo-3.x-6fe3a6?style=flat-square&labelColor=0e1013" alt="MuJoCo">
<img src="https://img.shields.io/badge/exports-MJCF%20·%20USD%20·%20SDF%20·%20URDF-8fa5ff?style=flat-square&labelColor=0e1013" alt="Exports">
<a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-d5d9de?style=flat-square&labelColor=0e1013" alt="MIT"></a>

<br/>

<img src="docs/media/robotics/hero_farm.gif" width="100%" alt="Robots harvesting on a Nova3D-generated farm, simulated in MuJoCo" />

*A working farm, written by Nova3D from one prompt. Humanoids pick tomatoes, quadrupeds carry the harvest, drones scout. Simulated and filmed in MuJoCo.*

<img src="docs/media/robotics/stats.svg" width="100%" alt="4 simulators · 173 mechanisms force-tested · friction-accurate · digital cousins checked shot-for-shot"/>

</div>

<br/>

<samp>worlds</samp>

## Robots at work.

Every world below started as a text prompt, was generated as an **executable scene program**, compiled to MuJoCo, and populated with robots. Doors open on real hinges, produce carries labeled masses, floors carry measured friction. The environment is code, so every physical property is authored, not painted on.

<table align="center">
  <tr>
    <td align="center" width="33%"><img src="docs/media/robotics/cafe_robots.gif" width="100%"/><br/><sub><b>Café</b> · Unitree G1 waiters clear tables; a Go2 serves from its back <i>(learned walking policy, full physics)</i></sub></td>
    <td align="center" width="33%"><img src="docs/media/robotics/mall_robots.gif" width="100%"/><br/><sub><b>Mall</b> · Spot patrols, H1 delivers parcels, Stretch restocks, a Skydio X2 flies the atrium</sub></td>
    <td align="center" width="33%"><img src="docs/media/robotics/field_robots.gif" width="100%"/><br/><sub><b>Farm</b> · Apptronik Apollo picks tomatoes into a basket; ANYmal hauls the crate</sub></td>
  </tr>
  <tr>
    <td align="center" width="33%"><img src="docs/media/robotics/g1_apartment.gif" width="100%"/><br/><sub><b>Apartment</b> · a G1 tidies a generated home, object by object</sub></td>
    <td align="center" width="33%"><img src="docs/media/robotics/zerog_catch.gif" width="100%"/><br/><sub><b>Orbital lab</b> · a UR5e throws a sample across the module in zero g; a Franka Panda catches it in flight</sub></td>
    <td align="center" width="33%"><img src="docs/media/robotics/friction_go2_lanes.gif" width="100%"/><br/><sub><b>Traction hall</b> · one walking policy, three floors: ice μ 0.02, steel μ 0.30, rubber μ 1.05</sub></td>
  </tr>
</table>

<br/>

<samp>physics</samp>

## Real-life physics, built in.

Every scene Nova3D produces comes with real-life physics as part of the world itself: gravity, contact, friction, mass and inertia. Change one constant and the simulation answers. Here the same scene runs twice; the only difference is gravity.

<table align="center">
  <tr>
    <td align="center" width="50%"><img src="docs/media/robotics/zerog_pushoff.gif" width="100%"/><br/><sub><b>g = 0</b> · a Booster T1 pushes off the hatch with its legs and floats the length of the module, carried only by the momentum of that push</sub></td>
    <td align="center" width="50%"><img src="docs/media/robotics/gravity981_drop.gif" width="100%"/><br/><sub><b>g = 9.81 m/s²</b> · the identical throw now falls in a curve, and the catcher waiting on the straight line misses</sub></td>
  </tr>
</table>

<div align="center"><img src="docs/media/robotics/friction_ramp.gif" width="72%"/></div>

*The ramp tilts slowly, and the blocks let go in order of grip: the ice block slides at just 4.6°, steel at 15°, aluminium at 20°, oak at 26°, and the rubber block holds on to the very end. Nobody animated any of this. Each block slips at exactly the angle where physics says its grip runs out.*

<br/>

<samp>validation</samp>

## Every mechanism opens before a scene ships.

The build pushes every door, drawer, lid and gate with the physics engine itself. A hinge that jams, a drawer that binds, a prop that floats: each one fails the build, by name.

<div align="center"><img src="docs/media/robotics/mechtest.svg" width="100%" alt="Mechanism test console output: hinges, sliders, free bodies, jammed=0, status=passed"/></div>

<br/>

<samp>digital&nbsp;cousins</samp>

## A real place, rebuilt as a digital cousin.

<div align="center">
<img src="docs/media/robotics/real_vs_mujoco_go2.jpg" width="100%" alt="Photograph vs Nova3D digital cousin in MuJoCo vs the same scene with a Go2 robot inserted"/>
<img src="docs/media/robotics/real_vs_mujoco_go2_angle2.jpg" width="100%" alt="Second camera angle: photograph vs MuJoCo vs MuJoCo with Go2"/>
<img src="docs/media/robotics/real_vs_mujoco_go2_angle3.jpg" width="100%" alt="Third camera angle: photograph vs MuJoCo vs MuJoCo with Go2"/>
</div>

*Left: the photograph. Middle: the Nova3D digital cousin rendered in MuJoCo from the same camera. Right: the same scene with a Unitree Go2 walking through it. Cousins are rebuilt object by object from photos: every visible item counted, placed and sized against the originals, checked shot for shot from every angle.*

<br/>

<samp>thesis</samp>

## A robot can't open a door that is one fused mesh.

<div align="center">

<img src="docs/media/robotics/g1_doors.gif" width="62%" alt="A Unitree G1 walks a generated house in MuJoCo, opening real hinged doors room by room."/>

<sub>A G1 tours a generated house in MuJoCo and opens every door on its way, because every door is a real hinged body.</sub>

</div>

Mesh generators output vertex soup. Nova3D never builds fused meshes:

- **Named parts, real hierarchy.** `kitchen_door`, its hinge pin, its handle: separately addressable bodies.
- **Working mechanisms.** Hinges and sliders with limits, damping and clearances that survive contact simulation.
- **Labeled physics.** Every loose object carries mass, inertia and friction with stated provenance.
- **Verified, not vibed.** Mechanism force-tests, terrain probe-tests and photo-matched captures gate every build.

<br/>

<samp>exports</samp>

## One source. Every engine.

A world written once opens wherever people build, play and train. Change the source and every target follows. For robotics the exports are native: MuJoCo (MJCF), Isaac Sim (USD), Gazebo (SDF) and PyBullet (URDF), the same environment everywhere, never four approximations.

<div align="center"><a href="https://nova3d.xyz"><img src="docs/media/robotics/every_engine.png" width="78%" alt="One source, every engine: MuJoCo, Isaac Sim, Gazebo, PyBullet, Omniverse, Unity, Unreal, Godot, Roblox, Minecraft, the web, glTF, Blender, OpenUSD, Rhino"/></a></div>

Static structure exports with exact collision. Mechanisms export as native joints on every target. Outdoor ground exports as height fields, so feet collide with the actual hill, not its convex hull.

<br/>

<samp>studio</samp>

## Worlds as software projects.

Nova3D builds 3D worlds as software projects you can edit, test and build on.

| **Keep building.** | **Decide what happens.** | **Build it together.** |
|---|---|---|
| Rebuild a part, add something new, or make another version. Every change is a saved version you can replay. | Add movement, controls and interactions to the things you build. | People and AI agents work in the same world at the same time, each on their own branch. The branches merge into one world. |

<br/>

<details>
<summary><b>Nova3D beyond robotics: general 3D asset generation</b> (click to expand)</summary>

<br/>

Nova3D generates 3D assets as **executable construction procedures**: prompt-to-code targeting Blender's API, compiling to structured GLB with named parts, assembly hierarchy, joint pivots and PBR materials.

<div align="center">
<img src="app/assets/gifs/nova3d/drill_machine.gif" width="32%" />&nbsp;<img src="app/assets/gifs/nova3d/escalator.gif" width="32%" />&nbsp;<img src="app/assets/gifs/nova3d/oven.gif" width="32%" />
</div>

[![Nova3D one-shot generation demo](docs/media/demo_one_shot.png)](https://www.youtube.com/watch?v=309zNw0JETU)

**Comparisons:** [vs TRELLIS & Hunyuan3D](https://www.youtube.com/watch?v=iL_NX_hBq9k) · [vs NVIDIA PartPacker & Tripo segmentation](https://www.youtube.com/watch?v=msGZs4EMnvs)

<div align="center"><img src="docs/media/comparison_slider.gif" width="100%" alt="Nova3D vs Meshy, TRELLIS.2, TripoSG" /></div>

<div align="center"><img src="docs/media/anatomy_ring.jpg" width="100%" alt="Measured engagement ring" /></div>

*Prompt-stated dimensions hold up when measured back from the result: a ring generated to 17.00 mm inner diameter measures 17.00 mm.*

<div align="center"><img src="docs/media/segmentation_explode.gif" width="78%" /></div>

<div align="center"><img src="docs/media/assembly_hierarchy.gif" width="100%" /></div>

<div align="center"><img src="docs/media/articulation_crane.gif" width="100%" /></div>

<div align="center"><img src="docs/media/uv_from_code.png" width="100%" /></div>

</details>

<br/>

<samp>start</samp>

## Open Studio. Pick a cartridge.

New projects in Studio start from a cartridge. Pick **ROBOTICS** and the project is wired for MuJoCo, PyBullet, Gazebo and Isaac Sim from the first prompt.

<div align="center"><a href="https://app.nova3d.xyz"><img src="docs/media/robotics/studio_cartridges.png" width="88%" alt="Nova3D Studio: new project console with the Game Assets and Robotics cartridges"/></a></div>

<div align="center"><a href="https://app.nova3d.xyz"><b>Open Studio ↗</b></a> · no local backend required</div>

<br/>

This repository is the home of Nova3D's open clients and integrations: the [web client](app/), the [MCP server](mcp/) and the [Blender add-on](blender-plugin/).

> Robot models in the films are from the [MuJoCo Menagerie](https://github.com/google-deepmind/mujoco_menagerie);
> the worlds, physics setups, controllers and films are Nova3D.

<br/>

<div align="center">

<a href="https://app.nova3d.xyz"><img src="docs/media/robotics/footer.svg" width="100%" alt="Build a world. Put a robot in it. Open Studio"/></a>

</div>

## License

[MIT](LICENSE) © RareSense. The clients and integrations in this repository are open-source.

<p align="center">
  <small>Built on the same engine powering <b><a href="https://formanova.ai">FormaNova</a></b> for specialized jewelry CAD.</small>
</p>
