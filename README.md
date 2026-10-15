<div align="center">

<a href="https://nova3d.xyz"><img src="docs/media/site/banner.svg" width="100%" alt="Nova 3D: design workspace for programmable 3D" /></a>

<a href="https://nova3d.xyz"><img src="https://api.iconify.design/lucide:globe-2.svg?color=%230e1013" width="16" height="16" align="center" alt="Website" /> website</a> · <a href="https://app.nova3d.xyz"><img src="https://api.iconify.design/lucide:box.svg?color=%230e1013" width="16" height="16" align="center" alt="App" /> open studio</a> · <a href="https://arxiv.org/abs/2607.22738"><img src="https://api.iconify.design/simple-icons:arxiv.svg?color=%23b31b1b" width="16" height="16" align="center" alt="Paper" /> paper</a> · <a href="https://discord.gg/QEH8mzcwdR"><img src="https://api.iconify.design/simple-icons:discord.svg?color=%235865f2" width="16" height="16" align="center" alt="Discord" /> discord</a> · <a href="https://x.com/nova3d_ai"><img src="https://api.iconify.design/simple-icons:x.svg?color=%230e1013" width="16" height="16" align="center" alt="X" /> X</a> · <a href="https://github.com/RareSense/Nova3D/issues"><img src="https://api.iconify.design/octicon:issue-opened-16.svg?color=%230e1013" width="16" height="16" align="center" alt="Issues" /> issues</a>

<a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-d5d9de?style=flat-square&labelColor=0e1013" alt="MIT"></a>

<br/>

<img src="docs/media/robotics/hero_farm.gif" width="100%" alt="Robots harvesting on a Nova3D-generated farm, simulated in MuJoCo" />

*A working farm, written by Nova3D from one prompt. Humanoids pick tomatoes, quadrupeds carry the harvest, drones scout. Simulated and filmed in MuJoCo.*

</div>

<br/>

## Capabilities

1. **Executable source:** represent assets and environments as programs that can be inspected, edited, and rebuilt.
2. **Parametric control:** define dimensions, proportions, materials, physical properties, and motion through explicit parameters.
3. **Controlled variation:** specify which parameters change and which remain fixed across design alternatives or experiments.
4. **Structural editing:** change components, assemblies, layouts, clearances, and connections through their construction code.
5. **Reusable construction:** reuse components and generation logic to build related designs, asset families, and environments.
6. **Programmable motion:** define articulation, animation, interactive controls, and prescribed object trajectories.
7. **Geometry and motion checks:** inspect dimensions, part relationships, pivots, and collisions, using checks appropriate to the design.
8. **Versioned development:** preserve source, parameters, build outputs, and validation results as the project evolves.
9. **Target-specific exports:** compile designs for CAD tools, 3D applications, and robotics simulators through dedicated export paths.

### For robotics

1. **Controlled scenario generation:** specify which geometric, physical, and temporal parameters change, and which remain fixed.
2. **Structural variation:** change connectivity, obstacle arrangement, clearances, and mechanism configurations, not just textures or initial positions.
3. **Reproducible evaluation:** preserve the environment source, parameters, simulator configuration, and experiment results.
4. **Failure-driven generation:** eventually turn a failed rollout into a family of nearby scenarios to investigate the failure boundary.

<br/>

## Describe it. Build it. Keep going.

Start with an idea and keep shaping it. Change the geometry, add motion and behavior, and explore new versions.

<div align="center">
<img src="docs/media/assets/drill_machine.gif" width="32%" />&nbsp;<img src="docs/media/assets/escalator.gif" width="32%" />&nbsp;<img src="docs/media/assets/oven.gif" width="32%" />
</div>

<p align="center"><sub>A drill, an escalator and an oven, each built part by part: assembled, taken apart, and seen through to every piece inside.</sub></p>

<table align="center">
  <tr>
    <td align="center" width="33%"><a href="https://nova3d.xyz/#keep-building"><img src="docs/media/site/keep_bot.gif" width="100%" alt="The gardener bot's arm turns from a soil probe into a watering can"/></a><br/><sub><b>gardener_bot</b><br/><i>Animate his arm changing from the probe into the can, and make him water the plants.</i></sub></td>
    <td align="center" width="33%"><a href="https://nova3d.xyz/#keep-building"><img src="docs/media/site/keep_jewel.gif" width="100%" alt="A ring, then a pair of earrings, then rose gold, then rising-star climbers"/></a><br/><sub><b>shooting_star</b><br/><i>Make this ring.</i> → <i>Turn it into a pair of matching earrings.</i> → <i>Make the earrings rose gold.</i> → <i>Change the earring shape into a rising-star climber.</i></sub></td>
    <td align="center" width="33%"><a href="https://nova3d.xyz/#keep-building"><img src="docs/media/site/keep_doll.gif" width="100%" alt="The harlequin doll's head unzips and a glowing moon floats out"/></a><br/><sub><b>harlequin_doll</b><br/><i>Animate his head unzipping, and a bright glowing moon floating out of it.</i></sub></td>
  </tr>
</table>

<br/>

## Build it together.

People and AI agents work in the same world at the same time, each on their own branch. Then the branches merge into one world.

