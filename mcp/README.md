# nova3d-mcp

<!-- mcp-name: io.github.RareSense/nova3d-mcp -->

**Structured, part-aware 3D generation for AI agents.**

nova3d-mcp is an [MCP](https://modelcontextprotocol.io) server that exposes
[Nova3D](https://nova3d.xyz)'s generation pipeline as a callable tool inside
Codex, Cursor, VS Code, Visual Studio, Claude Code, and other MCP-compatible agents.

One tool call. A washing machine comes back with named drum, door, control
panel, and hose connectors — separately editable, not fused into a blob.

---

## Quickstart

Claude Code:

1. Run `claude mcp add nova3d -- uvx nova3d-mcp`
2. In Claude, call `nova3d_login`
3. Complete the Nova3D browser sign-in flow
4. Then call `nova3d_status`

Other MCP clients:

- See [Install](#install) for client-specific setup
- Then follow the shared [First Run](#first-run) steps

---

## Why Nova3D

Every major AI 3D generator today produces **mesh blobs** — a single fused
object that looks plausible in a render and collapses the moment you try to
edit, rig, or pipeline it.

Nova3D is different. Instead of diffusion → mesh, it runs:

```
prompt / image
      ↓
LLM writes Blender Python construction code
      ↓
headless Blender executes + validates + repairs
      ↓
structured GLB — named parts, intact hierarchy, real joints
```

The result is a 3D asset that **survives contact with real workflows**: game
engines, configurators, robotics simulations, AR scenes. Parts have names.
Hierarchy is intact. Joints are real. You can change one component without
regenerating everything.

---

## Supported clients

| Client | Status | Install path | Preview path |
|---|---|---|---|
| Codex | Supported | `codex mcp add` or Codex MCP config | Browser `conversation_url` |
| Cursor | Supported | `.cursor/mcp.json` or `~/.cursor/mcp.json` | Browser `conversation_url` |
| VS Code | Supported | `.vscode/mcp.json`, MCP: Add Server, or `code --add-mcp` | Browser `conversation_url` |
| Visual Studio | Supported | `.mcp.json` or Visual Studio MCP UI | Browser `conversation_url` |
| Claude Code | Supported | `claude mcp add` | Browser `conversation_url` |

Nova3D runs from your MCP client, but model inspection happens through the
hosted browser viewer returned as `conversation_url`. This repository does not
currently ship an embedded IDE-native 3D viewport.

---

## Install

Add the MCP server in your client first. This only registers the server. It
does **not** complete Nova3D account onboarding yet.

#### Codex

```bash
codex mcp add nova3d -- uvx nova3d-mcp
```

Codex also supports MCP configuration through `~/.codex/config.toml`. If you
prefer config files over the CLI, use Codex's MCP config surface and point it
at the same stdio command: `uvx nova3d-mcp`.

#### Claude Code

```bash
claude mcp add nova3d -- uvx nova3d-mcp
```

#### Cursor

Create `.cursor/mcp.json` in your project, or `~/.cursor/mcp.json` for a global
install:

```json
{
  "mcpServers": {
    "nova3d": {
      "command": "uvx",
      "args": ["nova3d-mcp"]
    }
  }
}
```

#### VS Code

Option A: add the server from the command line:

```bash
code --add-mcp "{\"name\":\"nova3d\",\"command\":\"uvx\",\"args\":[\"nova3d-mcp\"]}"
```

Option B: create `.vscode/mcp.json` in your workspace:

```json
{
  "servers": {
    "nova3d": {
      "command": "uvx",
      "args": ["nova3d-mcp"]
    }
  }
}
```

You can also use `MCP: Add Server` from the Command Palette.

#### Visual Studio

Create `<SOLUTIONDIR>/.mcp.json` or `%USERPROFILE%/.mcp.json`:

```json
{
  "servers": {
    "nova3d": {
      "command": "uvx",
      "args": ["nova3d-mcp"]
    }
  }
}
```

You can also add the server from the Visual Studio MCP UI by providing the
stdio command `uvx` with args `["nova3d-mcp"]`.

After the server is installed in any client, the next step is to call
`nova3d_login` or `nova3d_setup` from inside that client. Installation alone
does not complete Nova3D onboarding.

## First Run

After installing the MCP server in any client:

1. Call `nova3d_login`
2. Complete the Nova3D sign-in flow in the browser tab that opens
3. Call `nova3d_status`
4. If `next_action == "purchase_credits"`, follow the returned purchase link
5. When `authenticated: true` and `generation_ready: true`, start using `generate_3d`

Important:

- Installing the MCP server and completing Nova3D sign-in are separate steps.
- `nova3d_login` opens a browser tab and may return `login_pending_confirmation: true`
  while local MCP session setup is still being confirmed.
- If browser sign-in finishes but login completion is ambiguous, call
  `nova3d_status` before retrying or considering manual fallback.
- `NOVA3D_TOKEN` is an advanced/manual fallback only for environments where
  browser/loopback auth is unavailable.

## For AI Assistants

If you are helping a user set up Nova3D MCP:

1. Ensure the `nova3d` MCP server is installed in the client
2. Call `nova3d_login`
3. Tell the user a browser tab will open and they must complete sign-in there
4. After browser sign-in, call `nova3d_status`
5. If `next_action == "purchase_credits"`, direct the user to the returned URL
6. Proceed to `generate_3d` only when `authenticated: true` and `generation_ready: true`
7. Only suggest manual `NOVA3D_TOKEN` setup if browser/loopback auth is unavailable

## Onboarding Decision Tree

- If `nova3d_login` returns `login_pending_confirmation: true`
  - complete the browser sign-in flow
  - then call `nova3d_status`
- If `nova3d_status.next_action == "sign_in"`
  - call `nova3d_login`
- If `nova3d_status.next_action == "session_expired"`
  - call `nova3d_login` again
- If `nova3d_status.next_action == "purchase_credits"`
  - follow the returned purchase URL
- If `nova3d_status.next_action == null` and `generation_ready == true`
  - proceed to `generate_3d`

## Local install

If you prefer to install from source instead of `uvx`, clone the repository and
install the package locally:

```bash
git clone https://github.com/RareSense/nova3d-mcp.git
cd nova3d-mcp
python3.10 -m venv .venv && source .venv/bin/activate
pip install .
```

Then replace `uvx nova3d-mcp` in the client examples above with the local
`nova3d-mcp` executable from your environment.

## Typical workflow

Once onboarding is complete, pass a prompt like this to your AI agent:

```
Generate a vending machine with separate door, glass panel, coin slot,
button grid, frame, and interior shelving.
```

The agent calls `generate_3d`. You get back:

```json
{
  "glb_url": "https://nova3d.xyz/assets/abc123.glb",
  "conversation_url": "https://app.nova3d.xyz/chat/conv-...",
  "parts": ["door", "glass_panel", "coin_slot", "button_grid", "frame", "shelf_1", "shelf_2"],
  "joint_count": 1,
  "code_artifact": { ... },
  "workflow_id": "state-..."
}
```

- **`conversation_url`** — your editing session in the Nova3D app, with the generated model and edit history already hydrated. All subsequent `regenerate_part`, `add_part`, and `articulate_model` calls on this asset link back to the same session.

---

## Configuration notes

- `conversation_url` is the standard supported way to inspect generated assets — it opens your fully hydrated editing session in the Nova3D app.
- Preferred onboarding is browser sign-in through `nova3d_login`, then `nova3d_status` to confirm credits/readiness.
- `nova3d_login` opens a browser tab and starts local MCP session setup through a loopback callback.
- `nova3d_status` is the canonical follow-up check for authentication, credits, and readiness.
- Keep secrets out of checked-in workspace config when possible. Prefer
  per-user configuration files or client-managed environment variables.
- If your editor supports source-controlled MCP config, commit the server entry
  and inject `NOVA3D_TOKEN` per-user only for the advanced/manual fallback path.

---

## Troubleshooting

| Problem | What to check |
|---|---|
| Prompted to sign in before generation | Call `nova3d_login`, then re-check with `nova3d_status` |
| `nova3d_login` returns `login_pending_confirmation: true` | Finish the browser sign-in step, then call `nova3d_status` |
| Browser sign-in finished but `nova3d_login` did not confirm completion | Call `nova3d_status` now. If it still shows not signed in, retry `nova3d_login` |
| Told that credits are required | Follow the purchase link returned by `nova3d_status` |
| Auth failure on startup | Sign in again with `nova3d_login`, or confirm the manual key at https://app.nova3d.xyz/api-key |
| `uvx` not found | Install `uv` or use a local `nova3d-mcp` executable from a virtualenv |
| No 3D preview inside the editor | Open the returned `conversation_url` in the browser; that is the supported preview path |

---

## Tools

### `generate_3d`

Generate a structured 3D asset from text (and optional reference image).
Initial generation runs through Nova3D's paid GraphFlow v2 workflow. This MCP
server does not expose BYOK/provider-key generation.

| Parameter | Type | Required | Description |
|---|---|---|---|
| `prompt` | string | ✓ | Asset description. Be specific about parts. |
| `model` | string | | Paid routing preset: `"gemini"` (default) · `"claude-sonnet"` · `"claude-opus"` · `"claude-opus-latest"` · `"gpt-5.5"` |
| `image_base64` | string | | Reference image as plain base64; the server converts it to the v2 `image_artifact` data-URL format |
| `image_mime` | string | | e.g. `"image/jpeg"` |

**Returns:** `glb_url`, `conversation_url`, `parts`, `joint_count`, `code_artifact`, `model_artifact`, `workflow_id`. Pass `code_artifact` to any edit tool. Open `conversation_url` to see the full edit history for this asset in the Nova3D app.

---

### `regenerate_part`

Regenerate one named part without rebuilding the whole asset.

| Parameter | Type | Required | Description |
|---|---|---|---|
| `code_artifact` | object | ✓ | From prior `generate_3d` result |
| `part_type` | string | ✓ | Part name e.g. `"door"`, `"handle"` |
| `description` | string | ✓ | What the new part should look like |
| `model` | string | | `"gemini"` (default) · `"claude-sonnet"` · `"claude-opus"` · `"claude-opus-latest"` · `"gpt-5.5"` |

**Finding part names:** Open the `conversation_url` from your generation and
inspect the model viewer — each mesh is labeled. Use that exact name as
`part_type`.

---

### `add_part`

Add a new component to an existing asset.

| Parameter | Type | Required | Description |
|---|---|---|---|
| `code_artifact` | object | ✓ | From prior generation result |
| `description` | string | ✓ | Description of the new part and where it goes |
| `model` | string | | `"gemini"` (default) · `"claude-sonnet"` · `"claude-opus"` · `"claude-opus-latest"` · `"gpt-5.5"` |

---

### `articulate_model`

Add joints, hinges, or rotational articulation to an existing asset.

| Parameter | Type | Required | Description |
|---|---|---|---|
| `code_artifact` | object | ✓ | From prior generation result |
| `articulation_request` | string | ✓ | What should move and how |
| `model_url` | string | | `glb_url` from prior generation. Provide this or `model_artifact`. |
| `model_artifact` | object | | `model_artifact` from prior generation. Provide this or `model_url`. |
| `model` | string | | `"gemini"` (default) · `"claude-sonnet"` · `"claude-opus"` · `"claude-opus-latest"` · `"gpt-5.5"` |
| `selected_meshes` | list | | Specific mesh names to articulate |

---

### `get_generation_status`

Check the status of a running workflow by ID.

| Parameter | Type | Required | Description |
|---|---|---|---|
| `workflow_id` | string | ✓ | From any prior generation tool |

---

### `nova3d_login`

Start the preferred browser-based Nova3D sign-in flow and store a local MCP session.
This opens a browser tab. If the browser flow finishes but local completion is
ambiguous, call `nova3d_status` before using manual token fallback.

---

### `nova3d_status`

Return the canonical Nova3D onboarding/readiness state, including identity,
credits, generation readiness, and the next recommended action.

---

### `nova3d_logout`

Clear the locally stored MCP session. This does not remove an advanced/manual
`NOVA3D_TOKEN` from your MCP config.

---

## Typical workflow

```
1. generate_3d("robot dog with four legs, head, torso, and tail")
   → glb_url, conversation_url, parts, code_artifact

2. Open conversation_url in browser
   → see named parts, identify what needs changing

3. regenerate_part(code_artifact, part_type="head", description="...")
   → updated glb_url, same conversation_url

4. add_part(code_artifact, description="a wagging tail with three segments")
   → updated glb_url, parts list now includes new tail segments

5. articulate_model(code_artifact, model_url, "make legs rotate at hip joints")
   → glb_url with working joints
```

All edit tools accept the `code_artifact` from any prior result and return an updated one. Always pass the most recent `code_artifact` forward — it carries the session state that links your edits together.

---

## Model reference

| `model` value | Provider | Notes |
|---|---|---|
| `"gemini"` *(default)* | Google Gemini | Recommended for spatial reasoning |
| `"claude-sonnet"` | Anthropic | Strong reasoning |
| `"claude-opus"` | Anthropic | Most capable Anthropic model |
| `"claude-opus-latest"` | Anthropic | Latest Opus version |
| `"gpt-5.5"` | OpenAI | Latest GPT model |

---

## Environment variables

| Variable | Required | Description |
|---|---|---|
| `NOVA3D_TOKEN` | | Advanced/manual fallback API key from https://app.nova3d.xyz/api-key |
| `NOVA3D_API_URL` | | Override API base URL (default: `https://nova3d.xyz/api`) |
| `NOVA3D_APP_URL` | | Override app URL for conversation links (default: `https://app.nova3d.xyz`) |

---

## How it differs from blender-mcp

[blender-mcp](https://github.com/ahujasid/blender-mcp) (21.9k ★) gives AI
agents a remote control for a **locally running Blender instance**. It requires
Blender installed, produces unstructured output, and inherits all the bpy
hallucination problems of raw LLM → Blender code generation.

nova3d-mcp is different in kind:

| | blender-mcp | nova3d-mcp |
|---|---|---|
| Blender required | Yes | No |
| Output | Unstructured scene | Named, hierarchical GLB |
| Validation | None | Server-side repair loop |
| Part awareness | No | Yes — named, addressable |
| Joints | Manual scripting | First-class output |
| Hosted backend | No | Yes |

---

## Contributing

Issues, PRs, and workflow feedback welcome.
[github.com/RareSense/nova3d-mcp](https://github.com/RareSense/nova3d-mcp)

Community Discord: [discord.gg/QEH8mzcwdR](https://discord.gg/QEH8mzcwdR)

---

## License

MIT — see [LICENSE](LICENSE)
