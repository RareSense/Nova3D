I traced the Nova3D client. The source of truth for GraphFlow calls is [cad_service.dart](/home/nimz/Nova3D/Nova3D/lib/features/cad/data/cad_service.dart:92), with workflow constants in [constants.dart](/home/nimz/Nova3D/Nova3D/lib/core/constants.dart:13).

**Shared Rules**
Base URL:
`CAD_BASE_URL`, default `https://nova3d.xyz/api`

Auth:
`Authorization: Bearer <token>`

For MCP, this should become:
`Authorization: Bearer n3d_...`

All workflow starts use:

```http
POST /run/state/{workflow}?request_id={workflowId}
Content-Type: application/json
```

`workflowId` format used by client:

```text
state-{DateTime.now().microsecondsSinceEpoch}
```

After start, client polls:

```http
GET /status/{workflowId}
GET /result/{workflowId}
```

Readiness check before generation:

```http
GET /workflow/readiness/sketch_to_3d
```

**Model Options**
Allowed `modelOptionId -> provider/llm` values from [generation_model_option.dart](/home/nimz/Nova3D/Nova3D/lib/features/cad/models/generation_model_option.dart:62):

```text
anthropic_claude_sonnet      provider=anthropic  llm=claude-sonnet
anthropic_claude_opus        provider=anthropic  llm=claude-opus
anthropic_claude_opus_latest provider=anthropic  llm=claude-opus-latest
openai_gpt55                 provider=openai     llm=gpt55
gemini_gemini                provider=gemini     llm=gemini
```

Only providers with locally stored valid keys appear in the UI:
`anthropic`, `openai`, `gemini`.

**Generation**
Endpoint:

```http
POST /run/state/sketch_to_3d?request_id={workflowId}
```

Body from [cad_service.dart](/home/nimz/Nova3D/Nova3D/lib/features/cad/data/cad_service.dart:102):

```json
{
  "payload": {
    "prompt": "trimmed user prompt",
    "llm": "claude-sonnet | claude-opus | claude-opus-latest | gpt55 | gemini",
    "provider": "anthropic | openai | gemini",
    "api_key": "provider API key",
    "validate": false,
    "image_base64": "optional raw base64 without data URL prefix",
    "image_mime": "optional image/png | image/jpeg | image/webp"
  },
  "return_nodes": ["sketch_to_3d_generator"]
}
```

Allowed/used fields:

```text
prompt        required if no image; string; trimmed
llm           required; one of model option llm values above
provider      required; anthropic/openai/gemini
api_key       required by current client
validate      always false
image_base64  optional; included only when image attached
image_mime    optional; image/png default, image/jpeg for jpg/jpeg, image/webp for webp
```

Image limit from UI:
`8 MB`, from `kMaxReferenceImageBytes`.

**Regenerate / Edit Selected Part**
Endpoint:

```http
POST /run/state/regenerate_3d_part?request_id={workflowId}
```

Body:

```json
{
  "payload": {
    "code_artifact": {},
    "description": "trimmed edit description",
    "part_type": "selected part or selected mesh names",
    "llm": "claude-sonnet | claude-opus | claude-opus-latest | gpt55 | gemini",
    "provider": "anthropic | openai | gemini",
    "api_key": "provider API key"
  },
  "return_nodes": ["regenerate_3d_part"]
}
```

Allowed/used fields:

```text
code_artifact required; object from previous /result
description   required; non-empty after trim
part_type     optional in method, always sent; defaults to "selected part"
llm           required
provider      required
api_key       required by current client
```

Client part type behavior:
The viewer uses up to 4 selected mesh names joined by `, `, otherwise `selected part`.

**Add / Grow Part**
Endpoint:

```http
POST /run/state/add_3d_part?request_id={workflowId}
```

Body:

```json
{
  "payload": {
    "code_artifact": {},
    "description": "trimmed add-part description",
    "llm": "claude-sonnet | claude-opus | claude-opus-latest | gpt55 | gemini",
    "provider": "anthropic | openai | gemini",
    "api_key": "provider API key"
  },
  "return_nodes": ["add_3d_part"]
}
```

Allowed/used fields:

```text
code_artifact required; object from previous /result
description   required; non-empty after trim
llm           required
provider      required
api_key       required by current client
```

**Articulation**
Endpoint:

```http
POST /run/state/articulate_3d_model?request_id={workflowId}
```

Body from [cad_service.dart](/home/nimz/Nova3D/Nova3D/lib/features/cad/data/cad_service.dart:178):

```json
{
  "payload": {
    "code_artifact": {},
    "model_url": "optional server-readable GLB URL",
    "model_artifact": {},
    "instruction_prompt": "optional original generation prompt",
    "articulation_request": "optional articulation instruction",
    "selected_meshes": ["optional mesh names"],
    "screenshots": ["optional screenshot strings"],
    "llm": "claude-sonnet | claude-opus | claude-opus-latest | gpt55 | gemini",
    "provider": "anthropic | openai | gemini",
    "api_key": "provider API key"
  },
  "return_nodes": ["articulate_3d_model"]
}
```

Allowed/used fields:

```text
code_artifact          required
model_url              optional, but required if model_artifact missing; blob: URLs are stripped
model_artifact         optional, but required if model_url missing
instruction_prompt     optional; included only if non-empty
articulation_request   optional; included only if non-empty
selected_meshes        optional; list of non-empty strings
screenshots            optional; list of non-empty strings
llm                    required
provider               required
api_key                required by current client
```

Important client nuance:
The Dart service supports `selected_meshes` and `screenshots`, but the current web bridge in [web/index.html](/home/nimz/Nova3D/Nova3D/web/index.html:477) only forwards `requestId`, `operation`, `description`, `partType`, `codeArtifact`, `sourceWorkflowId`, and `modelOptionId` from the iframe. So in the actual current browser path, articulation usually falls back to the Flutter widget's stored `modelArtifact`, `sourceModelUrl`, and `instructionPrompt`, while `selectedMeshes` and `screenshots` effectively arrive empty unless that bridge is expanded.

**Result Parsing**
The client expects `/result/{workflowId}` to contain one of these node keys:

```text
sketch_to_3d_generator
regenerate_3d_part
add_3d_part
articulate_3d_model
```

It extracts:

```text
model_url
model.url
model_artifact.url
code_artifact
source_code_artifact
input_code_artifact
model_artifact
model
joints_artifact
joints
joint_count
operation
cost
failure
```

So for the MCP server, the clean direct-backend mapping is: use the four `POST /run/state/...` payloads above, then poll `/status/{workflowId}` until terminal, then read `/result/{workflowId}` and parse the same node/result fields.
