# Nova3D — Blender Add-on

Generate **part-structured 3D models** from a text prompt (and optional reference
images) right inside Blender. Each model imports as named, separately-editable
meshes with materials and a UV atlas — plus the Blender Python that built it.
Powered by the hosted Nova3D service; billed in Nova3D credits.

> Blender **3.6 → 5.x** (tested on 5.1). No Python dependencies.

## Install

```bash
git clone https://github.com/RareSense/Nova3D.git
cd Nova3D/blender-plugin
bash build.sh            # → dist/nova3d_blender-1.0.0.zip
```


In Blender: **Edit ▸ Preferences ▸ Get Extensions ▸ ⌄ ▸ Install from Disk…**,
pick the zip, and confirm the *Network* + *Files* permissions. Then turn on
**Edit ▸ Preferences ▸ System ▸ Allow Online Access**.

![Install from disk](docs/media/install.png)

## Connect

Open the **N-panel ▸ Nova3D** tab and **Sign in with Google** (or paste an API key).

![Sign in](docs/media/connect.png)

A browser tab finishes sign-in — then return to Blender.

![Browser handoff](docs/media/browser.png)

## Generate

Type a prompt, choose a model, optionally add up to 3 reference images, and click
**Generate**. Blender stays responsive; the finished model imports into the
viewport and `code.py` opens in the Text Editor.

![Generate](docs/media/generate.png)

Every generation is saved to `~/Nova3D/<timestamp>_<slug>/`:

```
model.glb   ·   code.py   ·   uvs/   ·   meta.json
```

## Notes

- **Credits only** (Gemini, Claude, GPT-5.5). Top up with **Buy Credits**.
- Generations **auto-resume** if interrupted (network drop, Blender closed).
- Settings: **Preferences ▸ Add-ons ▸ Nova3D** — output folder, clean-viewport,
  and self-host URLs.
- Your credential is stored in Blender's user preferences and sent only to the
  Nova3D API.

MIT © RareSense.
