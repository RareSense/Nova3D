# Nova3D — Blender Plugin

Generate part-structured 3D assets **natively inside Blender**, powered by the
hosted Nova3D backend. Type a prompt (optionally attach reference images), spend
Nova3D credits, and get a clean, named, editable model imported straight into
your scene — plus its source program, UV atlases, and a durable project folder
on disk.

This plugin talks to the **same hosted GraphFlow API the web app uses**. There
are no Blender-specific backend routes and **no backend or web-app changes** are
required: it authenticates with your Nova3D API key, draws from the same credit
wallet, and writes into the same chat history you see at
[app.nova3d.xyz](https://app.nova3d.xyz).

> Scope: **initial generation only**, **credits only** (no BYOK provider keys).
> Editing/articulation/UV-in-editor live in the web app.

---

## What it does

- **Prompt → 3D, in Blender.** Same inputs as the web app: a prompt (≤ 40 words)
  and/or up to 3 reference images (≤ 8 MB each, auto-downscaled to 512 px).
- **Credits-only with preflight.** Before spending anything it checks workflow
  readiness, estimates the credit hold, and confirms your balance — exactly like
  the web client. Shows your live credit balance and a **Buy Credits** button
  that opens the same Stripe checkout.
- **Non-blocking.** Generation runs on a background thread; Blender stays fully
  responsive and shows a live progress line ("Writing the Blender scene…",
  "Reviewing the generated model…", …). Press **Esc** or **Cancel** to stop.
- **Durable, user-owned output.** Every generation writes its own folder:

  ```
  ~/Nova3D/<timestamp>_<slug>/
    ├── model.glb      the exported asset
    ├── code.py        the Blender program that built it (re-runnable)
    ├── joints.json    articulation rig (only if the asset has joints)
    ├── uvs/           UV atlases (combined + per-group), like the web app
    └── meta.json      pointers: workflow_id, conversation_id, message_id,
                       code_artifact, prompt, model, credits, joints
  ```

- **Clean scene handling.** The new model is imported into its own
  `Nova3D_<slug>` collection. Previous Nova3D generations are **auto-hidden**
  (never deleted) so only the newest shows. Your other objects are never
  touched.
- **Re-runnable code.** `code.py` is loaded into Blender's **Text Editor** as a
  datablock you can read, tweak, and re-run.
- **Synced history.** Each generation is linked to a Nova3D conversation, so when
  you sign in to the web app with the same account it appears in your recent
  history — fully interactive (model preview, code, joints).

---

## Install

No extra Python packages are needed — the plugin uses only Blender's bundled
standard library (no venv, no `requirements.txt`).

### 1. Get the zip

**Easiest — download a release:** grab `nova3d_blender-<version>.zip` from the
[latest release](https://github.com/RareSense/Nova3D/releases) (filter by the
`blender-plugin-v*` tags).

**Or build from source** (no `zip` binary needed, just `python3`):

```bash
cd blender-plugin
bash build.sh           # → blender-plugin/dist/nova3d_blender-<version>.zip
```

### 2. Install in Blender

**Blender 4.2+ / 5.x (extension):** drag the zip onto the Blender window, or
**Edit ▸ Preferences ▸ Get Extensions ▸ ⌄ ▸ Install from Disk…**, and confirm
the requested *Network* + *Files* permissions.

**Blender 3.6–4.1 (legacy add-on):** **Edit ▸ Preferences ▸ Add-ons ▸ Install…**,
pick the zip, and enable **"Nova3D — Code-native 3D Generation"**. (The bundled
`blender_manifest.toml` is simply ignored on these versions.)

> **Compatibility:** Blender **3.6 → 5.x** (verified against 5.1). On 4.2+/5.x it
> runs as an extension and respects **Preferences ▸ System ▸ Allow Online
> Access** — that toggle must be on for generation to work.

### Maintainer: cutting a release

The release zip is built and attached automatically by
`.github/workflows/blender-plugin-release.yml` when you push a surface tag:

```bash
git tag blender-plugin-v1.0.0
git push origin blender-plugin-v1.0.0
```

## Set up your account

1. In the add-on preferences (or the panel's *Connect your Nova3D account*
   prompt), click **Get / Create API Key**. This opens the Nova3D web page where
   you sign in / create an account and generate an API key (`n3d_…`).
2. Paste the key into **Preferences ▸ Add-ons ▸ Nova3D ▸ API Key**.

That key is stored in Blender's user preferences (not in your `.blend`) and is
only ever sent as the `Authorization` header to the Nova3D API.

## Use it

Open the **N-panel** in the 3D Viewport and pick the **Nova3D** tab.

1. Check your **Credits** (refresh with the ↻ button; top up with **Buy
   Credits**).
2. Type a **Prompt** and choose a **Model**.
3. Optionally **Add Reference Image(s)** (up to 3).
4. Click **Generate**. Watch the status line; Blender stays usable throughout.
5. When it finishes, the model appears in the viewport, `code.py` opens in the
   Text Editor, and **Open Last Generation Folder** reveals the files on disk.

---

## Configuration (preferences)

| Setting | Default | Notes |
|---|---|---|
| **API Key** | _(empty)_ | Your `n3d_…` key. |
| **Output Folder** | `~/Nova3D` | Root for per-generation project folders. |
| **API Base URL** | `https://nova3d.xyz/api` | Change only for self-hosting. |
| **Web Base URL** | `https://app.nova3d.xyz` | Hosts the API-key and credits pages (the Flutter app). |

**Self-hosting:** point *API Base URL* / *Web Base URL* at your own deployment.
The plugin calls the standard GraphFlow routes (`/workflow/readiness`,
`/credits/estimate`, `/credits/balance/me`, `/run/state`, `/status`, `/result`,
`/conversations*`), so any compatible backend works unchanged.

---

## How it works (data flow)

```
Blender add-on (worker thread)
  → GET  /workflow/readiness/sketch_to_3d_v2        (preflight)
  → POST /credits/estimate                          (credit hold)
  → GET  /credits/balance/me                        (affordability)
  → POST /conversations                             (history session)
  → POST /run/state/sketch_to_3d_v2?request_id=…    (start)
  → GET  /status/{id}   (poll, 3s)                  (progress)
  → GET  /result/{id}                               (GLB + code + joints URLs)
  → download artifacts → ~/Nova3D/<ts>_<slug>/
  → PATCH /conversations/{id}  + POST messages/links (web history)
  → POST /run/state/generate_uv_maps …              (UV atlases)
Blender main thread
  → import GLB into Nova3D_<slug>, hide older, load code.py text datablock
```

Authentication is `Authorization: Bearer n3d_…` on every call. The key resolves
server-side to the **same account** as your web login, which is why credits and
history are shared automatically.

## Architecture

The add-on is split so the network/IO layers never touch Blender's data model
(which is not thread-safe), and the Blender layer never blocks on the network:

| Module | Responsibility | Touches `bpy`? |
|---|---|---|
| `api/` | stdlib HTTP, typed client, result parsing | no |
| `services/generation.py` | the worker pipeline (preflight → poll → save) | no |
| `services/history.py` | conversation snapshot/message payloads | no |
| `services/project_store.py` | `~/Nova3D/<ts>_<slug>/` + `meta.json` | no |
| `services/uv_maps.py` | UV atlas bundle | no |
| `services/images.py` | reference-image encode/resize | yes (main thread only) |
| `scene_io/importer.py` | GLB import, collection hiding, text datablock | yes (main thread) |
| `operators/generate.py` | modal operator bridging worker ↔ Blender | yes (main thread) |
| `ui/panel.py` | the N-panel | yes |

The worker reports progress over a thread-safe queue; the modal operator drains
it each timer tick and performs all Blender-side work on the main thread.

## Privacy & security

- Your API key lives only in Blender's user preferences and is sent only to the
  configured API base. It is never logged or written into project files.
- The add-on declares exactly two extension permissions — *network* (to reach
  the Nova3D API) and *files* (to write your output folder) — and respects
  Blender's "Allow Online Access" setting.
- TLS certificate verification is always on.
- The plugin sends **no provider API keys** — paid generations resolve provider
  credentials server-side.

## License

MIT © RareSense. The clients and integrations in the Nova3D repository are
open-source; the hosted generation backend is proprietary.