<table align="center">
  <tr>
    <td align="center" width="33%"><img src="docs/media/site/together_1-build.gif" width="100%" alt="v1: a cottage with a glass tower"/><br/><sub><b>You</b>: <i>Build a cottage on the empty plot, with a glass tower.</i><br/>v1 · 53 parts</sub></td>
    <td align="center" width="33%"><img src="docs/media/site/together_2-open.gif" width="100%" alt="v2: the back opened up"/><br/><sub><b>Maya</b>: <i>I want to see inside. Open up the back.</i><br/>v2 · 19 new parts inside</sub></td>
    <td align="center" width="33%"><img src="docs/media/site/together_3-winter.gif" width="100%" alt="v3: winter"/><br/><sub><b>Sam</b>: <i>What does it look like in winter?</i><br/>v3 · snow, bare trees, frozen pond</sub></td>
  </tr>
  <tr>
    <td align="center" width="33%"><img src="docs/media/site/together_4-night.gif" width="100%" alt="v4: night"/><br/><sub><b>Sam</b>: <i>Now make it night.</i><br/>v4 · 9 lamps and the fire lit</sub></td>
    <td align="center" width="33%"><img src="docs/media/site/together_5-merge.gif" width="100%" alt="v5: the two branches merged"/><br/><sub><b>You</b>: <i>Merge Maya's open back with Sam's winter night.</i><br/>v5 · no conflicts</sub></td>
    <td align="center" width="33%"><img src="docs/media/site/together_6-bot.gif" width="100%" alt="v6: the gardener bot waters the plants"/><br/><sub><b>Maya</b>: <i>Send the gardener bot in to water the plants.</i><br/>v6 · in through the open back</sub></td>
  </tr>
</table>

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

## Simulate. Test. Revise.

Run your designs in simulation to check movement, collisions, and interactions. Find what fails, revise the design, and test it again.

<table align="center">
  <tr>
    <td align="center" width="33%"><img src="docs/media/site/orchard_test1.gif" width="100%" alt="Test 1: the Husky robot is stopped by the tree's low limb"/><br/><sub><b>Test 1 · failed</b><br/><i>Husky, pick the ripe apples off this tree.</i><br/>The low limb stops it at 50 cm.</sub></td>
    <td align="center" width="33%"><img src="docs/media/site/orchard_test2.gif" width="100%" alt="Test 2: the arm snags on branches"/><br/><sub><b>v2 · the low limb tied up 20°</b><br/><b>Test 2 · failed</b>: the arm snags on branches, 0 of 3 apples picked.</sub></td>
    <td align="center" width="33%"><img src="docs/media/site/orchard_test3.gif" width="100%" alt="Test 3: the arm picks the ripe apples into the bin"/><br/><sub><b>v3 · 6 branches pruned out of the arm's path</b><br/><b>Test 3 · passed</b>: 3 ripe apples in the bin, nothing knocked.</sub></td>
  </tr>
</table>

<p align="center"><sub>A Clearpath Husky with a UR10e arm and a Robotiq 2F-85 gripper, in an old orchard grown as code. Asked to <i>adapt this tree for this robot and keep every apple</i>, Nova revises the tree and tests again. Every move is the MuJoCo run: branches bend and spring back, stems snap only when pulled or lifted.</sub></p>

<table align="center">
  <tr>
    <td align="center" width="33%"><img src="docs/media/site/loft_photo.jpg" width="100%" alt="Photo of the real kitchen"/><br/><sub><b>The real kitchen</b><br/>The scene was built from 8 phone photos.</sub></td>
    <td align="center" width="33%"><img src="docs/media/site/loft_test1.gif" width="100%" alt="Test 1: Stretch bumps the bar stool"/><br/><sub><b>Test 1 · failed</b><br/><i>Stretch, get the milk off the island.</i><br/>It bumps the bar stool, 1.1 m short.</sub></td>
    <td align="center" width="33%"><img src="docs/media/site/loft_test2.gif" width="100%" alt="Test 2: Stretch gets the milk"/><br/><sub><b>v2 · adapted for Stretch, design kept</b><br/><b>Test 2 · passed</b>: 4 things moved out of its path, milk in hand at 11 s.</sub></td>
  </tr>
</table>

<br/>

<samp>physics</samp>

## Physics, defined in source.

Mass, inertia, friction, and joint limits are explicit and editable alongside the geometry. Change the conditions and simulate the result. Below, the same scene runs with one parameter changed: gravity, from 0 to 9.81 m/s².

<table align="center">
  <tr>
    <td align="center" width="50%"><img src="docs/media/robotics/zerog_pushoff.gif" width="100%"/><br/><sub><b>g = 0</b> · a Booster T1 pushes off the hatch with its legs and floats the length of the module, carried only by the momentum of that push</sub></td>
    <td align="center" width="50%"><img src="docs/media/robotics/friction_ramp.gif" width="100%"/><br/><sub>The ramp tilts slowly, and the blocks let go in order of grip: the ice block slides at just 4.6°, steel at 15°, aluminium at 20°, oak at 26°, and the rubber block holds on to the very end. Nobody animated any of this. Each block slips at exactly the angle where physics says its grip runs out.</sub></td>
  </tr>
</table>

<br/>

## Build on common ground.

Bring assets, scenes, and behavior together in one programmable project. Build from the same source for design tools, game engines, and simulators.

<div align="center"><a href="https://nova3d.xyz"><img src="docs/media/robotics/every_engine.png" width="78%" alt="One source, every engine: MuJoCo, Isaac Sim, Gazebo, PyBullet, Omniverse, Unity, Unreal, Godot, Roblox, Minecraft, the web, glTF, Blender, OpenUSD, Rhino"/></a></div>

<br/>

## License

[MIT](LICENSE) © RareSense.

<p align="center">
  <small>Built on the same engine powering <b><a href="https://formanova.ai">FormaNova</a></b> for specialized jewelry CAD.</small>
</p>
