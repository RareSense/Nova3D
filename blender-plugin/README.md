# Nova3D — Blender Add-on

Generate **part-structured 3D models** from a text prompt (and optional reference
images) right inside Blender. Each model imports as named, separately-editable
meshes with materials and a UV atlas — plus the Blender Python that built it.
Powered by the hosted Nova3D service; billed in Nova3D credits.

> Works in Blender **3.6 → 5.x** (tested on 5.1). Nothing else to install.

## 1. Download the add-on

Open the [**Releases page**](https://github.com/RareSense/Nova3D/releases) and,
under the newest release's **Assets**, download **`nova3d_blender-1.0.0.zip`**.
Leave it zipped — Blender installs the `.zip` as-is.

## 2. Install it in Blender

1. Open Blender. In the top menu bar, click **Edit → Preferences**.
2. In the window that opens, click **Get Extensions** in the left-hand list.
3. At the **top-right**, click the small **▾ arrow** (next to the funnel icon) and
   choose **Install from Disk…**.
4. Find your `nova3d_blender-1.0.0.zip`, click it, then click **Install from Disk**.
   It installs *and* switches on automatically. If asked, allow the *Network* and
   *Files* permissions.

   ![Choosing the zip file](docs/media/install.png)

5. Still in Preferences, click **System** in the left list and tick
   **Allow Online Access** (the add-on needs this to reach Nova3D). Close Preferences.

## 3. Open the Nova3D panel

Press **N** in the 3D viewport to open the sidebar, then click the **Nova3D** tab.

## 4. Sign in

Click **Sign in with Google**. Your web browser opens — sign in there. When the page
says **"Nova3D is ready"**, switch back to Blender; you're now connected.

> No Google account? Click **Enter Key** instead and paste a Nova3D API key
> (create one at <https://app.nova3d.xyz/api-key>).

![Sign in panel](docs/media/connect.png)
![Browser confirmation](docs/media/browser.png)

## 5. Generate

1. Type what you want in the **Prompt** box (e.g. *"7 DOF robotic arm"*).
2. Pick a **Model** from the dropdown.
3. *(Optional)* Click **Add Reference Image** — up to 3.
4. Click **Generate** and wait. Blender stays usable while it runs.

![Generate panel](docs/media/generate.png)

When it finishes, the model appears in the viewport and its `code.py` opens in
Blender's Text Editor. Everything is also saved on your computer at
`~/Nova3D/<timestamp>_<name>/`:

```
model.glb   ·   code.py   ·   uvs/   ·   meta.json
```

## Good to know

- **Credits** power generation (Gemini, Claude, GPT-5.5). See your balance and
  **Buy Credits** at the top of the panel.
- If a run is interrupted (network drop, Blender closed), it **auto-resumes** —
  reopen the panel and click **Resume**.
- If Nova3D can't be reached, the panel shows an **unreachable** notice with a
  **Retry** button — no failed generation, just try again when you're back online.
- The add-on checks for a newer version on startup and shows a **Download update**
  link when one exists (also under **Preferences → Add-ons → Nova3D**).
- Don't see colours? Materials only show in **Material Preview**; the add-on
  switches to it for you. Press **Alt + H** to un-hide anything it tucked away.
- Change the output folder or self-host URLs in
  **Edit → Preferences → Add-ons → Nova3D**.

## Build from source (developers)

```bash
git clone https://github.com/RareSense/Nova3D.git
cd Nova3D/blender-plugin
bash build.sh            # creates dist/nova3d_blender-1.0.0.zip
```

Then install that zip via step 2 above.

MIT © RareSense.
