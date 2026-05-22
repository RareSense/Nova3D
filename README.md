<div align="center">

# Nova3D

**A tool that generates 3D objects with separate, editable parts - instead of a single merged blob**

[website](https://nova3d.xyz) · [discord](https://discord.gg/QEH8mzcwdR) · [twitter/X](https://x.com/nova3d_ai) · [github issues](https://github.com/RareSense/Nova3D/issues)

<br/>

<img src="assets/gifs/nova3d/0504.gif" width="32%" />&nbsp;<img src="assets/gifs/nova3d/0504(1).gif" width="32%" />&nbsp;<img src="assets/gifs/nova3d/0504(2).gif" width="32%" />

</div>

## What is Nova3D?

Nova3D generates 3D assets as **executable construction procedures**. The pipeline writes Blender-native Python scripts, returning a structured GLB with named, separately addressable parts.

This is architecturally different from diffusion-based generators (Meshy, Tripo, Rodin), which extract a single merged mesh with no part boundaries, and from OpenSCAD-based systems (CADAM), which guarantee manifold solids but have a hard ceiling on organic shapes, hierarchy, materials, and structural editability. 

Nova3D uses Blender's scene graph as the native representation - the most expressive geometry substrate available - making it a strict superset of both approaches.

This repo is the client. It connects to our (currently) closed-source hosted service. 

---

## Prerequisites

The client is built with Flutter/Dart. If you don't have Flutter 3.24+ installed, set it up first:

<details>
<summary>💻 macOS</summary>

Install Flutter via [Homebrew](https://brew.sh):

```bash
brew install --cask flutter
flutter doctor
```

</details>

<details>
<summary>🪟 Windows</summary>

Install Flutter via [Chocolatey](https://chocolatey.org) (run PowerShell as Administrator):

```powershell
choco install flutter
```

Then close and reopen your terminal, and verify:

```powershell
flutter doctor
```

> Don't have Chocolatey? [Install it here](https://chocolatey.org/install), or follow the [manual Flutter install guide](https://docs.flutter.dev/install/manual).

</details>

<details>
<summary>🐧 Linux</summary>

Install Flutter via Snap:

```bash
sudo snap install flutter --classic
flutter sdk-path   # confirm install path
flutter doctor
```

</details>

Once `flutter doctor` shows no blocking issues, continue with Quick Start below.

## Quick Start

Get it running locally in under 2 minutes. Requires [Flutter 3.24+](https://flutter.dev).

```bash
# 1. Clone and Install
git clone https://github.com/RareSense/Nova3D.git
cd Nova3D
flutter pub get

# 2. Run Local UI
# Note: Port 5555 is required for OAuth redirect authorization
flutter run -d web-server --web-hostname 0.0.0.0 --web-port 5555
```

1.  Open `http://127.0.0.1:5555`
2.  Sign in (Google/Email).
3.  **Settings** → Add your API Key (OpenAI, Anthropic, or Gemini).
4.  Enter a prompt and generate.

---

## Demo

[![Editable parts — quick look](https://i.imgur.com/mnHrRKG.png)](https://www.youtube.com/watch?v=rLzkfTzDdwY)
☝️Prompt: Make a washing machine with detailed internal mechanics

## Comparison

[![Nova3D vs TRELLIS vs Hunyuan3D](https://i.imgur.com/QAAgIQ8.png)](https://www.youtube.com/watch?v=iL_NX_hBq9k)
☝️Side-by-side comparison with TRELLIS and Hunyuan3D

Nova3D is optimized for **structured asset generation**, but the advantage is not limited to multipart editing. In this comparison, Nova3D also shows stronger **single-asset fidelity**: cleaner silhouette control, sharper feature delineation, more coherent surface transitions, and better preservation of distinct functional substructures.

The important point is that **explicit part structure is an added capability, not a quality tradeoff**. Even when judged purely as a single 3D object, Nova3D aims for higher geometric clarity and stronger downstream readiness; preserving named, separately editable components comes on top of that.

[![Nova3D vs PartPacker vs Tripo Segmentation](https://i.imgur.com/wWjVuRr.png)](https://www.youtube.com/watch?v=msGZs4EMnvs)
☝️Part-aware comparison with NVIDIA PartPacker and Tripo

Nova3D emphasizes **semantic separation with usable structure**. The goal is to preserve discrete components as independently addressable objects with stable boundaries, clearer instance separation, and better **edit locality**.

In practice, that means Nova3D is designed for assets that need to remain actionable after generation: users can inspect, regenerate, restyle, articulate, or export components without collapsing the model back into a single undifferentiated mesh.

---

## Technical Philosophy

### 1. Script-Native vs. Mesh-Native
Most AI 3D generators use "Image-to-3D" diffusion. Nova3D is "Prompt-to-Code" or "Image-to-Code." And by targeting Blender's API, the following is achieved:
*   **Logical Hierarchy:** Parts are named and parented correctly.
*   **Surgical Edits:** Change the "handle" without regenerating the "cup."
*   **Material Support:** Proper PBR texture mapping rather than "baked" vertex colors.

### 2. Model Agnostic
Nova3D is a generation harness. You can swap between Claude 3.5, GPT-4o, or Gemini 1.5 Pro via the settings menu. The pipeline handles validation and execution regardless of which LLM is writing the code.

### 3. Precision + Organic Flow
Unlike pure CSG/OpenSCAD systems which struggle with organic shapes, Nova3D leverages Blender's full suite of modifiers (subdivision, sculpting, booleans) to create high-fidelity models.

---

## Features

*   **Integrated Viewport:** Built-in Three.js editor with transform tools, snapping, and material editing.
*   **Local Caching:** Models are cached in-browser; view your history even after remote URLs expire.
*   **Reference Images:** Attach a photo to guide the spatial logic of the generated script.
*   **Production Build:** `flutter build web --release` for static hosting.

---

## Troubleshooting

*   **Auth Loops:** Always use `http://127.0.0.1:5555`. Using `localhost:5555` will cause Google Sign-In to fail due to strict OAuth origin policies.
*   **Self-Hosting Backend:** By default, this client communicates with the `nova3d.xyz` API (currently closed-source). Self-hosting is theoretically possible by setting --dart-define=API_BASE_URL=https://your-api.com, but you would have to build your own server from scratch.

---

<p align="center">
  <small>
    Built on the same engine powering <b><a href="https://formanova.ai">FormaNova</a></b> for specialized jewelry CAD.
  </small>
</p>
